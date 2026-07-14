## roche/store の永続化テスト

import std/[os, strutils, tables, tempfiles, unittest]
import ../src/roche/store

suite "store persistence":
  test "Particle vec は E レコードで復元される":
    let dir = createTempDir("roche-store", "vec")
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
    let dir = createTempDir("roche-store", "payload-codec")
    var st = openStore(dir)
    st.upsert Particle(parent: 12'u64, seq: 0'u32, period: 60.0, head: 0.0,
                       tWrite: 1.0, payload: "(object (name RocheDB))",
                       codec: pcNif)
    st.close()

    var restored = openStore(dir)
    check restored.items[(12'u64, 0'u32)].codec == pcNif
    restored.close()
    removeDir(dir)

    let legacyDir = createTempDir("roche-store", "legacy-payload-codec")
    writeFile(legacyDir / "roche.log",
              "P 13 0 60.0 0.0 1.0 5 0\nhello\n")
    var legacy = openStore(legacyDir)
    check legacy.items[(13'u64, 0'u32)].codec == pcRaw
    legacy.close()
    removeDir(legacyDir)

  test "Forwarder は F レコードで復元される":
    let dir = createTempDir("roche-store", "fwd")
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
    let dir = createTempDir("roche-store", "warp")
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
    let dir = createTempDir("roche-store", "universe-sync")
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

  test "transaction commit は atomic に復元される":
    let dir = createTempDir("roche-store", "tx")
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
    let dir = createTempDir("roche-store", "strong")
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
    let dir = createTempDir("roche-store", "tx-partial")
    writeFile(dir / "roche.log",
              "T 7\n" &
              "XP 7 2 0 60.0 0.0 1.0 5 0\nhello\n")
    var st = openStore(dir)
    check not st.contains(2'u64, 0'u32)
    st.close()
    removeDir(dir)

  test "WAL 末尾の不完全レコードは最後の完全レコードまで repair される":
    let dir = createTempDir("roche-store", "torn-tail")
    let good = "P 2 0 60.0 0.0 1.0 5\nhello\n"
    writeFile(dir / "roche.log",
              good &
              "P 2 1 60.0 0.0 2.0 11\npartial")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(2'u64, 0'u32)].payload == "hello"
    check not st.contains(2'u64, 1'u32)
    check readFile(dir / "roche.log") == good
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
    let dir = createTempDir("roche-store", "bad-len-tail")
    let good = "P 2 0 60.0 0.0 1.0 5\nhello\n"
    writeFile(dir / "roche.log",
              good &
              "P 2 1 60.0 0.0 2.0 -1 0\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(2'u64, 0'u32)].payload == "hello"
    check not st.contains(2'u64, 1'u32)
    check readFile(dir / "roche.log") == good
    st.close()
    removeDir(dir)

  test "WAL 末尾の不正な vector 次元は repair される":
    let dir = createTempDir("roche-store", "bad-vec-tail")
    let good = "P 2 0 60.0 0.0 1.0 5\nhello\n"
    writeFile(dir / "roche.log",
              good &
              "E 2 0 -1\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(2'u64, 0'u32)].payload == "hello"
    check st.items[(2'u64, 0'u32)].vec.len == 0
    check readFile(dir / "roche.log") == good
    st.close()
    removeDir(dir)

  test "commit marker が torn tail の transaction は repair 後も適用されない":
    let dir = createTempDir("roche-store", "tx-torn-tail")
    let good = "P 1 0 60.0 0.0 1.0 4\nbase\n"
    writeFile(dir / "roche.log",
              good &
              "T 12\n" &
              "XP 12 1 1 60.0 0.0 2.0 6 0\ninside\n" &
              "C")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(1'u64, 0'u32)].payload == "base"
    check not st.contains(1'u64, 1'u32)
    check readFile(dir / "roche.log") == good &
      "T 12\n" &
      "XP 12 1 1 60.0 0.0 2.0 6 0\ninside\n"
    st.close()

    var st2 = openStore(dir)
    check st2.count() == 1
    check not st2.contains(1'u64, 1'u32)
    st2.close()
    removeDir(dir)

  test "cluster transaction intent は applied まで保持される":
    let dir = createTempDir("roche-store", "cluster-tx")
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
    let dir = createTempDir("roche-store", "compact-tmp")
    writeFile(dir / "roche.log.compact",
              "G 11\nrecover-tmp\n" &
              "P 5 0 60.0 0.0 1.0 4\nlive\n")

    var st = openStore(dir)
    check st.galaxy == "recover-tmp"
    check st.count() == 1
    check st.items[(5'u64, 0'u32)].payload == "live"
    check fileExists(dir / "roche.log")
    check not fileExists(dir / "roche.log.compact")
    st.close()
    removeDir(dir)

  test "compact 中断で正規 WAL と tmp が両方ある場合は正規 WAL を優先する":
    let dir = createTempDir("roche-store", "compact-log-tmp")
    writeFile(dir / "roche.log",
              "P 6 0 60.0 0.0 1.0 4\nkeep\n")
    writeFile(dir / "roche.log.compact",
              "P 6 1 60.0 0.0 2.0 4\ndrop\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(6'u64, 0'u32)].payload == "keep"
    check not st.contains(6'u64, 1'u32)
    check not fileExists(dir / "roche.log.compact")
    st.close()
    removeDir(dir)

  test "compact 中断で bak だけ残った場合は bak を正規 WAL として復旧する":
    let dir = createTempDir("roche-store", "compact-bak")
    writeFile(dir / "roche.log.bak",
              "P 7 0 60.0 0.0 1.0 4\nback\n")

    var st = openStore(dir)
    check st.count() == 1
    check st.items[(7'u64, 0'u32)].payload == "back"
    check fileExists(dir / "roche.log")
    check not fileExists(dir / "roche.log.bak")
    st.close()
    removeDir(dir)

  test "compact は生存レコードだけで WAL を再構築する":
    let dir = createTempDir("roche-store", "compact")
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
    st2.close()
    removeDir(dir)

  test "locality report は interleaved WAL と compact 後の ring grouping を測る":
    let dir = createTempDir("roche-store", "locality")
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
    let dir = createTempDir("roche-store", "locality-dead")
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

  test "strong durability の compact 後も WAL は復元できる":
    let dir = createTempDir("roche-store", "strong-compact")
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
    let dir = createTempDir("roche-store", "backup-src")
    let backupDir = createTempDir("roche-store", "backup")
    let restoredDir = createTempDir("roche-store", "restore")
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
    let verifyStats = verifyBackup(backupDir)
    check verifyStats.items == 1
    st.close()

    removeDir(restoredDir)
    let restoreStats = restoreBackup(backupDir, restoredDir)
    check restoreStats.items == 1
    var restored = openStore(restoredDir)
    check restored.galaxy == "backup-galaxy"
    check restored.ringNames[3'u64] == "docs/ai"
    check restored.ringMeta[3'u64].period == 90.0
    check not restored.contains(3'u64, 0'u32)
    check restored.items[(3'u64, 1'u32)].payload == "live"
    check restored.items[(3'u64, 1'u32)].vec == @[1.0'f32, 0.0'f32]
    restored.close()
    expect IOError:
      discard restoreBackup(backupDir, restoredDir)
    discard restoreBackup(backupDir, restoredDir, overwrite = true)
    removeDir(dir)
    removeDir(backupDir)
    removeDir(restoredDir)

  test "壊れた plain backup は restore 前に拒否され target を壊さない":
    let srcDir = createTempDir("roche-store", "backup-corrupt-src")
    let backupDir = createTempDir("roche-store", "backup-corrupt")
    let targetDir = createTempDir("roche-store", "backup-corrupt-target")

    var src = openStore(srcDir)
    src.upsert Particle(parent: 10'u64, seq: 0'u32, period: 60.0, head: 0.0,
                        tWrite: 1.0, payload: "source")
    discard src.backup(backupDir)
    src.close()

    createDir(targetDir)
    writeFile(targetDir / "roche.log",
              "P 9 0 60.0 0.0 1.0 6 0\nstable\n")
    writeFile(backupDir / "roche.log",
              readFile(backupDir / "roche.log") &
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
    let dir = createTempDir("roche-store", "enc-backup-src")
    let backupDir = createTempDir("roche-store", "enc-backup")
    let restoredDir = createTempDir("roche-store", "enc-restore")
    var st = openStore(dir)
    st.setGalaxy("encrypted-galaxy")
    st.upsert Particle(parent: 4'u64, seq: 0'u32, period: 60.0, head: 0.1,
                       tWrite: 1.0, payload: "secret",
                       vec: @[1.0'f32, 0.0'f32])
    let backupStats = st.backupEncrypted(backupDir, "correct-passphrase")
    check backupStats.items == 1
    let verifyStats = verifyEncryptedBackup(backupDir, "correct-passphrase")
    check verifyStats.items == 1
    check fileExists(backupDir / "roche.backup")
    check not readFile(backupDir / "roche.backup").contains("secret")
    st.close()

    removeDir(restoredDir)
    expect CatchableError:
      discard restoreEncryptedBackup(backupDir, restoredDir, "wrong-passphrase")
    let restoreStats = restoreEncryptedBackup(backupDir, restoredDir,
                                              "correct-passphrase")
    check restoreStats.items == 1
    var restored = openStore(restoredDir)
    check restored.galaxy == "encrypted-galaxy"
    check restored.items[(4'u64, 0'u32)].payload == "secret"
    check restored.items[(4'u64, 0'u32)].vec == @[1.0'f32, 0.0'f32]
    restored.close()
    removeDir(dir)
    removeDir(backupDir)
    removeDir(restoredDir)

  test "壊れた encrypted backup は restore 前に拒否され target を壊さない":
    let backupDir = createTempDir("roche-store", "enc-corrupt-backup")
    let targetDir = createTempDir("roche-store", "enc-corrupt-target")

    writeFile(backupDir / "roche.backup", "not-a-rochedb-encrypted-backup")
    createDir(targetDir)
    writeFile(targetDir / "roche.log",
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
    let dir = createTempDir("roche-store", "galaxy")
    var st = openStore(dir)
    st.setGalaxy("andromeda")
    st.close()

    var st2 = openStore(dir)
    st2.setGalaxy("andromeda")
    expect AssertionDefect:
      st2.setGalaxy("milky-way")
    st2.close()
    removeDir(dir)
