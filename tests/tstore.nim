## kouten/store の永続化テスト

import std/[algorithm, os, osproc, strutils, tables, tempfiles, unittest]
import ../src/kouten/store

if paramCount() == 2 and paramStr(1) == "--lock-child":
  let dir = paramStr(2)
  var st = openStore(dir)
  writeFile(dir / "locked.ready", "1")
  sleep(5_000)
  st.close()
  quit 0

proc ringSignature(st: Store, ring: uint64): seq[string] =
  if ring notin st.itemsByRing:
    return @[]
  for k in st.itemsByRing[ring]:
    if k in st.items:
      let p = st.items[k]
      result.add p.payload & "|" & $p.codec & "|" & $p.seq & "|" & $p.tWrite
  result.sort()

suite "store persistence":
  test "persistent data dirs are locked across processes":
    let dir = createTempDir("kouten-store", "lock")
    let child = startProcess(getAppFilename(), args = ["--lock-child", dir])
    try:
      for _ in 0 ..< 50:
        if fileExists(dir / "locked.ready"):
          break
        sleep(100)
      check fileExists(dir / "locked.ready")
      expect IOError:
        discard openStore(dir)
    finally:
      try:
        child.terminate()
        discard child.waitForExit(timeout = 2_000)
      except CatchableError:
        discard
      child.close()
      removeDir(dir)

  test "Particle vec は E レコードで復元される":
    let dir = createTempDir("kouten-store", "vec")
    var st = openStore(dir)
    st.upsert Particle(parent: 11'u64, seq: 3'u32, period: 60.0, head: 1.2,
                       tWrite: 4.5, payload: "payload",
                       vec: @[0.25'f32, -0.5'f32, 1.0'f32])
    st.close()

    var st2 = openStore(dir)
    check st2.items[(11'u64, 3'u32)].payload == "payload"
    check st2.items[(11'u64, 3'u32)].vec == @[0.25'f32, -0.5'f32, 1.0'f32]
    st2.close()
    removeDir(dir)

  test "payload codec survives WAL replay while legacy records default to raw":
    let dir = createTempDir("kouten-store", "payload-codec")
    var st = openStore(dir)
    st.upsert Particle(parent: 12'u64, seq: 0'u32, period: 60.0, head: 0.0,
                       tWrite: 1.0, payload: "(object (name KoutenDB))",
                       codec: pcNif)
    st.close()

    var restored = openStore(dir)
    check restored.items[(12'u64, 0'u32)].codec == pcNif
    restored.close()
    removeDir(dir)

    let legacyDir = createTempDir("kouten-store", "legacy-payload-codec")
    writeFile(legacyDir / "kouten.log",
              "P 13 0 60.0 0.0 1.0 5 0\nhello\n")
    var legacy = openStore(legacyDir)
    check legacy.items[(13'u64, 0'u32)].codec == pcRaw
    legacy.close()
    removeDir(legacyDir)

  test "stellar map blobs are validated before write and replay":
    let dir = createTempDir("kouten-store", "stellar-map-validate")
    var st = openStore(dir)
    st.putStellarMap("commerce/order/A-001",
                     """{"stellar":"commerce/order/A-001","members":["users/123","shops/1123"]}""")
    expect ValueError:
      st.putStellarMap("commerce/order/A-001", """{"members":["users/123"]}""")
    expect ValueError:
      st.putStellarMap("commerce/order/A-001",
                       """{"stellar":"other","members":["users/123"]}""")
    expect ValueError:
      st.putStellarMap("commerce/order/A-001",
                       """{"stellar":"commerce/order/A-001","members":[123]}""")
    st.close()

    var restored = openStore(dir)
    check restored.stellarMaps["commerce/order/A-001"].contains("users/123")
    restored.close()
    removeDir(dir)

    let legacyDir = createTempDir("kouten-store", "stellar-map-bad-replay")
    let malformed = """{"stellar":"commerce/order/A-001","members":[123]}"""
    writeFile(legacyDir / "kouten.log", "SM " & $malformed.len & "\n" & malformed & "\n")
    expect IOError:
      discard openStore(legacyDir)
    removeDir(legacyDir)

  test "time orbit profile survives WAL replay and compact":
    let dir = createTempDir("kouten-store", "time-orbit")
    var st = openStore(dir)
    let profile = TimeOrbitProfile(bits: 60, bucketMs: 1000'i64,
                                   phase: 1234'u64, salt: "logs-api")
    st.putTimeOrbitProfile(77'u64, profile)
    st.close()

    var restored = openStore(dir)
    check restored.ringTimeOrbitProfiles[77'u64] == profile
    discard restored.compact()
    restored.close()

    var compacted = openStore(dir)
    check compacted.ringTimeOrbitProfiles[77'u64] == profile
    compacted.close()
    removeDir(dir)

  when declared(poisonWritesForTest):
    test "poisoned write path rejects later persistent mutations":
      let dir = createTempDir("kouten-store", "poison")
      var st = openStore(dir, durability = durStrong)
      st.upsert Particle(parent: 20'u64, seq: 0'u32, period: 60.0,
                         head: 0.0, tWrite: 1.0, payload: "before")
      st.poisonWritesForTest("simulated fsync failure")
      check st.writeFailed
      expect IOError:
        st.upsert Particle(parent: 20'u64, seq: 1'u32, period: 60.0,
                           head: 0.0, tWrite: 2.0, payload: "after")
      st.close()
      removeDir(dir)

  test "new WAL records have magic header and checksums":
    let dir = createTempDir("kouten-store", "wal-v2")
    var st = openStore(dir)
    st.upsert Particle(parent: 14'u64, seq: 0'u32, period: 60.0, head: 0.0,
                       tWrite: 1.0, payload: "checksummed",
                       codec: pcJson)
    st.close()

    let raw = readFile(dir / "kouten.log")
    check raw.startsWith("!KOUTENDB-WAL 2\n@ ")
    check raw.contains("\nP 14 0 ")

    var restored = openStore(dir)
    check restored.items[(14'u64, 0'u32)].payload == "checksummed"
    check restored.items[(14'u64, 0'u32)].codec == pcJson
    restored.close()
    removeDir(dir)

  test "versioned WAL checksum mismatch refuses open without repair":
    let dir = createTempDir("kouten-store", "wal-v2-corrupt")
    var st = openStore(dir)
    st.upsert Particle(parent: 15'u64, seq: 0'u32, period: 60.0, head: 0.0,
                       tWrite: 1.0, payload: "checksum")
    st.close()

    let path = dir / "kouten.log"
    let raw = readFile(path)
    writeFile(path, raw.replace("checksum", "checksux"))

    expect IOError:
      discard openStore(dir)
    check readFile(path).contains("checksux")
    removeDir(dir)

  test "versioned WAL torn tail repairs to last checked record":
    let dir = createTempDir("kouten-store", "wal-v2-tail")
    var st = openStore(dir)
    st.upsert Particle(parent: 16'u64, seq: 0'u32, period: 60.0, head: 0.0,
                       tWrite: 1.0, payload: "stable")
    st.close()

    let path = dir / "kouten.log"
    let good = readFile(path)
    writeFile(path, good & "@ 80 0\nP 16 1 60.0 0.0 2.0 7 0 raw\npartial")

    var restored = openStore(dir)
    check restored.count() == 1
    check restored.items[(16'u64, 0'u32)].payload == "stable"
    check not restored.contains(16'u64, 1'u32)
    restored.close()
    check readFile(path) == good
    removeDir(dir)

  test "Forwarder は F レコードで復元される":
    let dir = createTempDir("kouten-store", "fwd")
    var st = openStore(dir)
    st.putForwarder(0'u64, 7'u32,
                    Forwarder(newParent: 99'u64, newSeq: 2'u32,
                              newTWrite: 12.5, expiresAt: 123.0))
    st.close()

    var st2 = openStore(dir)
    let f = st2.forwarders[(0'u64, 7'u32)]
    check f.newParent == 99'u64
    check f.newSeq == 2'u32
    check f.newTWrite == 12.5
    check f.expiresAt == 123.0
    st2.close()
    removeDir(dir)

  test "Warp job snapshot は WJ レコードで復元される":
    let dir = createTempDir("kouten-store", "warp")
    var st = openStore(dir)
    st.putWarpJob(42'u64, """{"id":42,"status":"wsPending"}""")
    st.close()

    var st2 = openStore(dir)
    check st2.warpJobs[42'u64].contains("\"status\":\"wsPending\"")
    discard st2.compact()
    st2.close()

    var st3 = openStore(dir)
    check st3.warpJobs[42'u64].contains("\"id\":42")
    st3.deleteWarpJob(42'u64)
    check 42'u64 notin st3.warpJobs
    st3.close()

    var st4 = openStore(dir)
    check 42'u64 notin st4.warpJobs
    discard st4.compact()
    st4.close()

    var st5 = openStore(dir)
    check 42'u64 notin st5.warpJobs
    st5.close()
    removeDir(dir)

  test "Universe sync event は UJ/UA/UD レコードで復元される":
    let dir = createTempDir("kouten-store", "universe-sync")
    var st = openStore(dir)
    st.putUniverseSyncEvent(7'u64, """{"id":7,"eventKey":"tokyo|social|posts|p1","ring":"posts"}""")
    st.markUniverseSyncEventApplied("tokyo|social|posts|p1")
    st.close()

    var st2 = openStore(dir)
    check st2.universeSyncEvents[7'u64].contains("\"ring\":\"posts\"")
    check st2.isUniverseSyncEventApplied("tokyo|social|posts|p1")
    discard st2.compact()
    st2.close()

    var st3 = openStore(dir)
    check 7'u64 in st3.universeSyncEvents
    check st3.isUniverseSyncEventApplied("tokyo|social|posts|p1")
    st3.deleteUniverseSyncEvent(7'u64)
    st3.close()

    var st4 = openStore(dir)
    check 7'u64 notin st4.universeSyncEvents
    check st4.isUniverseSyncEventApplied("tokyo|social|posts|p1")
    st4.close()
    removeDir(dir)

  test "Universe sync sequence は prune 後も UQ レコードで巻き戻らない":
    let dir = createTempDir("kouten-store", "universe-seq")
    var st = openStore(dir)
    st.putUniverseSyncEvent(1'u64, """{"id":1,"eventKey":"e1","ring":"r"}""")
    st.setNextUniverseSyncId(9'u64)
    st.deleteUniverseSyncEvent(1'u64)
    st.close()

    var st2 = openStore(dir)
    check st2.universeSyncEvents.len == 0
    check st2.nextUniverseSyncId == 9'u64
    discard st2.compact()
    st2.close()

    var st3 = openStore(dir)
    check st3.universeSyncEvents.len == 0
    check st3.nextUniverseSyncId == 9'u64
    st3.close()
    removeDir(dir)

  test "Universe sync applied dedup set can be pruned with WAL replay":
    let dir = createTempDir("kouten-store", "universe-applied-prune")
    var st = openStore(dir)
    st.markUniverseSyncEventApplied("event-1")
    st.markUniverseSyncEventApplied("event-2")
    st.markUniverseSyncEventApplied("event-3")
    check st.pruneAppliedUniverseSyncEvents(2) == 1
    check not st.isUniverseSyncEventApplied("event-1")
    check st.isUniverseSyncEventApplied("event-2")
    check st.isUniverseSyncEventApplied("event-3")
    st.close()

    var reopened = openStore(dir)
    check not reopened.isUniverseSyncEventApplied("event-1")
    check reopened.isUniverseSyncEventApplied("event-2")
    check reopened.isUniverseSyncEventApplied("event-3")
    reopened.close()
    removeDir(dir)

  test "Universe sync event は store transaction commit まで可視化されない":
    let dir = createTempDir("kouten-store", "universe-tx")
    var st = openStore(dir)
    var tx = st.beginTxn()
    tx.putUniverseSyncEvent(3'u64, """{"id":3,"eventKey":"e3","ring":"r"}""")
    tx.rollback()
    st.close()

    var st2 = openStore(dir)
    check 3'u64 notin st2.universeSyncEvents
    tx = st2.beginTxn()
    tx.putUniverseSyncEvent(3'u64, """{"id":3,"eventKey":"e3","ring":"r"}""")
    tx.commit()
    st2.close()

    var st3 = openStore(dir)
    check st3.universeSyncEvents[3'u64].contains("\"eventKey\":\"e3\"")
    check st3.nextUniverseSyncId == 3'u64
    st3.close()
    removeDir(dir)

  test "transaction commit は atomic に復元される":
    let dir = createTempDir("kouten-store", "tx")
    var st = openStore(dir)
    let tx = st.beginTxn()
    tx.upsert Particle(parent: 1'u64, seq: 0'u32, period: 30.0, head: 0.5,
                       tWrite: 1.0, payload: "a")
    tx.upsert Particle(parent: 1'u64, seq: 1'u32, period: 30.0, head: 0.5,
                       tWrite: 2.0, payload: "b",
                       vec: @[1.0'f32, 0.0'f32])
    tx.commit()
    st.close()

    var st2 = openStore(dir)
    check st2.items[(1'u64, 0'u32)].payload == "a"
    check st2.items[(1'u64, 1'u32)].payload == "b"
    check st2.items[(1'u64, 1'u32)].vec == @[1.0'f32, 0.0'f32]
    st2.close()
    removeDir(dir)

  test "strong durability は単発 write と transaction を再open後も復元する":
    let dir = createTempDir("kouten-store", "strong")
    var st = openStore(dir, durability = durStrong)
    st.upsert Particle(parent: 10'u64, seq: 0'u32, period: 30.0, head: 0.1,
                       tWrite: 1.0, payload: "single",
                       vec: @[0.5'f32, 0.5'f32])
    let tx = st.beginTxn()
    tx.upsert Particle(parent: 10'u64, seq: 1'u32, period: 30.0, head: 0.1,
                       tWrite: 2.0, payload: "tx")
    tx.commit()
    st.close()

    var st2 = openStore(dir, durability = durStrong)
    check st2.items[(10'u64, 0'u32)].payload == "single"
    check st2.items[(10'u64, 0'u32)].vec == @[0.5'f32, 0.5'f32]
    check st2.items[(10'u64, 1'u32)].payload == "tx"
    st2.close()
    removeDir(dir)

  test "commit marker のない transaction は replay で無視される":
    let dir = createTempDir("kouten-store", "tx-partial")
    writeFile(dir / "kouten.log",
              "T 7\n" &
              "XP 7 2 0 60.0 0.0 1.0 5 0\nhello\n")
    var st = openStore(dir)
    check not st.contains(2'u64, 0'u32)
    st.close()
    removeDir(dir)

  test "WAL 末尾の不完全レコードは最後の完全レコードまで repair される":
    let dir = createTempDir("kouten-store", "torn-tail")
    let good = "P 2 0 60.0 0.0 1.0 5\nhello\n"
    writeFile(dir / "kouten.log",
              good &
              "P 2 1 60.0 0.0 2.0 11\npartial")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(2'u64, 0'u32)].payload == "hello"
    check not st.contains(2'u64, 1'u32)
    check readFile(dir / "kouten.log") == good
    st.upsert Particle(parent: 2'u64, seq: 2'u32, period: 60.0, head: 0.0,
                       tWrite: 3.0, payload: "after")
    st.close()

    var st2 = openStore(dir)
    check st2.count() == 2
    check st2.items[(2'u64, 0'u32)].payload == "hello"
    check st2.items[(2'u64, 2'u32)].payload == "after"
    check not st2.contains(2'u64, 1'u32)
    st2.close()
    removeDir(dir)

  test "WAL 末尾の不正な長さ指定は repair される":
    let dir = createTempDir("kouten-store", "bad-len-tail")
    let good = "P 2 0 60.0 0.0 1.0 5\nhello\n"
    writeFile(dir / "kouten.log",
              good &
              "P 2 1 60.0 0.0 2.0 -1 0\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(2'u64, 0'u32)].payload == "hello"
    check not st.contains(2'u64, 1'u32)
    check readFile(dir / "kouten.log") == good
    st.close()
    removeDir(dir)

  test "WAL 末尾の不正な vector 次元は repair される":
    let dir = createTempDir("kouten-store", "bad-vec-tail")
    let good = "P 2 0 60.0 0.0 1.0 5\nhello\n"
    writeFile(dir / "kouten.log",
              good &
              "E 2 0 -1\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(2'u64, 0'u32)].payload == "hello"
    check st.items[(2'u64, 0'u32)].vec.len == 0
    check readFile(dir / "kouten.log") == good
    st.close()
    removeDir(dir)

  test "WAL 中間破損は tail repair せず起動を拒否する":
    let dir = createTempDir("kouten-store", "mid-corrupt")
    let wal = "P 2 0 60.0 0.0 1.0 5\nhello\n" &
              "P 2 1 60.0 0.0 2.0 -1 0\n" &
              "P 2 2 60.0 0.0 3.0 5 0\nlater\n"
    writeFile(dir / "kouten.log", wal)

    expect IOError:
      discard openStore(dir)
    check readFile(dir / "kouten.log") == wal
    removeDir(dir)

  test "commit marker が torn tail の transaction は repair 後も適用されない":
    let dir = createTempDir("kouten-store", "tx-torn-tail")
    let good = "P 1 0 60.0 0.0 1.0 4\nbase\n"
    writeFile(dir / "kouten.log",
              good &
              "T 12\n" &
              "XP 12 1 1 60.0 0.0 2.0 6 0\ninside\n" &
              "C")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(1'u64, 0'u32)].payload == "base"
    check not st.contains(1'u64, 1'u32)
    check readFile(dir / "kouten.log") == good &
      "T 12\n" &
      "XP 12 1 1 60.0 0.0 2.0 6 0\ninside\n"
    st.close()

    var st2 = openStore(dir)
    check st2.count() == 1
    check not st2.contains(1'u64, 1'u32)
    st2.close()
    removeDir(dir)

  test "cluster transaction intent は applied まで保持される":
    let dir = createTempDir("kouten-store", "cluster-tx")
    var st = openStore(dir)
    st.putClusterTxIntent ClusterTxIntent(
      id: 9'u64,
      ops: @[ClusterTxOp(parent: 3'u64, seq: 1'u32, period: 60.0,
                         head: 0.2, tWrite: 10.0, payload: "v",
                         vec: @[1.0'f32, 0.0'f32])],
      committed: true)
    st.close()

    var st2 = openStore(dir)
    check 9'u64 in st2.clusterTx
    check st2.clusterTx[9'u64].committed
    check not st2.clusterTx[9'u64].applied
    st2.markClusterTxApplied(9'u64)
    st2.close()

    var st3 = openStore(dir)
    check st3.clusterTx[9'u64].applied
    st3.close()
    removeDir(dir)

  test "compact 中断で tmp だけ残った場合は tmp を正規 WAL として復旧する":
    let dir = createTempDir("kouten-store", "compact-tmp")
    writeFile(dir / "kouten.log.compact",
              "G 11\nrecover-tmp\n" &
              "P 5 0 60.0 0.0 1.0 4\nlive\n")

    var st = openStore(dir)
    check st.galaxy == "recover-tmp"
    check st.count() == 1
    check st.items[(5'u64, 0'u32)].payload == "live"
    check fileExists(dir / "kouten.log")
    check not fileExists(dir / "kouten.log.compact")
    st.close()
    removeDir(dir)

  test "compact 中断で正規 WAL と tmp が両方ある場合は正規 WAL を優先する":
    let dir = createTempDir("kouten-store", "compact-log-tmp")
    writeFile(dir / "kouten.log",
              "P 6 0 60.0 0.0 1.0 4\nkeep\n")
    writeFile(dir / "kouten.log.compact",
              "P 6 1 60.0 0.0 2.0 4\ndrop\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(6'u64, 0'u32)].payload == "keep"
    check not st.contains(6'u64, 1'u32)
    check not fileExists(dir / "kouten.log.compact")
    st.close()
    removeDir(dir)

  test "compact 中断で bak だけ残った場合は bak を正規 WAL として復旧する":
    let dir = createTempDir("kouten-store", "compact-bak")
    writeFile(dir / "kouten.log.bak",
              "P 7 0 60.0 0.0 1.0 4\nback\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(7'u64, 0'u32)].payload == "back"
    check fileExists(dir / "kouten.log")
    check not fileExists(dir / "kouten.log.bak")
    st.close()
    removeDir(dir)

  test "compact は生存レコードだけで WAL を再構築する":
    let dir = createTempDir("kouten-store", "compact")
    var st = openStore(dir)
    st.setGalaxy("compact-galaxy")
    st.putGalaxyDescription("compact galaxy description")
    st.putRingName(1'u64, "docs")
    st.putRingDescription(1'u64, "docs ring description")
    st.putRingMeta(1'u64, 60.0, 0.25)
    for i in 0'u32 ..< 40'u32:
      st.upsert Particle(parent: 1'u64, seq: i, period: 60.0, head: 0.25,
                         tWrite: float(i), payload: repeat("x", 128),
                         vec: @[1.0'f32, 0.0'f32])
    for i in 0'u32 ..< 35'u32:
      st.remove(1'u64, i)
    let stats = st.compact()
    check stats.beforeBytes > stats.afterBytes
    check stats.items == 5
    check st.count() == 5
    st.close()

    var st2 = openStore(dir)
    check st2.galaxy == "compact-galaxy"
    check st2.galaxyDescription == "compact galaxy description"
    check st2.ringNames[1'u64] == "docs"
    check st2.ringDescriptions[1'u64] == "docs ring description"
    check st2.ringMeta[1'u64].period == 60.0
    check st2.count() == 5
    check not st2.contains(1'u64, 0'u32)
    check st2.contains(1'u64, 39'u32)
    check st2.items[(1'u64, 39'u32)].payload == repeat("x", 128)
    check st2.items[(1'u64, 39'u32)].vec == @[1.0'f32, 0.0'f32]
    let nextSeq = st2.nextSeq(1'u64)
    check nextSeq == 40'u32
    check st2.maxTWrite == 39.0
    st2.close()
    removeDir(dir)

  test "bare delete replay keeps itemsByRing consistent":
    let dir = createTempDir("kouten-store", "delete-replay-index")
    var st = openStore(dir)
    st.upsert Particle(parent: 30'u64, seq: 0'u32, period: 60.0, head: 0.0,
                       tWrite: 1.0, payload: "deleted")
    st.upsert Particle(parent: 30'u64, seq: 1'u32, period: 60.0, head: 0.0,
                       tWrite: 2.0, payload: "live")
    st.remove(30'u64, 0'u32)
    st.close()

    var reopened = openStore(dir)
    check reopened.count() == 1
    check not reopened.contains(30'u64, 0'u32)
    check reopened.contains(30'u64, 1'u32)
    check reopened.itemsByRing[30'u64] == @[(30'u64, 1'u32)]
    reopened.close()
    removeDir(dir)

  test "locality report は interleaved WAL と compact 後の ring grouping を測る":
    let dir = createTempDir("kouten-store", "locality")
    var st = openStore(dir)
    for i in 0'u32 ..< 12'u32:
      let ring = uint64((i mod 3) + 1)
      st.upsert Particle(parent: ring, seq: i div 3, period: 60.0,
                         head: float(ring), tWrite: float(i),
                         payload: "p" & $i, codec: pcRaw)

    let before = st.localityReport()
    check before.persistent
    check before.liveParticleRecords == 12
    check before.ringCount == 3
    check before.ringRuns == 12
    check before.fragmentedRings == 3
    check before.localityScore < 1.0

    discard st.compact()
    let after = st.localityReport()
    check after.liveParticleRecords == 12
    check after.ringCount == 3
    check after.ringRuns == 3
    check after.fragmentedRings == 0
    check after.localityScore == 1.0
    check after.avgRunRecords == 4.0
    st.close()
    removeDir(dir)

  test "locality report は上書き済み particle record を dead として数える":
    let dir = createTempDir("kouten-store", "locality-dead")
    var st = openStore(dir)
    st.upsert Particle(parent: 7'u64, seq: 0'u32, period: 60.0,
                       head: 0.0, tWrite: 1.0, payload: "old",
                       codec: pcRaw)
    st.upsert Particle(parent: 7'u64, seq: 0'u32, period: 60.0,
                       head: 0.0, tWrite: 2.0, payload: "new",
                       codec: pcRaw)
    let report = st.localityReport()
    check report.totalParticleRecords == 2
    check report.liveParticleRecords == 1
    check report.deadParticleRecords == 1
    st.close()
    removeDir(dir)

  test "locality report matrix covers delete and backfill fragmentation":
    let dir = createTempDir("kouten-store", "locality-matrix")
    var st = openStore(dir)

    for i in 0'u32 ..< 24'u32:
      let ring = uint64((i mod 4) + 1)
      st.upsert Particle(parent: ring, seq: i div 4, period: 60.0,
                         head: float(ring), tWrite: float(i),
                         payload: "p" & $i, codec: pcRaw)

    for i in countup(0'u32, 20'u32, 4):
      st.remove(1'u64, i div 4)

    for i in 0'u32 ..< 8'u32:
      let ring = uint64(((i * 3) mod 4) + 1)
      st.upsert Particle(parent: ring, seq: 100'u32 + i, period: 60.0,
                         head: float(ring), tWrite: 100.0 + float(i),
                         payload: "b" & $i, codec: pcRaw)

    let before = st.localityReport()
    let ring1Before = st.ringSignature(1'u64)
    let ring2Before = st.ringSignature(2'u64)
    let ring3Before = st.ringSignature(3'u64)
    let ring4Before = st.ringSignature(4'u64)
    check before.totalParticleRecords == 32
    check before.liveParticleRecords == 26
    check before.deadParticleRecords == 6
    check before.ringCount == 4
    check before.fragmentedRings > 0
    check before.localityScore < 1.0

    discard st.compact()
    let after = st.localityReport()
    check st.ringSignature(1'u64) == ring1Before
    check st.ringSignature(2'u64) == ring2Before
    check st.ringSignature(3'u64) == ring3Before
    check st.ringSignature(4'u64) == ring4Before
    check after.totalParticleRecords == 26
    check after.liveParticleRecords == 26
    check after.deadParticleRecords == 0
    check after.ringCount == 4
    check after.ringRuns == 4
    check after.fragmentedRings == 0
    check after.localityScore == 1.0
    st.close()
    removeDir(dir)

  test "strong durability の compact 後も WAL は復元できる":
    let dir = createTempDir("kouten-store", "strong-compact")
    var st = openStore(dir, durability = durStrong)
    for i in 0'u32 ..< 10'u32:
      st.upsert Particle(parent: 8'u64, seq: i, period: 60.0, head: 0.0,
                         tWrite: float(i), payload: "v" & $i)
    for i in 0'u32 ..< 5'u32:
      st.remove(8'u64, i)
    let stats = st.compact()
    check stats.items == 5
    st.close()

    var st2 = openStore(dir, durability = durStrong)
    check st2.count() == 5
    check not st2.contains(8'u64, 0'u32)
    check st2.items[(8'u64, 9'u32)].payload == "v9"
    st2.close()
    removeDir(dir)

  test "backup/restore は compact 済み WAL として別 dir に復元できる":
    let dir = createTempDir("kouten-store", "backup-src")
    let backupDir = createTempDir("kouten-store", "backup")
    let restoredDir = createTempDir("kouten-store", "restore")
    var st = openStore(dir)
    st.setGalaxy("backup-galaxy")
    st.putRingName(3'u64, "docs/ai")
    st.putRingMeta(3'u64, 90.0, 0.75)
    st.upsert Particle(parent: 3'u64, seq: 0'u32, period: 90.0, head: 0.75,
                       tWrite: 1.0, payload: "dead",
                       vec: @[0.0'f32, 1.0'f32])
    st.upsert Particle(parent: 3'u64, seq: 1'u32, period: 90.0, head: 0.75,
                       tWrite: 2.0, payload: "live",
                       vec: @[1.0'f32, 0.0'f32])
    st.remove(3'u64, 0'u32)
    let backupStats = st.backup(backupDir)
    check backupStats.items == 1
    st.upsert Particle(parent: 3'u64, seq: 2'u32, period: 90.0, head: 0.75,
                       tWrite: 3.0, payload: "second-live")
    let backupStats2 = st.backup(backupDir)
    check backupStats2.items == 2
    check not fileExists(backupDir / "kouten.log.tmp")
    let verifyStats = verifyBackup(backupDir)
    check verifyStats.items == 2
    st.close()

    removeDir(restoredDir)
    let restoreStats = restoreBackup(backupDir, restoredDir,
                                     durability = durStrong)
    check restoreStats.items == 2
    check not fileExists(restoredDir / "kouten.log.restore")
    var restored = openStore(restoredDir, durability = durStrong)
    check restored.galaxy == "backup-galaxy"
    check restored.ringNames[3'u64] == "docs/ai"
    check restored.ringMeta[3'u64].period == 90.0
    check not restored.contains(3'u64, 0'u32)
    check restored.items[(3'u64, 1'u32)].payload == "live"
    check restored.items[(3'u64, 1'u32)].vec == @[1.0'f32, 0.0'f32]
    check restored.items[(3'u64, 2'u32)].payload == "second-live"
    restored.close()
    expect IOError:
      discard restoreBackup(backupDir, restoredDir)
    discard restoreBackup(backupDir, restoredDir, overwrite = true,
                          durability = durStrong)
    check not fileExists(restoredDir / "kouten.log.restore")
    removeDir(dir)
    removeDir(backupDir)
    removeDir(restoredDir)

  test "壊れた plain backup は restore 前に拒否され target を壊さない":
    let srcDir = createTempDir("kouten-store", "backup-corrupt-src")
    let backupDir = createTempDir("kouten-store", "backup-corrupt")
    let targetDir = createTempDir("kouten-store", "backup-corrupt-target")

    var src = openStore(srcDir)
    src.upsert Particle(parent: 10'u64, seq: 0'u32, period: 60.0, head: 0.0,
                        tWrite: 1.0, payload: "source")
    discard src.backup(backupDir)
    src.close()

    createDir(targetDir)
    writeFile(targetDir / "kouten.log",
              "P 9 0 60.0 0.0 1.0 6 0\nstable\n")
    writeFile(backupDir / "kouten.log",
              readFile(backupDir / "kouten.log") &
              "P 10 1 60.0 0.0 2.0 7 0\npartial")

    expect IOError:
      discard verifyBackup(backupDir)
    expect IOError:
      discard restoreBackup(backupDir, targetDir, overwrite = true)

    var target = openStore(targetDir)
    check target.count() == 1
    check target.items[(9'u64, 0'u32)].payload == "stable"
    check not target.contains(10'u64, 0'u32)
    target.close()

    removeDir(srcDir)
    removeDir(backupDir)
    removeDir(targetDir)

  test "encrypted backup/restore は passphrase が一致すると復元できる":
    let dir = createTempDir("kouten-store", "enc-backup-src")
    let backupDir = createTempDir("kouten-store", "enc-backup")
    let restoredDir = createTempDir("kouten-store", "enc-restore")
    var st = openStore(dir)
    st.setGalaxy("encrypted-galaxy")
    st.upsert Particle(parent: 4'u64, seq: 0'u32, period: 60.0, head: 0.1,
                       tWrite: 1.0, payload: "secret",
                       vec: @[1.0'f32, 0.0'f32])
    let backupStats = st.backupEncrypted(backupDir, "correct-passphrase")
    check backupStats.items == 1
    let verifyStats = verifyEncryptedBackup(backupDir, "correct-passphrase")
    check verifyStats.items == 1
    check fileExists(backupDir / "kouten.backup")
    check not fileExists(backupDir / "kouten.verify.tmp")
    check not fileExists(backupDir / "kouten.log.tmp")
    check not readFile(backupDir / "kouten.backup").contains("secret")
    st.close()

    removeDir(restoredDir)
    expect CatchableError:
      discard restoreEncryptedBackup(backupDir, restoredDir, "wrong-passphrase")
    let restoreStats = restoreEncryptedBackup(backupDir, restoredDir,
                                              "correct-passphrase",
                                              durability = durStrong)
    check restoreStats.items == 1
    check not fileExists(restoredDir / "kouten.log.restore")
    var restored = openStore(restoredDir, durability = durStrong)
    check restored.galaxy == "encrypted-galaxy"
    check restored.items[(4'u64, 0'u32)].payload == "secret"
    check restored.items[(4'u64, 0'u32)].vec == @[1.0'f32, 0.0'f32]
    restored.close()
    removeDir(dir)
    removeDir(backupDir)
    removeDir(restoredDir)

  test "壊れた encrypted backup は restore 前に拒否され target を壊さない":
    let backupDir = createTempDir("kouten-store", "enc-corrupt-backup")
    let targetDir = createTempDir("kouten-store", "enc-corrupt-target")

    writeFile(backupDir / "kouten.backup", "not-a-koutendb-encrypted-backup")
    createDir(targetDir)
    writeFile(targetDir / "kouten.log",
              "P 11 0 60.0 0.0 1.0 6 0\nstable\n")

    expect IOError:
      discard verifyEncryptedBackup(backupDir, "passphrase")
    expect IOError:
      discard restoreEncryptedBackup(backupDir, targetDir, "passphrase",
                                     overwrite = true)

    var target = openStore(targetDir)
    check target.count() == 1
    check target.items[(11'u64, 0'u32)].payload == "stable"
    target.close()

    removeDir(backupDir)
    removeDir(targetDir)

  test "galaxy は data dir に固定され、違う galaxy では開けない":
    let dir = createTempDir("kouten-store", "galaxy")
    var st = openStore(dir)
    st.setGalaxy("andromeda")
    st.close()

    var st2 = openStore(dir)
    st2.setGalaxy("andromeda")
    expect ValueError:
      st2.setGalaxy("milky-way")
    st2.close()
    removeDir(dir)
