## roched — RocheDB ノードサーバ（設計書 §14: スケールアウト実装）
##
## usage: roched --id=0 --peers=127.0.0.1:7301,127.0.0.1:7302,127.0.0.1:7303 [--data=DIR]
##   - peers リスト内の自分の位置が弧の担当を決める（等分割, epoch 1）
##   - 時計は wall clock（NTP 有界スキュー前提 = 設計書 §6.3 の guard band 側で吸収）
##   - ハンドオフ: 粒子が弧境界を越える前に後続ノードへ先送り（lookahead）し、
##     越えたあとも猶予期間（grace）は手元に残す = §6.1 の「先読み＋尾流」の最小版
##   - --data を与えると追記ログに永続化（§16）。再起動後は再生 → 自分の弧に
##     ないものはハンドオフが自然に掃き出す（自己修復）

import std/[algorithm, selectors, net, os, strutils, times, monotimes, json, tables, parseopt, hashes]
import roche/[core, store, select, wire, field, auth]

const
  Lookahead = 0.5   # [s] 境界のこれだけ前に後続へ複製を送る
  Grace = 1.0       # [s] 所有を失ってから削除するまでの猶予（= 尾流 w の時間版）
  TickMs = 100      # ハンドオフ判定の周期
  DefaultSlowTickSec = 10.0
  MaxTransfersPerTick = 256   # 一括移動時も select ループを塞がない上限
  DefaultPeriod = 60.0
  MaxWireBodyBytes = 64 * 1024 * 1024
  MaxWireVectorDim = MaxWireBodyBytes div sizeof(float32)

type
  UserRole = enum
    roleReader, roleWriter, roleAdmin

  UserRule = object
    password: string
    role: UserRole
    prefixes: seq[string]

  Server = ref object
    myId: int
    peers: seq[Peer]
    tbl: ArcTable
    st: Store
    fs: FieldState
    peerLink: ClusterClient
    slowTickSec: float
    running: bool
    authUser: string
    authPassword: string
    authSecretKey: string
    users: Table[string, UserRule]
    galaxy: string
    allowedRingPrefixes: seq[string]
    authed: Table[int, bool]
    authedUsers: Table[int, string]
    authChallenges: Table[int, string]
    startedAt: float
    requestCount: uint64
    errorResponses: uint64
    authFailures: uint64
    authzDenied: uint64
    connectionsAccepted: uint64
    activeConnections: int
    universeApplyApplied: uint64
    universeApplySkipped: uint64
    universeApplyErrors: uint64
    universeApplyForwarded: uint64
    universeApplyLastOk: float
    universeApplyLastError: float

type LocalHit = object
  parent: uint64
  seq: uint32
  tWrite: float
  score: float
  payload: string

proc orbitOf(p: Particle): Orbit =
  OrbitalId(parent: p.parent, epoch: 1, tWrite: p.tWrite, seq: p.seq)
    .ringOrbit(p.period, p.head)

proc ringInfo(sv: Server, name: string): tuple[key: uint64, period, head: float] =
  if name == "halo":
    result = (key: HaloKey, period: HaloPeriod, head: 0.0)
  else:
    let key = uint64(hash(name)) or 1'u64
    result = (key: key, period: DefaultPeriod, head: float(key mod 628) / 100.0)
  if result.key notin sv.st.ringMeta:
    sv.st.putRingMeta(result.key, result.period, result.head)
  if result.key notin sv.st.ringNames or sv.st.ringNames[result.key] != name:
    sv.st.putRingName(result.key, name)

proc authzEnabled(sv: Server): bool =
  sv.allowedRingPrefixes.len > 0 or sv.users.len > 0

proc parseRole(s: string): UserRole =
  case s.toLowerAscii()
  of "reader", "read": roleReader
  of "writer", "write": roleWriter
  of "admin": roleAdmin
  else:
    raise newException(ValueError, "role must be reader, writer, or admin")

proc roleAllowed(role: UserRole, need: UserRole): bool =
  case need
  of roleReader: true
  of roleWriter: role in {roleWriter, roleAdmin}
  of roleAdmin: role == roleAdmin

proc parsePrefixes(s: string): seq[string] =
  for part in s.split(','):
    let prefix = part.strip()
    if prefix.len > 0:
      result.add prefix

proc parseUserRule(spec: string): tuple[user: string, rule: UserRule] =
  let parts = spec.split(':', maxsplit = 3)
  if parts.len < 3:
    raise newException(ValueError,
      "--role must be user:password:role[:prefix1,prefix2]")
  result.user = parts[0]
  result.rule = UserRule(password: parts[1],
                         role: parseRole(parts[2]),
                         prefixes: if parts.len >= 4: parsePrefixes(parts[3]) else: @[])
  if result.user.len == 0:
    raise newException(ValueError, "--role user must not be empty")

proc currentUser(sv: Server, sock: Socket): string =
  sv.authedUsers.getOrDefault(sock.getFd.int, sv.authUser)

proc userRule(sv: Server, user: string): UserRule =
  if user.len > 0 and user in sv.users:
    return sv.users[user]
  if sv.users.len > 0:
    return UserRule(password: "", role: roleReader, prefixes: @["__no-access__"])
  UserRule(password: sv.authPassword,
           role: roleAdmin,
           prefixes: sv.allowedRingPrefixes)

proc ringNameAllowed(sv: Server, name: string, user = ""): bool =
  if not sv.authzEnabled:
    return true
  let prefixes =
    if sv.users.len > 0: sv.userRule(user).prefixes
    else: sv.allowedRingPrefixes
  if prefixes.len == 0:
    return true
  for prefix in prefixes:
    if name == prefix or name.startsWith(prefix & "/"):
      return true
  false

proc ringKeyAllowed(sv: Server, ringKey: uint64, user = ""): bool =
  if not sv.authzEnabled:
    return true
  let name = sv.st.ringNames.getOrDefault(ringKey, "")
  name.len > 0 and sv.ringNameAllowed(name, user)

proc ringNameAllowed(sv: Server, sock: Socket, name: string): bool =
  sv.ringNameAllowed(name, sv.currentUser(sock))

proc ringKeyAllowed(sv: Server, sock: Socket, ringKey: uint64): bool =
  sv.ringKeyAllowed(ringKey, sv.currentUser(sock))

proc requireRole(sv: Server, sock: Socket, need: UserRole): bool =
  if sv.users.len == 0:
    return true
  let user = sv.currentUser(sock)
  let rule = sv.userRule(user)
  if roleAllowed(rule.role, need):
    return true
  inc sv.authzDenied
  inc sv.errorResponses
  sock.sendFrame("ERR authz-denied role=" & $rule.role)
  false

proc requireRingKey(sv: Server, sock: Socket, ringKey: uint64): bool =
  if sv.ringKeyAllowed(ringKey, sv.currentUser(sock)):
    return true
  inc sv.authzDenied
  inc sv.errorResponses
  sock.sendFrame("ERR authz-denied ringKey=" & $ringKey)
  false

proc drainBytes(sock: Socket, n: int) =
  if n > 0:
    discard sock.readExact(n)

proc checkedWireLen(n: int, label: string): int =
  if n < 0:
    raise newException(ValueError, label & " must be non-negative")
  if n > MaxWireBodyBytes:
    raise newException(ValueError, label & " exceeds max wire body bytes")
  n

proc checkedVecBytes(vecDim: int): int =
  if vecDim < 0:
    raise newException(ValueError, "vecDim must be non-negative")
  if vecDim > MaxWireVectorDim:
    raise newException(ValueError, "vecDim exceeds max wire vector dim")
  vecDim * sizeof(float32)

proc checkedFrameBytes(payloadLen, vecDim: int, extra = 0): int =
  let payloadBytes = checkedWireLen(payloadLen, "payloadLen")
  let vectorBytes = checkedVecBytes(vecDim)
  if extra < 0:
    raise newException(ValueError, "extra frame bytes must be non-negative")
  if payloadBytes > MaxWireBodyBytes - vectorBytes or
      payloadBytes + vectorBytes > MaxWireBodyBytes - extra:
    raise newException(ValueError, "frame body exceeds max wire body bytes")
  payloadBytes + vectorBytes + extra

proc denyRingName(sock: Socket, name: string) =
  sock.sendFrame("ERR authz-denied ring=" & name)

proc denyRingKey(sock: Socket, ringKey: uint64) =
  sock.sendFrame("ERR authz-denied ringKey=" & $ringKey)

proc drainTxCommitOps(sock: Socket, nOps: int) =
  for _ in 0 ..< nOps:
    let h = sock.readHeader()
    let data = if h[0] == "P" or h[0] == "D": 1 else: 0
    let payloadLen = parseInt(h[data + 5])
    let vecDim = parseInt(h[data + 6])
    sock.drainBytes(checkedFrameBytes(payloadLen, vecDim, extra = 1))

proc jsonFloat32Seq(node: JsonNode): seq[float32] =
  if node.isNil or node.kind != JArray:
    return @[]
  for item in node.items:
    case item.kind
    of JInt:
      result.add float32(item.getInt())
    of JFloat:
      result.add float32(item.getFloat())
    else:
      discard

proc applyUniverseEvent(sv: Server, event: JsonNode, now: float): bool =
  if event.kind != JObject:
    raise newException(ValueError, "universe event must be an object")
  let eventKey = event{"eventKey"}.getStr()
  let ringName = event{"ring"}.getStr()
  let op = event{"op"}.getStr("put")
  if eventKey.len == 0:
    raise newException(ValueError, "universe event key is empty")
  if ringName.len == 0:
    raise newException(ValueError, "universe event ring is empty")
  if op != "put":
    raise newException(ValueError, "only put universe events are supported")
  if sv.st.isUniverseSyncEventApplied(eventKey):
    return false
  let payload = event{"payload"}.getStr()
  let vec = jsonFloat32Seq(event{"vec"}).normalize()
  let ri = sv.ringInfo(ringName)
  let seq = sv.st.nextSeq(ri.key)
  let tWrite = event{"timestamp"}.getFloat(now)
  sv.st.upsert Particle(parent: ri.key, seq: seq, period: ri.period,
                        head: ri.head, tWrite: tWrite, payload: payload,
                        vec: vec, lastHere: now)
  if ri.key != HaloKey:
    sv.fs.observeRingPut(ri.key, vec)
  sv.st.markUniverseSyncEventApplied(eventKey)
  true

proc ownerOf(sv: Server, parent: uint64, seq: uint32, period, head, tWrite: float): int =
  let o = OrbitalId(parent: parent, epoch: 1, tWrite: tWrite, seq: seq)
    .ringOrbit(period, head)
  int(sv.tbl.node(o, epochTime()))

proc handoffTick(sv: Server) =
  let now = epochTime()
  let n = sv.peers.len
  if n <= 1:
    return
  var doomed: seq[(uint64, uint32)] = @[]
  var budget = MaxTransfersPerTick
  for k in sv.st.items.keys:
    if budget <= 0:
      break   # 残りは次の tick（サービス応答性を優先）
    # Table を書き換えるのは対象確定後（doomed）。sentAhead/lastHere の更新は直接。
    template p: untyped = sv.st.items[k]
    let o = orbitOf(p)
    let ownNow = int(sv.tbl.node(o, now))
    if ownNow == sv.myId:
      p.lastHere = now
      let nextNode = (sv.myId + 1) mod n
      let tCross = o.nextArrival(sv.tbl.arcStart(NodeId(nextNode)), now)
      if tCross - now < Lookahead:
        if not p.sentAhead:
          try:
            sv.peerLink.transferReq(nextNode, p.parent, p.seq, p.period, p.head,
                                    p.tWrite, p.payload, p.vec, timeoutMs = 500)
            p.sentAhead = true
            dec budget
          except CatchableError:
            discard   # 次の tick で再試行
      else:
        p.sentAhead = false   # 新しい周回に入った
    else:
      if not p.sentAhead:
        try:
          sv.peerLink.transferReq(ownNow, p.parent, p.seq, p.period, p.head,
                                  p.tWrite, p.payload, p.vec, timeoutMs = 500)
          p.sentAhead = true
          dec budget
        except CatchableError:
          discard   # 次の tick で再試行
      if p.sentAhead and now - p.lastHere > Grace:
        doomed.add k
  for k in doomed:
    sv.st.remove(k[0], k[1])

proc rebuildFieldState(sv: Server) =
  sv.fs.forwarders = sv.st.forwarders
  for _, p in sv.st.items:
    if p.parent != HaloKey and p.vec.len > 0:
      sv.fs.observeRingPut(p.parent, p.vec)

proc slowTick(sv: Server) =
  sv.fs.clusterTick(sv.st)
  discard sv.fs.captureTick(sv.st, epochTime())

proc handleRetrieve(sv: Server, sock: Socket, parts: seq[string]) =
  let hasRing = parts[1] == "1"
  let ringKey = parseBiggestUInt(parts[2]).uint64
  let budget = parseInt(parts[3])
  let vecDim = parseInt(parts[4])
  let q = sock.readExact(checkedVecBytes(vecDim)).bytesVec(vecDim).normalize()

  var hits: seq[LocalHit] = @[]
  var totalVectors = 0
  var scanned = 0
  var rings = initTable[uint64, bool]()
  if q.len > 0 and budget > 0:
    for _, p in sv.st.items:
      if p.vec.len == 0:
        continue
      inc totalVectors
      if not sv.ringKeyAllowed(sock, p.parent):
        continue
      if hasRing and p.parent != ringKey:
        continue
      inc scanned
      rings[p.parent] = true
      hits.add LocalHit(parent: p.parent, seq: p.seq, tWrite: p.tWrite,
                        score: 1.0 - cosineDistance(q, p.vec),
                        payload: p.payload)
    hits.sort(proc(a, b: LocalHit): int = cmp(b.score, a.score))
    if hits.len > budget:
      hits.setLen(budget)

  var payloadBytes = 0
  for h in hits:
    payloadBytes += h.payload.len
  sock.sendFrame("RHIT " & $scanned & " " & $rings.len & " " & $hits.len &
                 " " & $totalVectors & " " & $payloadBytes)
  for h in hits:
    sock.sendFrame("HIT " & $h.parent & " " & $h.seq & " " & $h.tWrite & " " &
                   $h.score & " " & $h.payload.len, h.payload)

proc applyClusterTxTick(sv: Server) =
  ## node0 が landing zone。commit intent は全 op の apply ACK まで残す。
  if sv.myId != 0:
    return
  var done: seq[uint64] = @[]
  for txid, intent in sv.st.clusterTx:
    if intent.applied or not intent.committed:
      continue
    var allApplied = true
    for op in intent.ops:
      let o = OrbitalId(parent: op.parent, epoch: 1, tWrite: op.tWrite, seq: op.seq)
        .ringOrbit(op.period, op.head)
      let node = int(sv.tbl.node(o, epochTime()))
      try:
        sv.peerLink.applyTxReq(node, txid,
          TxWireOp(delete: op.kind == ctxDelete,
                   parent: op.parent, seq: op.seq, period: op.period,
                   head: op.head, tWrite: op.tWrite,
                   payload: op.payload, vec: op.vec),
          timeoutMs = 500)
      except CatchableError:
        allApplied = false
    if allApplied:
      done.add txid
  for txid in done:
    sv.st.markClusterTxApplied(txid)

proc handleFrame(sv: Server, sock: Socket): bool =
  ## 1フレーム処理。false = 接続を閉じる。
  var parts: seq[string]
  try:
    parts = sock.readHeader()
  except IOError, OSError, TimeoutError:
    return false
  inc sv.requestCount
  let now = epochTime()
  let fd = sock.getFd.int
  if (sv.authUser.len > 0 or sv.users.len > 0) and
      not sv.authed.getOrDefault(fd, false):
    if sv.users.len > 0:
      if parts[0] == "AUTH" and parts.len >= 3 and parts[1] in sv.users and
          sv.users[parts[1]].password == parts[2]:
        sv.authed[fd] = true
        sv.authedUsers[fd] = parts[1]
        sock.sendFrame("OK auth")
        return true
    elif sv.authSecretKey.len > 0:
      if parts[0] == "AUTHCHAL" and parts.len >= 2 and parts[1] == sv.authUser:
        let challenge = newChallengeHex()
        sv.authChallenges[fd] = challenge
        sock.sendFrame("CHAL " & challenge)
        return true
      if parts[0] == "AUTHRESP" and parts.len >= 2 and fd in sv.authChallenges:
        let challenge = sv.authChallenges[fd]
        if verifySecretResponse(sv.authUser, sv.authPassword, challenge,
                                parts[1], sv.authSecretKey):
          sv.authChallenges.del fd
          sv.authed[fd] = true
          sv.authedUsers[fd] = sv.authUser
          sock.sendFrame("OK auth")
          sock.enableSecure(sv.authSecretKey, challenge)
          return true
    else:
      if parts[0] == "AUTH" and parts.len >= 3 and
          parts[1] == sv.authUser and parts[2] == sv.authPassword:
        sv.authed[fd] = true
        sv.authedUsers[fd] = sv.authUser
        sock.sendFrame("OK auth")
        return true
    inc sv.authFailures
    inc sv.errorResponses
    sock.sendFrame("ERR auth-required")
    return false
  case parts[0]
  of "AUTH":
    sock.sendFrame("OK auth")
  of "HELLO":
    if parts.len < 2:
      inc sv.errorResponses
      sock.sendFrame("ERR galaxy-required")
    elif parts[1] != sv.galaxy:
      inc sv.errorResponses
      sock.sendFrame("ERR wrong-galaxy expected=" & sv.galaxy)
    else:
      sock.sendFrame("OK galaxy=" & sv.galaxy)
  of "TXBEGIN":
    if not sv.requireRole(sock, roleWriter):
      return true
    doAssert sv.myId == 0, "TXBEGIN は node0 の landing zone で処理する"
    let txid = sv.st.reserveTxId()
    sock.sendFrame("OK " & $txid)
  of "TXRESERVE":
    if not sv.requireRole(sock, roleWriter):
      return true
    doAssert sv.myId == 0, "TXRESERVE は node0 の landing zone で処理する"
    let ringKey = parseBiggestUInt(parts[2]).uint64
    if not sv.requireRingKey(sock, ringKey):
      return true
    let period = parseFloat(parts[3])
    let head = parseFloat(parts[4])
    if ringKey notin sv.st.ringMeta:
      sv.st.putRingMeta(ringKey, period, head)
    let seq = sv.st.nextSeq(ringKey)
    sock.sendFrame("OK " & $seq & " " & $now)
  of "TXCOMMIT":
    if not sv.requireRole(sock, roleWriter):
      return false
    doAssert sv.myId == 0, "TXCOMMIT は node0 の landing zone で処理する"
    let txid = parseBiggestUInt(parts[1]).uint64
    let nOps = parseInt(parts[2])
    var ops: seq[ClusterTxOp] = @[]
    for _ in 0 ..< nOps:
      let h = sock.readHeader()
      let isDelete = h[0] == "D"
      let data = if h[0] == "P" or h[0] == "D": 1 else: 0
      var op = ClusterTxOp(kind: if isDelete: ctxDelete else: ctxPut,
                           parent: parseBiggestUInt(h[data]).uint64,
                           seq: parseUInt(h[data + 1]).uint32,
                           period: parseFloat(h[data + 2]),
                           head: parseFloat(h[data + 3]),
                           tWrite: parseFloat(h[data + 4]))
      let payloadLen = parseInt(h[data + 5])
      let vecDim = parseInt(h[data + 6])
      let bodyBytes = checkedFrameBytes(payloadLen, vecDim, extra = 1)
      if not sv.ringKeyAllowed(sock, op.parent):
        sock.drainBytes(bodyBytes)
        sock.drainTxCommitOps(nOps - ops.len - 1)
        sock.denyRingKey(op.parent)
        return true
      op.payload = sock.readExact(payloadLen)
      op.vec = sock.readExact(checkedVecBytes(vecDim)).bytesVec(vecDim).normalize()
      discard sock.readExact(1) # op 区切りの '\n'
      ops.add op
    sv.st.putClusterTxIntent ClusterTxIntent(id: txid, ops: ops, committed: true)
    sock.sendFrame("OK")
  of "TXSTATUS":
    if not sv.requireRole(sock, roleWriter):
      return true
    doAssert sv.myId == 0, "TXSTATUS は node0 の landing zone で処理する"
    let txid = parseBiggestUInt(parts[1]).uint64
    if sv.st.isClusterTxApplied(txid):
      sock.sendFrame("OK APPLIED")
    elif sv.st.hasClusterTxIntent(txid):
      sock.sendFrame("OK PENDING")
    else:
      sock.sendFrame("OK UNKNOWN")
  of "UAPPLY":
    if not sv.requireRole(sock, roleWriter):
      return false
    try:
      let bodyLen = parseInt(parts[1])
      discard checkedWireLen(bodyLen, "bodyLen")
      let body = sock.readExact(bodyLen)
      let event = parseJson(body)
      let ringName = event{"ring"}.getStr()
      if not sv.ringNameAllowed(sock, ringName):
        sock.denyRingName(ringName)
        return true
      let ri = sv.ringInfo(ringName)
      let owner = int(sv.tbl.owner(ri.head))
      if owner != sv.myId:
        let status = sv.peerLink.universeApplyReq(owner, body)
        inc sv.universeApplyForwarded
        sv.universeApplyLastOk = now
        sock.sendFrame("UOK " & status)
        return true
      let applied = sv.applyUniverseEvent(event, now)
      if applied:
        inc sv.universeApplyApplied
      else:
        inc sv.universeApplySkipped
      sv.universeApplyLastOk = now
      sock.sendFrame("UOK " & (if applied: "APPLIED" else: "SKIPPED"))
    except CatchableError:
      inc sv.universeApplyErrors
      sv.universeApplyLastError = now
      raise
  of "USTATUS":
    if not sv.requireRole(sock, roleAdmin):
      return true
    sock.sendFrame("USTATUS " & $sv.st.universeSyncEvents.len & " " &
                   $sv.st.appliedUniverseSyncEvents.len & " " &
                   $sv.universeApplyApplied & " " &
                   $sv.universeApplySkipped & " " &
                   $sv.universeApplyErrors & " " &
                   $sv.universeApplyForwarded & " " &
                   $(int(sv.universeApplyLastOk)) & " " &
                   $(int(sv.universeApplyLastError)))
  of "WIREVER":
    sock.sendFrame("WIREVER " & $WireProtocolVersion)
  of "APPLYTX":
    if not sv.requireRole(sock, roleWriter):
      return false
    let txid = parseBiggestUInt(parts[1]).uint64
    let isDelete = parts[2] == "D"
    let data = if parts[2] == "P" or parts[2] == "D": 3 else: 2
    let parent = parseBiggestUInt(parts[data]).uint64
    let seq = parseUInt(parts[data + 1]).uint32
    let payloadLen = parseInt(parts[data + 5])
    let vecDim = parseInt(parts[data + 6])
    let bodyBytes = checkedFrameBytes(payloadLen, vecDim)
    if not sv.ringKeyAllowed(sock, parent):
      sock.drainBytes(bodyBytes)
      sock.denyRingKey(parent)
      return true
    if sv.st.appliedClusterTx.getOrDefault(txid, false):
      sock.drainBytes(bodyBytes)
      sock.sendFrame("OK")
      return true
    var p = Particle(parent: parent, seq: seq,
                     period: parseFloat(parts[data + 2]),
                     head: parseFloat(parts[data + 3]),
                     tWrite: parseFloat(parts[data + 4]),
                     lastHere: now)
    p.payload = sock.readExact(payloadLen)
    p.vec = sock.readExact(checkedVecBytes(vecDim)).bytesVec(vecDim).normalize()
    if isDelete:
      if sv.st.contains(parent, seq):
        sv.st.remove(parent, seq)
      sock.sendFrame("OK")
      return true
    if p.parent notin sv.st.ringMeta:
      sv.st.putRingMeta(p.parent, p.period, p.head)
    if p.seq >= sv.st.seqs.getOrDefault(p.parent, 0'u32):
      sv.st.seqs[p.parent] = p.seq + 1
    if sv.st.contains(p.parent, p.seq) and p.vec.len == 0:
      p.vec = sv.st.items[(p.parent, p.seq)].vec
    sv.st.upsert p
    if p.parent != HaloKey:
      sv.fs.observeRingPut(p.parent, p.vec)
    sock.sendFrame("OK")
  of "TXGETID", "TXQRYID":
    doAssert sv.myId == 0, "TXGETID/TXQRYID は node0 の landing zone で処理する"
    let parent = parseBiggestUInt(parts[1]).uint64
    let seq = parseUInt(parts[3]).uint32
    var selection = ""
    if parts[0] == "TXQRYID":
      let selectionLen = parseInt(parts[7])
      discard checkedWireLen(selectionLen, "selectionLen")
      if not sv.ringKeyAllowed(sock, parent):
        sock.drainBytes(selectionLen)
        sock.denyRingKey(parent)
        return true
      selection = sock.readExact(selectionLen)
    elif not sv.requireRingKey(sock, parent):
      return true
    var found = false
    var bestTxid = 0'u64
    var best: ClusterTxOp
    for txid, intent in sv.st.clusterTx:
      if intent.committed and not intent.applied:
        for op in intent.ops:
          if op.parent == parent and op.seq == seq and (not found or txid > bestTxid):
            found = true
            bestTxid = txid
            best = op
    if found:
      if best.kind == ctxDelete:
        sock.sendFrame("GONE")
        return true
      var value = best.payload
      if parts[0] == "TXQRYID":
        try:
          value = $applySelection(parseSelection(selection), parseJson(value))
        except ValueError, JsonParsingError:
          sock.sendFrame("ERR " & getCurrentExceptionMsg().replace("\n", " "))
          return true
      sock.sendFrame("VAL 0 " & $value.len, value)
      return true
    sock.sendFrame("MISS")
  of "RETRIEVE":
    if parts[1] == "1":
      let ringKey = parseBiggestUInt(parts[2]).uint64
      if not sv.ringKeyAllowed(sock, ringKey):
        sock.drainBytes(checkedVecBytes(parseInt(parts[4])))
        sock.denyRingKey(ringKey)
        return true
    sv.handleRetrieve(sock, parts)
  of "RINGS":
    var allowedCount = 0
    for ring, rc in sv.fs.ringCentroid:
      if sv.ringKeyAllowed(sock, ring):
        inc allowedCount
    sock.sendFrame("RINGS " & $allowedCount)
    for ring, rc in sv.fs.ringCentroid:
      if not sv.ringKeyAllowed(sock, ring):
        continue
      sock.sendFrame("RING " & $ring & " " & $rc.n & " " & $rc.c.len,
                     rc.c.vecBytes)
  of "PUTR":
    if not sv.requireRole(sock, roleWriter):
      return false
    let ringLen = parseInt(parts[1])
    let payloadLen = parseInt(parts[2])
    let vecDim = if parts.len >= 4: parseInt(parts[3]) else: 0
    discard checkedWireLen(ringLen, "ringLen")
    let bodyBytes = checkedFrameBytes(payloadLen, vecDim)
    let ringName = sock.readExact(ringLen)
    if not sv.ringNameAllowed(sock, ringName):
      sock.drainBytes(bodyBytes)
      sock.denyRingName(ringName)
      return true
    let payload = sock.readExact(payloadLen)
    let vec = sock.readExact(checkedVecBytes(vecDim)).bytesVec(vecDim).normalize()
    let ri = sv.ringInfo(ringName)
    let owner = int(sv.tbl.owner(ri.head))
    if owner != sv.myId:
      let id = sv.peerLink.putRingReq(owner, ringName, payload, vec)
      sock.sendFrame("ID " & $id.parent & " " & $id.epoch & " " & $id.seq & " " &
                     $id.tWrite & " " & $id.period & " " & $id.head)
    else:
      let seq = sv.st.nextSeq(ri.key)
      sv.st.upsert Particle(parent: ri.key, seq: seq, period: ri.period,
                            head: ri.head, tWrite: now, payload: payload,
                            vec: vec, lastHere: now)
      if ri.key != HaloKey:
        sv.fs.observeRingPut(ri.key, vec)
      sock.sendFrame("ID " & $ri.key & " 1 " & $seq & " " & $now & " " &
                     $ri.period & " " & $ri.head)
  of "PUT":
    if not sv.requireRole(sock, roleWriter):
      return false
    let ringKey = parseBiggestUInt(parts[1]).uint64
    let period = parseFloat(parts[2])
    let head = parseFloat(parts[3])
    let payloadLen = parseInt(parts[4])
    let vecDim = if parts.len >= 6: parseInt(parts[5]) else: 0
    let bodyBytes = checkedFrameBytes(payloadLen, vecDim)
    if not sv.ringKeyAllowed(sock, ringKey):
      sock.drainBytes(bodyBytes)
      sock.denyRingKey(ringKey)
      return true
    let payload = sock.readExact(payloadLen)
    let vec = sock.readExact(checkedVecBytes(vecDim)).bytesVec(vecDim).normalize()
    let seq = sv.st.nextSeq(ringKey)
    if ringKey notin sv.st.ringMeta:
      sv.st.putRingMeta(ringKey, period, head)
    sv.st.upsert Particle(parent: ringKey, seq: seq, period: period, head: head,
                          tWrite: now, payload: payload, vec: vec, lastHere: now)
    if ringKey != HaloKey:
      sv.fs.observeRingPut(ringKey, vec)
    sock.sendFrame("OK " & $seq & " " & $now)
  of "COUNTR":
    let ringKey = parseBiggestUInt(parts[1]).uint64
    if not sv.requireRingKey(sock, ringKey):
      return true
    var n = 0
    for k in sv.st.itemsByRing.getOrDefault(ringKey, @[]):
      if k in sv.st.items:
        inc n
    sock.sendFrame("COUNT " & $n)
  of "LISTR":
    let ringKey = parseBiggestUInt(parts[1]).uint64
    let limit = parseInt(parts[2])
    let cursorLen = parseInt(parts[3])
    discard checkedWireLen(cursorLen, "cursorLen")
    if not sv.ringKeyAllowed(sock, ringKey):
      sock.drainBytes(cursorLen)
      sock.denyRingKey(ringKey)
      return true
    let cursor = sock.readExact(cursorLen)
    let afterSeq = if cursor.len == 0: -1'i64 else: int64(parseBiggestInt(cursor))
    var rows: seq[Particle] = @[]
    var nextCursor = "_"
    if limit > 0:
      for k in sv.st.itemsByRing.getOrDefault(ringKey, @[]):
        if k[1].int64 <= afterSeq or k notin sv.st.items:
          continue
        if rows.len >= limit:
          nextCursor = $(rows[^1].seq)
          break
        rows.add sv.st.items[k]
    sock.sendFrame("LVAL " & $rows.len & " " & nextCursor)
    for p in rows:
      sock.sendFrame("ITEM " & $p.seq & " " & $p.tWrite & " " & $p.parent & " " &
                     $p.payload.len, p.payload)
  of "GETID", "QRYID":
    let parent = parseBiggestUInt(parts[1]).uint64
    let epoch = parseUInt(parts[2]).uint32
    let seq = parseUInt(parts[3]).uint32
    let tWrite = parseFloat(parts[4])
    let period = parseFloat(parts[5])
    let head = parseFloat(parts[6])
    var selection = ""
    if parts[0] == "QRYID":
      let selectionLen = parseInt(parts[7])
      discard checkedWireLen(selectionLen, "selectionLen")
      if not sv.ringKeyAllowed(sock, parent):
        sock.drainBytes(selectionLen)
        sock.denyRingKey(parent)
        return true
      selection = sock.readExact(selectionLen)
    elif not sv.requireRingKey(sock, parent):
      return true
    let owner = sv.ownerOf(parent, seq, period, head, tWrite)
    if owner != sv.myId:
      let r =
        if parts[0] == "QRYID":
          sv.peerLink.queryReq(owner, parent, seq, period, head, tWrite, selection)
        else:
          sv.peerLink.getReq(owner, parent, seq, period, head, tWrite)
      if r.forwarded:
        sock.sendFrame("FWD " & $r.newParent & " " & $epoch & " " & $r.newSeq & " " &
                       $r.newTWrite & " " & $period & " " & $head)
      elif r.found:
        sock.sendFrame("VAL " & $r.node & " " & $r.value.len, r.value)
      else:
        sock.sendFrame("MISS")
      return true
    if not sv.st.contains(parent, seq):
      let k = (parent, seq)
      if k in sv.st.forwarders and sv.st.forwarders[k].expiresAt >= now:
        let f = sv.st.forwarders[k]
        sock.sendFrame("FWD " & $f.newParent & " " & $epoch & " " & $f.newSeq & " " &
                       $f.newTWrite & " " & $period & " " & $head)
      else:
        sock.sendFrame("MISS")
    else:
      var value = sv.st.items[(parent, seq)].payload
      if parts[0] == "QRYID":
        try:
          value = $applySelection(parseSelection(selection), parseJson(value))
        except ValueError, JsonParsingError:
          sock.sendFrame("ERR " & getCurrentExceptionMsg().replace("\n", " "))
          return true
      sock.sendFrame("VAL " & $sv.myId & " " & $value.len, value)
  of "GET", "QRY":
    let parent = parseBiggestUInt(parts[1]).uint64
    let seq = parseUInt(parts[2]).uint32
    var selection = ""
    if parts[0] == "QRY":
      let selectionLen = parseInt(parts[6])
      discard checkedWireLen(selectionLen, "selectionLen")
      if not sv.ringKeyAllowed(sock, parent):
        sock.drainBytes(selectionLen)
        sock.denyRingKey(parent)
        return true
      selection = sock.readExact(selectionLen)
    elif not sv.requireRingKey(sock, parent):
      return true
    if not sv.st.contains(parent, seq):
      let k = (parent, seq)
      if k in sv.st.forwarders and sv.st.forwarders[k].expiresAt >= now:
        let f = sv.st.forwarders[k]
        sock.sendFrame("FWD " & $f.newParent & " " & $f.newSeq & " " &
                       $f.newTWrite)
      else:
        sock.sendFrame("MISS")
    else:
      var value = sv.st.items[(parent, seq)].payload
      if parts[0] == "QRY":
        try:
          value = $applySelection(parseSelection(selection), parseJson(value))
        except ValueError, JsonParsingError:
          sock.sendFrame("ERR " & getCurrentExceptionMsg().replace("\n", " "))
          return true
      sock.sendFrame("VAL " & $sv.myId & " " & $value.len, value)
  of "BGET":
    let n = parseInt(parts[1])
    let bodyLen = parseInt(parts[2])
    discard checkedWireLen(bodyLen, "bodyLen")
    let body = sock.readExact(bodyLen)
    var payload = ""
    var pos = 0
    for _ in 0 ..< n:
      let nl = body.find('\n', pos)
      if nl < 0:
        break
      let h = body[pos ..< nl].split(' ')
      pos = nl + 1
      if h.len < 5:
        payload.add "0\n"
        continue
      let parent = parseBiggestUInt(h[0]).uint64
      if not sv.ringKeyAllowed(sock, parent):
        payload.add "0\n"
        continue
      let seq = parseUInt(h[1]).uint32
      let k = (parent, seq)
      if k in sv.st.items:
        let value = sv.st.items[k].payload
        payload.add $value.len & "\n"
        payload.add value
      else:
        payload.add "0\n"
    sock.sendFrame("BVAL " & $n & " " & $payload.len, payload)
  of "TRF":
    if not sv.requireRole(sock, roleWriter):
      return false
    var p = Particle(parent: parseBiggestUInt(parts[1]).uint64,
                     seq: parseUInt(parts[2]).uint32,
                     period: parseFloat(parts[3]),
                     head: parseFloat(parts[4]),
                     tWrite: parseFloat(parts[5]),
                     lastHere: now)
    let payloadLen = parseInt(parts[6])
    let vecDim = if parts.len >= 8: parseInt(parts[7]) else: 0
    let bodyBytes = checkedFrameBytes(payloadLen, vecDim)
    if not sv.ringKeyAllowed(sock, p.parent):
      sock.drainBytes(bodyBytes)
      sock.denyRingKey(p.parent)
      return true
    p.payload = sock.readExact(payloadLen)
    p.vec = sock.readExact(checkedVecBytes(vecDim)).bytesVec(vecDim).normalize()
    if p.parent notin sv.st.ringMeta:
      sv.st.putRingMeta(p.parent, p.period, p.head)
    # 追い越し対策: 相手起点の seq 採番と衝突しないよう max を取る
    if p.seq >= sv.st.seqs.getOrDefault(p.parent, 0'u32):
      sv.st.seqs[p.parent] = p.seq + 1
    sv.st.upsert p
    if p.parent != HaloKey:
      sv.fs.observeRingPut(p.parent, p.vec)
    sock.sendFrame("OK")
  of "STATS":
    sock.sendFrame("OK " & $sv.myId & " " & $sv.st.count)
  of "HEALTH":
    sock.sendFrame("OK node=" & $sv.myId & " items=" & $sv.st.count &
                   " pendingTx=" & $sv.st.clusterTxPending)
  of "METRICS":
    if not sv.requireRole(sock, roleAdmin):
      return true
    sock.sendFrame("OK " &
                   "node " & $sv.myId & " " &
                   "uptimeSec " & $(int(epochTime() - sv.startedAt)) & " " &
                   "requests " & $sv.requestCount & " " &
                   "errors " & $sv.errorResponses & " " &
                   "authFailures " & $sv.authFailures & " " &
                   "authzDenied " & $sv.authzDenied & " " &
                   "connectionsAccepted " & $sv.connectionsAccepted & " " &
                   "activeConnections " & $sv.activeConnections & " " &
                   "items " & $sv.st.count & " " &
                   "rings " & $sv.st.ringMeta.len & " " &
                   "forwarders " & $sv.st.forwarders.len & " " &
                   "walBytes " & $sv.st.logSize & " " &
                   "warpJobs " & $sv.st.warpJobs.len & " " &
                   "universeSyncEvents " & $sv.st.universeSyncEvents.len & " " &
                   "universeSyncApplied " &
                     $sv.st.appliedUniverseSyncEvents.len & " " &
                   "universeApplyApplied " & $sv.universeApplyApplied & " " &
                   "universeApplySkipped " & $sv.universeApplySkipped & " " &
                   "universeApplyErrors " & $sv.universeApplyErrors & " " &
                   "universeApplyForwarded " & $sv.universeApplyForwarded & " " &
                   "universeApplyLastOk " &
                     $(int(sv.universeApplyLastOk)) & " " &
                   "universeApplyLastError " &
                     $(int(sv.universeApplyLastError)) & " " &
                   "persistent " & $(if sv.st.isPersistent: 1 else: 0) & " " &
                   "durabilityStrong " &
                     $(if sv.st.durability == durStrong: 1 else: 0) & " " &
                   "clusterTxCommitted " & $sv.st.clusterTxCommitted & " " &
                   "clusterTxApplied " & $sv.st.clusterTxApplied & " " &
                   "clusterTxPending " & $sv.st.clusterTxPending & " " &
                   "clumps " & $sv.fs.clumps.len)
  of "SHUTDOWN":
    if not sv.requireRole(sock, roleAdmin):
      return true
    sv.st.sync()
    sock.sendFrame("OK shutting-down")
    sv.running = false
  else:
    inc sv.errorResponses
    sock.sendFrame("ERR unknown")
  true

proc printUsage() =
  echo "RocheDB node server"
  echo ""
  echo "Usage:"
  echo "  roched --id=N --peers=host:port[,host:port...] [options]"
  echo ""
  echo "Options:"
  echo "  --data=DIR                    Enable WAL-backed persistence"
  echo "  --slow-tick=SECONDS           Background maintenance interval"
  echo "  --durability=buffered|strong  Buffered WAL or fsync-on-write durability"
  echo "  --user=NAME                   Username for cluster auth"
  echo "  --password=TEXT               Password for cluster auth"
  echo "  --auth-token=TEXT             Token-style auth shortcut"
  echo "  --secret-key=TEXT             Additional secret-key gate"
  echo "  --galaxy=NAME                 Expected galaxy name"
  echo "  --allow-ring=PREFIX[,PREFIX]  Ring-prefix authorization"
  echo "  --role=user:password:role[:prefixes]"
  echo "                                Role entry: reader, writer, or admin"
  echo "  -h, --help                    Show this help"
  echo ""
  echo "Example:"
  echo "  roched --id=0 --peers=127.0.0.1:7301 --data=/var/lib/roche"

proc main() =
  for arg in commandLineParams():
    if arg == "--help" or arg == "-h":
      printUsage()
      return

  var id = -1
  var peersStr = ""
  var dataDir = ""
  var slowTickSec = DefaultSlowTickSec
  var authUser = ""
  var authPassword = ""
  var authSecretKey = ""
  var users = initTable[string, UserRule]()
  var galaxy = ""
  var allowedRingPrefixes: seq[string] = @[]
  var durability = durBuffered
  for kind, key, val in getopt():
    if kind == cmdLongOption:
      case key
      of "id": id = parseInt(val)
      of "peers": peersStr = val
      of "data": dataDir = val
      of "slow-tick": slowTickSec = parseFloat(val)
      of "user": authUser = val
      of "password": authPassword = val
      of "secret-key": authSecretKey = val
      of "galaxy": galaxy = val
      of "role":
        let parsed = parseUserRule(val)
        users[parsed.user] = parsed.rule
        if authUser.len == 0:
          authUser = parsed.user
          authPassword = parsed.rule.password
      of "allow-ring":
        for part in val.split(','):
          let prefix = part.strip()
          if prefix.len > 0:
            allowedRingPrefixes.add prefix
      of "durability":
        case val
        of "buffered": durability = durBuffered
        of "strong": durability = durStrong
        else:
          raise newException(ValueError,
            "--durability must be 'buffered' or 'strong'")
      of "auth-token":
        authUser = "token"
        authPassword = val
  let peers = parsePeers(peersStr)
  doAssert id >= 0 and id < peers.len, "--id と --peers を指定（id は peers 内の自分の位置）"

  let sv = Server(myId: id, peers: peers,
                  tbl: ArcTable(epoch: 1, nNodes: uint16(peers.len)),
                  st: openStore(dataDir, durability = durability),
                  fs: newFieldState(),
                  peerLink: newClusterClient(peers, username = authUser,
                                             password = authPassword,
                                             secretKey = authSecretKey),
                  slowTickSec: slowTickSec,
                  running: true,
                  authUser: authUser,
                  authPassword: authPassword,
                  authSecretKey: authSecretKey,
                  users: users,
                  galaxy: galaxy,
                  allowedRingPrefixes: allowedRingPrefixes,
                  startedAt: epochTime())
  sv.st.setGalaxy(galaxy)
  sv.rebuildFieldState()

  let listener = newSocket()
  listener.setSockOpt(OptReuseAddr, true)
  listener.bindAddr(Port(peers[id].port), peers[id].host)
  listener.listen()
  echo "roched node", id, " listening on ", peers[id].host, ":", peers[id].port,
       (if dataDir.len > 0: " data=" & dataDir else: " (memory)"),
       " arcs=1/", peers.len, " restored=", sv.st.count,
       " slowTick=", sv.slowTickSec, "s",
       " durability=", (if durability == durStrong: "strong" else: "buffered"),
       (if galaxy.len > 0: " galaxy=" & galaxy else: " galaxy=<none>"),
       (if users.len > 0: " authz=role-ring-prefix"
        elif allowedRingPrefixes.len > 0: " authz=ring-prefix"
        else: " authz=off"),
       (if authUser.len > 0:
          " auth=on user=" & authUser &
          (if authSecretKey.len > 0: " secret=on" else: " secret=off")
        else: " auth=off")

  var sel = newSelector[int]()
  sel.registerHandle(listener.getFd, {Event.Read}, -1)
  var conns = initTable[int, Socket]()

  var lastTick = getMonoTime()
  var lastSlowTick = getMonoTime()
  while sv.running:
    for ev in sel.select(TickMs):
      if ev.errorCode.int != 0:
        continue
      let fd = ev.fd
      if sel.getData(fd) == -1:
        var client: Socket
        listener.accept(client)
        client.setSockOpt(OptNoDelay, true, level = IPPROTO_TCP.cint)
        conns[client.getFd.int] = client
        inc sv.connectionsAccepted
        sv.activeConnections = conns.len
        if sv.authUser.len == 0:
          sv.authed[client.getFd.int] = true
        sel.registerHandle(client.getFd, {Event.Read}, 0)
      else:
        let sock = conns[fd]
        var keep = false
        try:
          keep = sv.handleFrame(sock)
        except Exception:
          inc sv.errorResponses
          try:
            sock.sendFrame("ERR " & getCurrentExceptionMsg().replace("\n", " "))
          except Exception:
            discard
          keep = false
        if not keep:
          sel.unregister(fd)
          conns.del fd
          sv.activeConnections = conns.len
          sv.authed.del fd
          sv.authChallenges.del fd
          sock.disableSecure()
          sock.close()
    # ハンドオフは TickMs ごと（select はリクエスト毎に返るので時刻で間引く。
    # ここを間引かないと全粒子スキャンが毎リクエストに乗り、レイテンシを壊す）
    let nowM = getMonoTime()
    if (nowM - lastTick).inMilliseconds >= TickMs:
      sv.handoffTick()
      sv.st.sync()
      lastTick = nowM
    if float((nowM - lastSlowTick).inMilliseconds) / 1000.0 >= sv.slowTickSec:
      sv.slowTick()
      sv.applyClusterTxTick()
      sv.st.sync()
      lastSlowTick = nowM
  sv.st.sync()
  sv.st.close()
  sv.peerLink.close()

when isMainModule:
  main()
