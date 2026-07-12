## roche/store — 粒子ストア（設計書 §16 永続化）
##
## メモリ上の Table ＋ 追記専用ログ（WAL 兼データファイル）。
## - 追記専用は環の WORM 性（概念書 6.3④）とそのまま噛み合う。
## - flush はバッチ（128件 or 1ms）: プロセスクラッシュには安全、
##   OS クラッシュでは直近バッチを失い得る（歯止め: §16）。fsync は将来のノブ。
## - compact は生存レコードだけで WAL を再構築する。backup/restore は
##   compact 済み WAL を別ディレクトリへ退避・復元する。完全な snapshot
##   世代管理や fsync 付き checkpoint は今後の運用ノブ。
##
## レコード形式（長さ接頭辞つきテキスト。payload はバイナリ安全）:
##   G <len>\n<galaxy>\n                                      銀河系ID
##   GD <len>\n<description>\n                              銀河系説明
##   N <ringKey> <len>\n<name>\n                               環名
##   RD <ringKey> <len>\n<description>\n                     環説明
##   R <ringKey> <period> <head>\n                             環メタ
##   RP <ringKey> <len>\n<json>\n                              環payload profile
##   P <parent> <seq> <period> <head> <tWrite> <len> <dim> <codec>\n<payload><vec>\n
##                                                               粒子 upsert
##   E <parent> <seq> <dim>\n<dim×float32>\n                    埋め込み
##   F <oldParent> <oldSeq> <newParent> <newSeq> <newTWrite> <expiresAt>\n フォワーダ
##   D <parent> <seq>\n                                        削除（ハンドオフ退去）
##   T <txid>\n / XP|XD|XF <txid> ... / C <txid>\n           atomic transaction
##   CT <txid>\n / CP <txid> ... / CC <txid>\n                cluster tx intent
##   CA <txid>\n                                          cluster tx applied
##   WJ <jobId> <len>\n<json>\n                         warp belt job snapshot
##   WD <jobId>\n                                      warp belt job delete tombstone
##   UJ <eventId> <len>\n<json>\n                    universe sync event snapshot
##   UD <eventId>\n                                    universe sync event delete tombstone
##   UA <len>\n<eventKey>\n                         universe sync event applied marker
##   Q <nextTxId>\n                                      次の transaction id

import std/[tables, os, streams, strutils, monotimes, times, posix, json]
import nimsodium
import payload

export payload

type
  StoreDurability* = enum
    durBuffered    ## batched flush: fast, may lose the last batch on OS crash
    durStrong      ## flush + fsync every write boundary

  Particle* = object
    parent*: uint64
    seq*: uint32
    period*: float
    head*: float
    tWrite*: float
    payload*: string
    codec*: PayloadCodec
    vec*: seq[float32]
    # serving 状態（永続化しない）
    sentAhead*: bool
    lastHere*: float

  Forwarder* = object
    newParent*: uint64
    newSeq*: uint32
    newTWrite*: float
    expiresAt*: float

  TxOpKind = enum
    txRingMeta, txUpsert, txRemove, txForwarder

  TxOp = object
    case kind: TxOpKind
    of txRingMeta:
      ringKey: uint64
      ringPeriod: float
      ringHead: float
    of txUpsert:
      p: Particle
    of txRemove:
      remParent: uint64
      remSeq: uint32
    of txForwarder:
      oldParent: uint64
      oldSeq: uint32
      f: Forwarder

  StoreTxn* = ref object
    store: Store
    id: uint64
    ops: seq[TxOp]
    closed: bool

  ClusterTxOpKind* = enum
    ctxPut, ctxDelete

  ClusterTxOp* = object
    kind*: ClusterTxOpKind
    parent*: uint64
    seq*: uint32
    period*: float
    head*: float
    tWrite*: float
    payload*: string
    codec*: PayloadCodec
    vec*: seq[float32]

  ClusterTxIntent* = object
    id*: uint64
    ops*: seq[ClusterTxOp]
    committed*: bool
    applied*: bool

  StoreCompactStats* = object
    beforeBytes*: BiggestInt
    afterBytes*: BiggestInt
    items*: int
    forwarders*: int
    ringMeta*: int
    ringNames*: int
    clusterTx*: int
    appliedClusterTx*: int
    warpJobs*: int
    universeSyncEvents*: int

  StoreBackupStats* = object
    bytes*: BiggestInt
    items*: int
    forwarders*: int
    ringMeta*: int
    ringNames*: int
    clusterTx*: int
    appliedClusterTx*: int
    warpJobs*: int
    universeSyncEvents*: int
    source*: string
    destination*: string

  Store* = ref object
    items*: Table[(uint64, uint32), Particle]
    itemsByRing*: Table[uint64, seq[(uint64, uint32)]]
    forwarders*: Table[(uint64, uint32), Forwarder]
    seqs*: Table[uint64, uint32]                    # ring → 次の seq
    ringMeta*: Table[uint64, tuple[period, head: float]]
    ringNames*: Table[uint64, string]
    ringDescriptions*: Table[uint64, string]
    ringPayloadProfiles*: Table[uint64, RingPayloadProfile]
    galaxy*: string
    galaxyDescription*: string
    clusterTx*: Table[uint64, ClusterTxIntent]
    appliedClusterTx*: Table[uint64, bool]
    warpJobs*: Table[uint64, string]
    universeSyncEvents*: Table[uint64, string]
    appliedUniverseSyncEvents*: Table[string, bool]
    maxTWrite*: float
    nextTxId: uint64
    logFile: File
    logPath: string
    persistent: bool
    durability*: StoreDurability
    dirty: int
    lastFlush: MonoTime

const
  FlushEvery = 128
  FlushNs = 1_000_000   # 1ms
  MaxStoreRecordBytes = 64 * 1024 * 1024
  MaxStoreVectorDim = MaxStoreRecordBytes div sizeof(float32)
  EncryptedBackupMagic = "ROCHEDB-BACKUP-SECRETBOX-V1\n"

proc key(parent: uint64, seq: uint32): (uint64, uint32) = (parent, seq)

proc writeVec(file: File, vec: seq[float32]) =
  for x in vec:
    var y = x
    discard file.writeBuffer(addr y, sizeof(float32))

proc checkedStoreLen(n: int, label: string): int =
  if n < 0:
    raise newException(ValueError, label & " must be non-negative")
  if n > MaxStoreRecordBytes:
    raise newException(ValueError, label & " exceeds max store record bytes")
  n

proc checkedStoreVecDim(n: int): int =
  if n < 0:
    raise newException(ValueError, "vecDim must be non-negative")
  if n > MaxStoreVectorDim:
    raise newException(ValueError, "vecDim exceeds max store vector dimensions")
  n

proc readVec(fs: FileStream, dim: int): seq[float32] =
  let dim = checkedStoreVecDim(dim)
  result = newSeq[float32](dim)
  for i in 0 ..< dim:
    if fs.readData(addr result[i], sizeof(float32)) != sizeof(float32):
      raise newException(IOError, "埋め込みレコードが途中で終わった")

proc readExactStr(fs: FileStream, len: int): string =
  let len = checkedStoreLen(len, "payloadLen")
  result = fs.readStr(len)
  if result.len != len:
    raise newException(IOError, "WAL レコードが途中で終わった")

proc readRecordSep(fs: FileStream) =
  if fs.atEnd:
    raise newException(IOError, "WAL レコード末尾の改行がない")
  discard fs.readChar()

proc applyOp(s: Store, op: TxOp) =
  case op.kind
  of txRingMeta:
    s.ringMeta[op.ringKey] = (op.ringPeriod, op.ringHead)
  of txUpsert:
    let p = op.p
    let k = key(p.parent, p.seq)
    s.maxTWrite = max(s.maxTWrite, p.tWrite)
    if p.seq >= s.seqs.getOrDefault(p.parent, 0'u32):
      s.seqs[p.parent] = p.seq + 1
    if k notin s.items:
      s.itemsByRing.mgetOrPut(p.parent, @[]).add k
    s.items[k] = p
  of txRemove:
    let k = key(op.remParent, op.remSeq)
    s.items.del k
    if op.remParent in s.itemsByRing:
      var entries = s.itemsByRing[op.remParent]
      for i in countdown(entries.len - 1, 0):
        if entries[i] == k:
          entries.delete(i)
          break
      if entries.len == 0:
        s.itemsByRing.del op.remParent
      else:
        s.itemsByRing[op.remParent] = entries
    s.forwarders.del k
  of txForwarder:
    s.forwarders[key(op.oldParent, op.oldSeq)] = op.f

proc applyOps(s: Store, ops: seq[TxOp]) =
  for op in ops:
    s.applyOp(op)

proc writeParticleRecord(file: File, tag: string, txid: uint64, p: Particle) =
  let prefix = if tag.len > 0: tag & " " & $txid & " " else: "P "
  file.write(prefix & $p.parent & " " & $p.seq & " " & $p.period & " " &
             $p.head & " " & $p.tWrite & " " & $p.payload.len & " " &
             $p.vec.len & " " & p.codec.payloadCodecName & "\n")
  file.write(p.payload)
  if p.vec.len > 0:
    file.writeVec(p.vec)
  file.write("\n")

proc writeClusterTxOp(file: File, txid: uint64, op: ClusterTxOp) =
  let kind = if op.kind == ctxDelete: "D" else: "P"
  file.write("CP " & $txid & " " & kind & " " & $op.parent & " " & $op.seq & " " &
             $op.period & " " & $op.head & " " & $op.tWrite & " " &
             $op.payload.len & " " & $op.vec.len & " " &
             op.codec.payloadCodecName & "\n")
  file.write(op.payload)
  if op.vec.len > 0:
    file.writeVec(op.vec)
  file.write("\n")

proc readParticleRecord(fs: FileStream, parts: seq[string], firstData: int): Particle =
  result = Particle(parent: parseBiggestUInt(parts[firstData]).uint64,
                    seq: parseUInt(parts[firstData + 1]).uint32,
                    period: parseFloat(parts[firstData + 2]),
                    head: parseFloat(parts[firstData + 3]),
                    tWrite: parseFloat(parts[firstData + 4]))
  let len = parseInt(parts[firstData + 5])
  let dim = if parts.len > firstData + 6: parseInt(parts[firstData + 6]) else: 0
  result.codec = if parts.len > firstData + 7:
                   parsePayloadCodec(parts[firstData + 7])
                 else:
                   pcRaw
  result.payload = fs.readExactStr(len)
  result.vec = fs.readVec(dim)
  fs.readRecordSep()

proc readClusterTxOp(fs: FileStream, parts: seq[string], firstData: int): ClusterTxOp =
  var data = firstData
  result.kind = ctxPut
  if parts.len > firstData and (parts[firstData] == "P" or parts[firstData] == "D"):
    result.kind = if parts[firstData] == "D": ctxDelete else: ctxPut
    inc data
  result.parent = parseBiggestUInt(parts[data]).uint64
  result.seq = parseUInt(parts[data + 1]).uint32
  result.period = parseFloat(parts[data + 2])
  result.head = parseFloat(parts[data + 3])
  result.tWrite = parseFloat(parts[data + 4])
  let len = parseInt(parts[data + 5])
  let dim = if parts.len > data + 6: parseInt(parts[data + 6]) else: 0
  result.codec = if parts.len > data + 7:
                   parsePayloadCodec(parts[data + 7])
                 else:
                   pcRaw
  result.payload = fs.readExactStr(len)
  result.vec = fs.readVec(dim)
  fs.readRecordSep()

proc truncateLog(path: string, size: int64) =
  if posix.truncate(path.cstring, posix.Off(size)) != 0:
    raiseOSError(osLastError())

proc syncFile(file: File) =
  file.flushFile()
  when not defined(windows):
    if posix.fsync(cint(file.getFileHandle())) != 0:
      raiseOSError(osLastError())

proc syncDir(path: string) =
  when not defined(windows):
    let dirPath = if path.len == 0: "." else: path
    let fd = posix.open(dirPath.cstring, posix.O_RDONLY)
    if fd >= 0:
      try:
        if posix.fsync(fd) != 0:
          raiseOSError(osLastError())
      finally:
        discard posix.close(fd)

proc backupKey(passphrase: string): SecretBoxKey =
  if passphrase.len == 0:
    raise newException(ValueError, "backup passphrase is empty")
  secretBoxKeyFromBytes(genericHash("rochedb-backup-v1\0" & passphrase,
                                    SecretBoxKeyBytes))

proc endsWithNewline(path: string): bool =
  if not fileExists(path) or getFileSize(path) == 0:
    return true
  var f = open(path, fmRead)
  try:
    f.setFilePos(getFileSize(path) - 1)
    var buf: array[1, char]
    result = f.readChars(buf) == 1 and buf[0] == '\n'
  finally:
    f.close()

proc truncateMissingFinalNewline(path: string) =
  if endsWithNewline(path):
    return
  var f = open(path, fmRead)
  try:
    var pos = getFileSize(path) - 1
    var buf: array[1, char]
    while pos >= 0:
      f.setFilePos(pos)
      if f.readChars(buf) == 1 and buf[0] == '\n':
        truncateLog(path, pos + 1)
        return
      dec pos
    truncateLog(path, 0)
  finally:
    f.close()

proc replay(s: Store, path: string, repair = true) =
  if repair:
    truncateMissingFinalNewline(path)
  elif not endsWithNewline(path):
    raise newException(IOError, "WAL snapshot is missing final newline")
  let fs = newFileStream(path, fmRead)
  if fs.isNil: return
  var line = ""
  var pending = initTable[uint64, seq[TxOp]]()
  var pendingCluster = initTable[uint64, ClusterTxIntent]()
  var lastGood = fs.getPosition()
  var repairTo = -1
  while true:
    if not fs.readLine(line):
      break
    if line.len == 0: continue
    let parts = line.split(' ')
    try:
      case parts[0]
      of "G":
        let len = parseInt(parts[1])
        s.galaxy = fs.readExactStr(len)
        fs.readRecordSep()
      of "GD":
        let len = parseInt(parts[1])
        s.galaxyDescription = fs.readExactStr(len)
        fs.readRecordSep()
      of "R":
        s.ringMeta[parseBiggestUInt(parts[1]).uint64] =
          (parseFloat(parts[2]), parseFloat(parts[3]))
      of "N":
        let ringKey = parseBiggestUInt(parts[1]).uint64
        let len = parseInt(parts[2])
        s.ringNames[ringKey] = fs.readExactStr(len)
        fs.readRecordSep()
      of "RD":
        let ringKey = parseBiggestUInt(parts[1]).uint64
        let len = parseInt(parts[2])
        let desc = fs.readExactStr(len)
        if desc.len == 0:
          s.ringDescriptions.del ringKey
        else:
          s.ringDescriptions[ringKey] = desc
        fs.readRecordSep()
      of "RP":
        let ringKey = parseBiggestUInt(parts[1]).uint64
        let len = parseInt(parts[2])
        let profile = parseJson(fs.readExactStr(len))
        s.ringPayloadProfiles[ringKey] = RingPayloadProfile(
          defaultCodec: parsePayloadCodec(profile{"defaultCodec"}.getStr("raw")),
          charset: profile{"charset"}.getStr(""),
          formatVersion: profile{"formatVersion"}.getStr(""))
        fs.readRecordSep()
      of "P":
        let p = fs.readParticleRecord(parts, 1)
        s.applyOp(TxOp(kind: txUpsert, p: p))
      of "E":
        let parent = parseBiggestUInt(parts[1]).uint64
        let seq = parseUInt(parts[2]).uint32
        let dim = parseInt(parts[3])
        let v = fs.readVec(dim)
        fs.readRecordSep()
        let k = key(parent, seq)
        if k in s.items:
          s.items[k].vec = v
      of "F":
        let oldParent = parseBiggestUInt(parts[1]).uint64
        let oldSeq = parseUInt(parts[2]).uint32
        s.forwarders[key(oldParent, oldSeq)] =
          Forwarder(newParent: parseBiggestUInt(parts[3]).uint64,
                    newSeq: parseUInt(parts[4]).uint32,
                    newTWrite: parseFloat(parts[5]),
                    expiresAt: parseFloat(parts[6]))
      of "D":
        let k = key(parseBiggestUInt(parts[1]).uint64, parseUInt(parts[2]).uint32)
        s.items.del k
        s.forwarders.del k
      of "T":
        let txid = parseBiggestUInt(parts[1]).uint64
        pending[txid] = @[]
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "XR":
        let txid = parseBiggestUInt(parts[1]).uint64
        pending.mgetOrPut(txid, @[]).add TxOp(kind: txRingMeta,
                                              ringKey: parseBiggestUInt(parts[2]).uint64,
                                              ringPeriod: parseFloat(parts[3]),
                                              ringHead: parseFloat(parts[4]))
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "XP":
        let txid = parseBiggestUInt(parts[1]).uint64
        let p = fs.readParticleRecord(parts, 2)
        pending.mgetOrPut(txid, @[]).add TxOp(kind: txUpsert, p: p)
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "XD":
        let txid = parseBiggestUInt(parts[1]).uint64
        pending.mgetOrPut(txid, @[]).add TxOp(kind: txRemove,
                                              remParent: parseBiggestUInt(parts[2]).uint64,
                                              remSeq: parseUInt(parts[3]).uint32)
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "XF":
        let txid = parseBiggestUInt(parts[1]).uint64
        pending.mgetOrPut(txid, @[]).add TxOp(kind: txForwarder,
                                              oldParent: parseBiggestUInt(parts[2]).uint64,
                                              oldSeq: parseUInt(parts[3]).uint32,
                                              f: Forwarder(newParent: parseBiggestUInt(parts[4]).uint64,
                                                           newSeq: parseUInt(parts[5]).uint32,
                                                           newTWrite: parseFloat(parts[6]),
                                                           expiresAt: parseFloat(parts[7])))
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "C":
        let txid = parseBiggestUInt(parts[1]).uint64
        if txid in pending:
          s.applyOps(pending[txid])
          pending.del txid
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "CT":
        let txid = parseBiggestUInt(parts[1]).uint64
        pendingCluster[txid] = ClusterTxIntent(id: txid)
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "CP":
        let txid = parseBiggestUInt(parts[1]).uint64
        let op = fs.readClusterTxOp(parts, 2)
        pendingCluster.mgetOrPut(txid, ClusterTxIntent(id: txid)).ops.add op
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "CC":
        let txid = parseBiggestUInt(parts[1]).uint64
        var intent = pendingCluster.getOrDefault(txid, ClusterTxIntent(id: txid))
        intent.committed = true
        intent.applied = s.appliedClusterTx.getOrDefault(txid, false)
        s.clusterTx[txid] = intent
        pendingCluster.del txid
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "CA":
        let txid = parseBiggestUInt(parts[1]).uint64
        s.appliedClusterTx[txid] = true
        if txid in s.clusterTx:
          s.clusterTx[txid].applied = true
        s.nextTxId = max(s.nextTxId, txid + 1)
      of "WJ":
        let jobId = parseBiggestUInt(parts[1]).uint64
        let len = parseInt(parts[2])
        s.warpJobs[jobId] = fs.readExactStr(len)
        fs.readRecordSep()
      of "WD":
        s.warpJobs.del parseBiggestUInt(parts[1]).uint64
      of "UJ":
        let eventId = parseBiggestUInt(parts[1]).uint64
        let len = parseInt(parts[2])
        s.universeSyncEvents[eventId] = fs.readExactStr(len)
        fs.readRecordSep()
      of "UD":
        s.universeSyncEvents.del parseBiggestUInt(parts[1]).uint64
      of "UA":
        let len = parseInt(parts[1])
        s.appliedUniverseSyncEvents[fs.readExactStr(len)] = true
        fs.readRecordSep()
      of "Q":
        s.nextTxId = max(s.nextTxId, parseBiggestUInt(parts[1]).uint64)
      else:
        discard   # 不明レコードは読み飛ばし（前方互換）
      lastGood = fs.getPosition()
    except CatchableError:
      if repair:
        repairTo = lastGood
        break
      fs.close()
      raise newException(IOError, "invalid WAL snapshot near byte " &
        $lastGood & ": " & getCurrentExceptionMsg())
  fs.close()
  if repairTo >= 0:
    truncateLog(path, repairTo.int64)

proc recoverCompaction(path: string) =
  let tmp = path & ".compact"
  let bak = path & ".bak"
  if not fileExists(path):
    if fileExists(tmp):
      moveFile(tmp, path)
    elif fileExists(bak):
      moveFile(bak, path)
  elif fileExists(tmp):
    removeFile(tmp)
  if fileExists(path) and fileExists(bak):
    removeFile(bak)

proc openStore*(dir: string, durability: StoreDurability = durBuffered): Store =
  ## dir == "" ならメモリのみ。指定時は dir/roche.log に追記・起動時に再生。
  result = Store(lastFlush: getMonoTime(), nextTxId: 1,
                 durability: durability)
  if dir.len > 0:
    createDir(dir)
    let path = dir / "roche.log"
    recoverCompaction(path)
    result.replay(path)
    result.logFile = open(path, fmAppend)
    result.logPath = path
    result.persistent = true

proc flushMaybe(s: Store, force = false)

proc setGalaxy*(s: Store, galaxy: string) =
  if galaxy.len == 0:
    return
  if s.galaxy.len > 0:
    doAssert s.galaxy == galaxy,
      "data dir belongs to galaxy '" & s.galaxy & "', not '" & galaxy & "'"
    return
  s.galaxy = galaxy
  if s.persistent:
    s.logFile.write("G " & $galaxy.len & "\n")
    s.logFile.write(galaxy)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc flushMaybe(s: Store, force: bool) =
  if not s.persistent: return
  inc s.dirty
  let nowM = getMonoTime()
  if force or s.durability == durStrong or s.dirty >= FlushEvery or
      (nowM - s.lastFlush).inNanoseconds > FlushNs:
    if s.durability == durStrong:
      s.logFile.syncFile()
    else:
      s.logFile.flushFile()
    s.dirty = 0
    s.lastFlush = nowM

proc sync*(s: Store) =
  if s.persistent: s.flushMaybe(force = true)

proc logSize*(s: Store): BiggestInt =
  if s.persistent and s.logPath.len > 0 and fileExists(s.logPath):
    getFileSize(s.logPath)
  else:
    0

proc isPersistent*(s: Store): bool =
  s.persistent

proc close*(s: Store) =
  if s.persistent:
    if s.durability == durStrong:
      s.logFile.syncFile()
    else:
      s.logFile.flushFile()
    s.logFile.close()
    s.persistent = false

proc writeSnapshotFile(s: Store, path: string) =
  var file = open(path, fmWrite)
  try:
    if s.galaxy.len > 0:
      file.write("G " & $s.galaxy.len & "\n")
      file.write(s.galaxy)
      file.write("\n")
    if s.galaxyDescription.len > 0:
      file.write("GD " & $s.galaxyDescription.len & "\n")
      file.write(s.galaxyDescription)
      file.write("\n")
    file.write("Q " & $s.nextTxId & "\n")
    for ringKey, name in s.ringNames:
      file.write("N " & $ringKey & " " & $name.len & "\n")
      file.write(name)
      file.write("\n")
    for ringKey, desc in s.ringDescriptions:
      if desc.len > 0:
        file.write("RD " & $ringKey & " " & $desc.len & "\n")
        file.write(desc)
        file.write("\n")
    for ringKey, profile in s.ringPayloadProfiles:
      let raw = $(%*{
        "defaultCodec": profile.defaultCodec.payloadCodecName,
        "charset": profile.charset,
        "formatVersion": profile.formatVersion
      })
      file.write("RP " & $ringKey & " " & $raw.len & "\n")
      file.write(raw)
      file.write("\n")
    for ringKey, meta in s.ringMeta:
      file.write("R " & $ringKey & " " & $meta.period & " " & $meta.head & "\n")
    for _, p in s.items:
      file.writeParticleRecord("", 0, p)
    for old, f in s.forwarders:
      file.write("F " & $old[0] & " " & $old[1] & " " & $f.newParent & " " &
                 $f.newSeq & " " & $f.newTWrite & " " & $f.expiresAt & "\n")
    for _, intent in s.clusterTx:
      file.write("CT " & $intent.id & "\n")
      for op in intent.ops:
        file.writeClusterTxOp(intent.id, op)
      if intent.committed:
        file.write("CC " & $intent.id & "\n")
      if intent.applied:
        file.write("CA " & $intent.id & "\n")
    for txid, applied in s.appliedClusterTx:
      if applied and txid notin s.clusterTx:
        file.write("CA " & $txid & "\n")
    for jobId, blob in s.warpJobs:
      file.write("WJ " & $jobId & " " & $blob.len & "\n")
      file.write(blob)
      file.write("\n")
    for eventId, blob in s.universeSyncEvents:
      file.write("UJ " & $eventId & " " & $blob.len & "\n")
      file.write(blob)
      file.write("\n")
    for eventKey, applied in s.appliedUniverseSyncEvents:
      if applied:
        file.write("UA " & $eventKey.len & "\n")
        file.write(eventKey)
        file.write("\n")
    if s.durability == durStrong:
      file.syncFile()
    else:
      file.flushFile()
  finally:
    file.close()

proc snapshotStats(s: Store, path: string, source = ""): StoreBackupStats =
  StoreBackupStats(bytes: (if fileExists(path): getFileSize(path) else: 0),
                   items: s.items.len,
                   forwarders: s.forwarders.len,
                   ringMeta: s.ringMeta.len,
                   ringNames: s.ringNames.len,
                   clusterTx: s.clusterTx.len,
                   appliedClusterTx: s.appliedClusterTx.len,
                   warpJobs: s.warpJobs.len,
                   universeSyncEvents: s.universeSyncEvents.len,
                   source: source,
                   destination: path)

proc snapshotStatsFromFile(path, source: string): StoreBackupStats =
  var s = Store(lastFlush: getMonoTime(), nextTxId: 1)
  s.replay(path, repair = false)
  result = s.snapshotStats(path, source)

proc compact*(s: Store): StoreCompactStats =
  ## 生存レコードだけで WAL を再構築する。
  ## append-only の読みやすさを保ちながら、削除済み/上書き済みログの肥大化を抑える。
  result.items = s.items.len
  result.forwarders = s.forwarders.len
  result.ringMeta = s.ringMeta.len
  result.ringNames = s.ringNames.len
  result.clusterTx = s.clusterTx.len
  result.appliedClusterTx = s.appliedClusterTx.len
  result.warpJobs = s.warpJobs.len
  result.universeSyncEvents = s.universeSyncEvents.len
  if not s.persistent or s.logPath.len == 0:
    return

  let path = s.logPath
  let tmp = path & ".compact"
  let bak = path & ".bak"
  s.flushMaybe(force = true)
  result.beforeBytes = getFileSize(path)
  s.logFile.close()
  s.writeSnapshotFile(tmp)
  if fileExists(bak):
    removeFile(bak)
  if fileExists(path):
    moveFile(path, bak)
  moveFile(tmp, path)
  result.afterBytes = getFileSize(path)
  if s.durability == durStrong:
    syncDir(parentDir(path))
  s.logFile = open(path, fmAppend)
  s.persistent = true
  s.dirty = 0
  s.lastFlush = getMonoTime()
  if fileExists(bak):
    removeFile(bak)
    if s.durability == durStrong:
      syncDir(parentDir(path))

proc backup*(s: Store, dstDir: string): StoreBackupStats =
  ## 現在の Store 状態を compact 済み WAL として dstDir/roche.log に退避する。
  ## 元の WAL は書き換えないため、通常運用中の backup に使える。
  if dstDir.len == 0:
    raise newException(ValueError, "backup destination is empty")
  createDir(dstDir)
  let dst = dstDir / "roche.log"
  let tmp = dst & ".tmp"
  if s.persistent:
    s.flushMaybe(force = true)
  s.writeSnapshotFile(tmp)
  if fileExists(dst):
    removeFile(dst)
  moveFile(tmp, dst)
  if s.durability == durStrong:
    syncDir(dstDir)
  result = s.snapshotStats(dst, s.logPath)

proc backupEncrypted*(s: Store, dstDir, passphrase: string): StoreBackupStats =
  ## 現在の Store 状態を secretbox で暗号化した snapshot として dstDir/roche.backup に退避する。
  if dstDir.len == 0:
    raise newException(ValueError, "backup destination is empty")
  createDir(dstDir)
  let dst = dstDir / "roche.backup"
  let tmpPlain = dstDir / "roche.log.tmp"
  let tmpEnc = dst & ".tmp"
  if s.persistent:
    s.flushMaybe(force = true)
  s.writeSnapshotFile(tmpPlain)
  try:
    let plaintext = readFile(tmpPlain)
    writeFile(tmpEnc, EncryptedBackupMagic &
      encryptSecretBox(plaintext, backupKey(passphrase)))
    if fileExists(dst):
      removeFile(dst)
    moveFile(tmpEnc, dst)
    if s.durability == durStrong:
      syncDir(dstDir)
    result = s.snapshotStats(dst, s.logPath)
  finally:
    if fileExists(tmpPlain):
      removeFile(tmpPlain)
    if fileExists(tmpEnc):
      removeFile(tmpEnc)

proc verifyBackup*(backupDir: string): StoreBackupStats =
  ## backupDir/roche.log を復元前に strict 検証する。通常 openStore の
  ## tail repair とは違い、backup 検証では壊れた snapshot を拒否する。
  if backupDir.len == 0:
    raise newException(ValueError, "backup directory is required")
  let src = backupDir / "roche.log"
  if not fileExists(src):
    raise newException(IOError, "backup roche.log not found: " & src)
  result = snapshotStatsFromFile(src, src)

proc verifyEncryptedBackup*(backupDir, passphrase: string): StoreBackupStats =
  ## backupDir/roche.backup を復号し、復元前に strict 検証する。
  if backupDir.len == 0:
    raise newException(ValueError, "backup directory is required")
  let src = backupDir / "roche.backup"
  if not fileExists(src):
    raise newException(IOError, "encrypted backup not found: " & src)
  let blob = readFile(src)
  if not blob.startsWith(EncryptedBackupMagic):
    raise newException(IOError, "invalid encrypted backup header")
  let plaintext = decryptSecretBox(blob[EncryptedBackupMagic.len .. ^1],
                                   backupKey(passphrase))
  let validateTmp = backupDir / "roche.verify.tmp"
  writeFile(validateTmp, plaintext)
  try:
    result = snapshotStatsFromFile(validateTmp, src)
    result.bytes = getFileSize(src)
    result.destination = src
  finally:
    if fileExists(validateTmp):
      removeFile(validateTmp)

proc restoreBackup*(backupDir, targetDir: string, overwrite = false): StoreBackupStats =
  ## backupDir/roche.log を targetDir/roche.log として復元する。
  ## 既存 target は overwrite=true のときだけ置き換える。
  if backupDir.len == 0 or targetDir.len == 0:
    raise newException(ValueError, "backup and target directories are required")
  let src = backupDir / "roche.log"
  if not fileExists(src):
    raise newException(IOError, "backup roche.log not found: " & src)
  discard verifyBackup(backupDir)
  createDir(targetDir)
  let dst = targetDir / "roche.log"
  if fileExists(dst) and not overwrite:
    raise newException(IOError, "target roche.log already exists: " & dst)
  if fileExists(dst):
    removeFile(dst)
  copyFile(src, dst)
  var restored = openStore(targetDir)
  try:
    result = restored.snapshotStats(dst, src)
  finally:
    restored.close()

proc restoreEncryptedBackup*(backupDir, targetDir, passphrase: string,
                             overwrite = false): StoreBackupStats =
  ## backupDir/roche.backup を復号し、targetDir/roche.log として復元する。
  if backupDir.len == 0 or targetDir.len == 0:
    raise newException(ValueError, "backup and target directories are required")
  let src = backupDir / "roche.backup"
  if not fileExists(src):
    raise newException(IOError, "encrypted backup not found: " & src)
  let blob = readFile(src)
  if not blob.startsWith(EncryptedBackupMagic):
    raise newException(IOError, "invalid encrypted backup header")
  let plaintext = decryptSecretBox(blob[EncryptedBackupMagic.len .. ^1],
                                   backupKey(passphrase))
  discard verifyEncryptedBackup(backupDir, passphrase)
  createDir(targetDir)
  let dst = targetDir / "roche.log"
  if fileExists(dst) and not overwrite:
    raise newException(IOError, "target roche.log already exists: " & dst)
  let tmp = dst & ".tmp"
  writeFile(tmp, plaintext)
  if fileExists(dst):
    removeFile(dst)
  moveFile(tmp, dst)
  var restored = openStore(targetDir)
  try:
    result = restored.snapshotStats(dst, src)
  finally:
    restored.close()

proc putRingMeta*(s: Store, ringKey: uint64, period, head: float) =
  s.applyOp(TxOp(kind: txRingMeta, ringKey: ringKey,
                 ringPeriod: period, ringHead: head))
  if s.persistent:
    s.logFile.write("R " & $ringKey & " " & $period & " " & $head & "\n")
    s.flushMaybe()

proc putRingName*(s: Store, ringKey: uint64, name: string) =
  if name.len == 0:
    return
  if s.ringNames.getOrDefault(ringKey, "") == name:
    return
  s.ringNames[ringKey] = name
  if s.persistent:
    s.logFile.write("N " & $ringKey & " " & $name.len & "\n")
    s.logFile.write(name)
    s.logFile.write("\n")
    s.flushMaybe()

proc putGalaxyDescription*(s: Store, description: string) =
  s.galaxyDescription = description
  if s.persistent:
    s.logFile.write("GD " & $description.len & "\n")
    s.logFile.write(description)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc putRingDescription*(s: Store, ringKey: uint64, description: string) =
  if description.len == 0:
    s.ringDescriptions.del ringKey
  else:
    s.ringDescriptions[ringKey] = description
  if s.persistent:
    s.logFile.write("RD " & $ringKey & " " & $description.len & "\n")
    s.logFile.write(description)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc putRingPayloadProfile*(s: Store, ringKey: uint64,
                            profile: RingPayloadProfile) =
  s.ringPayloadProfiles[ringKey] = profile
  if s.persistent:
    let raw = $(%*{
      "defaultCodec": profile.defaultCodec.payloadCodecName,
      "charset": profile.charset,
      "formatVersion": profile.formatVersion
    })
    s.logFile.write("RP " & $ringKey & " " & $raw.len & "\n")
    s.logFile.write(raw)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc putWarpJob*(s: Store, jobId: uint64, blob: string) =
  ## RocheDB layer が解釈する warp job snapshot を保存する。
  ## Store は WAL/compact/backup/restore だけを担当し、scheduler policy は持たない。
  if blob.len == 0:
    raise newException(ValueError, "warp job blob is empty")
  s.warpJobs[jobId] = blob
  if s.persistent:
    s.logFile.write("WJ " & $jobId & " " & $blob.len & "\n")
    s.logFile.write(blob)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc deleteWarpJob*(s: Store, jobId: uint64) =
  s.warpJobs.del jobId
  if s.persistent:
    s.logFile.write("WD " & $jobId & "\n")
    s.flushMaybe(force = true)

proc putUniverseSyncEvent*(s: Store, eventId: uint64, blob: string) =
  ## RocheDB layer が解釈する universe sync event snapshot を保存する。
  ## Store は durable queue / compact / backup / restore だけを担当する。
  if blob.len == 0:
    raise newException(ValueError, "universe sync event blob is empty")
  s.universeSyncEvents[eventId] = blob
  if s.persistent:
    s.logFile.write("UJ " & $eventId & " " & $blob.len & "\n")
    s.logFile.write(blob)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc deleteUniverseSyncEvent*(s: Store, eventId: uint64) =
  s.universeSyncEvents.del eventId
  if s.persistent:
    s.logFile.write("UD " & $eventId & "\n")
    s.flushMaybe(force = true)

proc markUniverseSyncEventApplied*(s: Store, eventKey: string) =
  if eventKey.len == 0:
    raise newException(ValueError, "universe sync event key is empty")
  if s.appliedUniverseSyncEvents.getOrDefault(eventKey, false):
    return
  s.appliedUniverseSyncEvents[eventKey] = true
  if s.persistent:
    s.logFile.write("UA " & $eventKey.len & "\n")
    s.logFile.write(eventKey)
    s.logFile.write("\n")
    s.flushMaybe(force = true)

proc isUniverseSyncEventApplied*(s: Store, eventKey: string): bool =
  s.appliedUniverseSyncEvents.getOrDefault(eventKey, false)

proc nextSeq*(s: Store, ring: uint64): uint32 =
  result = s.seqs.getOrDefault(ring, 0'u32)
  s.seqs[ring] = result + 1

proc upsert*(s: Store, p: Particle) =
  s.applyOp(TxOp(kind: txUpsert, p: p))
  if s.persistent:
    s.logFile.writeParticleRecord("", 0, p)
    s.flushMaybe()

proc putForwarder*(s: Store, oldParent: uint64, oldSeq: uint32, f: Forwarder) =
  s.forwarders[key(oldParent, oldSeq)] = f
  if s.persistent:
    s.logFile.write("F " & $oldParent & " " & $oldSeq & " " & $f.newParent & " " &
                    $f.newSeq & " " & $f.newTWrite & " " & $f.expiresAt & "\n")
    s.flushMaybe()

proc remove*(s: Store, parent: uint64, seq: uint32) =
  s.applyOp(TxOp(kind: txRemove, remParent: parent, remSeq: seq))
  if s.persistent:
    s.logFile.write("D " & $parent & " " & $seq & "\n")
    s.flushMaybe()

proc contains*(s: Store, parent: uint64, seq: uint32): bool =
  key(parent, seq) in s.items

proc count*(s: Store): int = s.items.len

proc clusterTxPending*(s: Store): int =
  for _, intent in s.clusterTx:
    if intent.committed and not intent.applied:
      inc result

proc clusterTxCommitted*(s: Store): int = s.clusterTx.len

proc clusterTxApplied*(s: Store): int =
  for _, intent in s.clusterTx:
    if intent.applied:
      inc result

proc isClusterTxApplied*(s: Store, txid: uint64): bool =
  s.appliedClusterTx.getOrDefault(txid, false) or
    (txid in s.clusterTx and s.clusterTx[txid].applied)

proc hasClusterTxIntent*(s: Store, txid: uint64): bool =
  txid in s.clusterTx

proc beginTxn*(s: Store): StoreTxn =
  result = StoreTxn(store: s, id: s.nextTxId)
  inc s.nextTxId

proc reserveTxId*(s: Store): uint64 =
  result = s.nextTxId
  inc s.nextTxId

proc upsert*(tx: StoreTxn, p: Particle) =
  doAssert not tx.closed, "transaction is closed"
  tx.ops.add TxOp(kind: txUpsert, p: p)

proc remove*(tx: StoreTxn, parent: uint64, seq: uint32) =
  doAssert not tx.closed, "transaction is closed"
  tx.ops.add TxOp(kind: txRemove, remParent: parent, remSeq: seq)

proc putForwarder*(tx: StoreTxn, oldParent: uint64, oldSeq: uint32, f: Forwarder) =
  doAssert not tx.closed, "transaction is closed"
  tx.ops.add TxOp(kind: txForwarder, oldParent: oldParent, oldSeq: oldSeq, f: f)

proc putRingMeta*(tx: StoreTxn, ringKey: uint64, period, head: float) =
  doAssert not tx.closed, "transaction is closed"
  tx.ops.add TxOp(kind: txRingMeta, ringKey: ringKey,
                  ringPeriod: period, ringHead: head)

proc rollback*(tx: StoreTxn) =
  tx.ops.setLen(0)
  tx.closed = true

proc commit*(tx: StoreTxn) =
  doAssert not tx.closed, "transaction is closed"
  let s = tx.store
  if s.persistent:
    s.logFile.write("T " & $tx.id & "\n")
    for op in tx.ops:
      case op.kind
      of txRingMeta:
        s.logFile.write("XR " & $tx.id & " " & $op.ringKey & " " &
                        $op.ringPeriod & " " & $op.ringHead & "\n")
      of txUpsert:
        s.logFile.writeParticleRecord("XP", tx.id, op.p)
      of txRemove:
        s.logFile.write("XD " & $tx.id & " " & $op.remParent & " " & $op.remSeq & "\n")
      of txForwarder:
        s.logFile.write("XF " & $tx.id & " " & $op.oldParent & " " & $op.oldSeq & " " &
                        $op.f.newParent & " " & $op.f.newSeq & " " &
                        $op.f.newTWrite & " " & $op.f.expiresAt & "\n")
    s.logFile.write("C " & $tx.id & "\n")
    s.flushMaybe(force = true)
  s.applyOps(tx.ops)
  tx.closed = true

proc putClusterTxIntent*(s: Store, intent: ClusterTxIntent) =
  s.clusterTx[intent.id] = intent
  if s.persistent:
    s.logFile.write("CT " & $intent.id & "\n")
    for op in intent.ops:
      s.logFile.writeClusterTxOp(intent.id, op)
    s.logFile.write("CC " & $intent.id & "\n")
    s.flushMaybe(force = true)

proc markClusterTxApplied*(s: Store, txid: uint64) =
  s.appliedClusterTx[txid] = true
  if txid in s.clusterTx:
    s.clusterTx[txid].applied = true
  if s.persistent:
    s.logFile.write("CA " & $txid & "\n")
    s.flushMaybe()
