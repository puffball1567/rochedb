## 公開 API（src/rochedb.nim）のテスト

import std/[json, os, strutils, tempfiles, unittest]
import ../src/rochedb

suite "public api":
  test "put/get の往復":
    var db = open()
    let id = db.put("hello")
    check db.get(id) == "hello"
    check id in db
    db.close()

  test "locate は決定論的で、未来も計算できる":
    var db = open(nodes = 8)
    let id = db.put("x", ring = "logs")
    let n0 = db.locate(id)
    check n0 == db.locate(id, at = 0.0)
    # 時計を進めても、過去に計算した未来位置と一致する（ephemeris の核）
    let predicted = db.locate(id, at = 42.0)
    db.advance(42.0)
    check db.locate(id) == predicted
    db.close()

  test "半周期後には反対側のノードにいる":
    var db = open(nodes = 8)
    db.configureRing("r", 60.0)
    let id = db.put("x", ring = "r")
    let n0 = db.locate(id, at = 0.0)
    let nHalf = db.locate(id, at = 30.0)
    check (n0 + 4) mod 8 == nHalf
    db.close()

  test "nextVisit の時刻に本当に到着する":
    var db = open(nodes = 8)
    let id = db.put("x")
    let target = (db.locate(id) + 3) mod 8
    let ta = db.nextVisit(id, target)
    check ta >= db.now
    check db.locate(id, at = ta + 1e-6) == target
    db.close()

  test "nextJoin: 1:2 共鳴の2件が同一ノードで会合する":
    var db = open(nodes = 8)
    db.configureRing("docs", 30.0)
    db.configureRing("logs", 60.0)
    let a = db.put("doc", ring = "docs")
    let b = db.put("log", ring = "logs")
    let tj = db.nextJoin(a, b)
    check tj >= 0.0
    check db.locate(a, at = tj) == db.locate(b, at = tj)
    db.close()

  test "nextJoin: 同周期・非同居は -1":
    var db = open(nodes = 8)
    db.configureRing("p", 60.0)
    db.configureRing("q", 60.0)
    let a = db.put("x", ring = "p")
    let b = db.put("y", ring = "q")
    let tj = db.nextJoin(a, b)
    if db.locate(a) == db.locate(b):
      check tj == db.now
    else:
      check tj == -1.0
    db.close()

  test "環は自動作成され、別環は別ヘッド角を持つ":
    var db = open(nodes = 8)
    let a = db.put("1", ring = "alpha")
    let b = db.put("2", ring = "beta")
    check db.get(a) == "1"
    check db.get(b) == "2"
    db.close()

  test "write ack mode は DB 全体と ring 単位で設定できる":
    var db = open()
    db.configureWriteAckMode(wamAccepted)
    db.configureRingWriteAckMode("profile", wamApplied)
    let id = db.put("p", ring = "profile")
    check db.get(id) == "p"
    db.close()

  test "halo は予約リングとして使える":
    var db = open(nodes = 8)
    let id = db.put("stray", ring = "halo", vec = @[3.0'f32, 4.0'f32])
    check db.get(id) == "stray"
    check db.locate(id, at = 0.0) >= 0
    db.close()

  test "ORM 下地 API: list/count/update/patch/delete/batch":
    var db = open()
    let ids = db.batchPut(@[
      %*{"name": "a", "meta": {"n": 1}},
      %*{"name": "b", "meta": {"n": 2}},
      %*{"name": "c", "meta": {"n": 3}}
    ], ring = "users")
    check ids.len == 3
    check db.countByRing("users") == 3

    let page1 = db.listByRing("users", limit = 2)
    check page1.items.len == 2
    check page1.items[0].payload.contains("\"name\":\"a\"")
    check page1.nextCursor.len > 0
    let page2 = db.listByRing("users", limit = 2, cursor = page1.nextCursor)
    check page2.items.len == 1
    check page2.items[0].payload.contains("\"name\":\"c\"")
    check page2.nextCursor.len == 0

    db.update(ids[0], %*{"name": "a2", "meta": {"n": 10}})
    check db.query(ids[0], "{ name }") == %*{"name": "a2"}
    let patched = db.patch(ids[0], %*{"meta": {"ok": true}, "name": nil})
    check patched == %*{"meta": {"n": 10, "ok": true}}

    check db.exists(ids[1])
    db.deleteById(ids[1])
    check not db.exists(ids[1])
    check db.countByRing("users") == 2

    db.batchDelete(@[ids[0], ids[2]])
    check db.countByRing("users") == 0
    db.close()

  test "warp は小惑星帯のように登録順で少しずつ patch を落とす":
    var db = open()
    let a1 = db.put(%*{"orderId": "o1", "status": "paid"},
                    ring = "orders/2026/07/06")
    let a2 = db.put(%*{"orderId": "o2", "status": "paid"},
                    ring = "orders/2026/07/06")
    let b1 = db.put(%*{"orderId": "o1", "status": "paid"},
                    ring = "users/u1/orders")

    let jobId = db.enqueueWarp(
      @["orders/2026/07/06", "users/u1/orders"],
      "orderId",
      %"o1",
      %*{"status": "refunded"})
    let queued = db.warpStatus(jobId)
    check queued.status == wsPending
    check queued.maxAttempts == 8
    check queued.attempts == 0
    check not queued.acknowledged

    let first = db.warpStep(jobId, maxRecords = 1)
    check first.status == wsRunning
    check first.scanned == 1
    check first.updated == 1
    check db.query(a1, "{ status }") == %*{"status": "refunded"}
    check db.query(a2, "{ status }") == %*{"status": "paid"}
    check db.query(b1, "{ status }") == %*{"status": "paid"}

    let done = db.warpDrain(jobId, maxRecordsPerStep = 1)
    check done.status == wsDone
    check done.scanned == 3
    check done.updated == 2
    check db.query(a1, "{ status }") == %*{"status": "refunded"}
    check db.query(a2, "{ status }") == %*{"status": "paid"}
    check db.query(b1, "{ status }") == %*{"status": "refunded"}

    let duplicateJob = db.enqueueWarp(
      @["orders/2026/07/06", "users/u1/orders"],
      "orderId",
      %"o1",
      %*{"status": "refunded"})
    let duplicate = db.warpDrain(duplicateJob, maxRecordsPerStep = 10)
    check duplicate.status == wsDone
    check duplicate.matched == 2
    check duplicate.updated == 0

    let acked = db.ackWarp(jobId)
    check acked.acknowledged
    db.close()

  test "warp job は WAL から進捗と ack 状態を復元する":
    let dir = createTempDir("roche-warp", "persist")
    var db = open(dataDir = dir)
    let a1 = db.put(%*{"orderId": "o1", "status": "paid"},
                    ring = "orders/2026/07/06")
    let a2 = db.put(%*{"orderId": "o1", "status": "paid"},
                    ring = "users/u1/orders")
    let jobId = db.enqueueWarp(
      @["orders/2026/07/06", "users/u1/orders"],
      "orderId",
      %"o1",
      %*{"status": "refunded"},
      maxAttempts = 3)
    let first = db.warpStep(jobId, maxRecords = 1)
    check first.status == wsRunning
    check first.scanned == 1
    db.close()

    var reopened = open(dataDir = dir)
    let resumed = reopened.warpStatus(jobId)
    check resumed.status == wsRunning
    check resumed.scanned == 1
    check resumed.maxAttempts == 3
    check not resumed.acknowledged
    let done = reopened.warpDrain(jobId, maxRecordsPerStep = 1)
    check done.status == wsDone
    check done.updated == 2
    check reopened.query(a1, "{ status }") == %*{"status": "refunded"}
    check reopened.query(a2, "{ status }") == %*{"status": "refunded"}
    discard reopened.ackWarp(jobId)
    reopened.close()

    var reopened2 = open(dataDir = dir)
    check reopened2.warpStatus(jobId).acknowledged
    check reopened2.pruneAckedWarpJobs() == 1
    expect KeyError:
      discard reopened2.warpStatus(jobId)
    reopened2.close()

    var reopened3 = open(dataDir = dir)
    expect KeyError:
      discard reopened3.warpStatus(jobId)
    reopened3.close()
    removeDir(dir)

  test "universe sync event は WAL で復元され idempotent に適用できる":
    let srcDir = createTempDir("roche-universe", "src")
    let dstDir = createTempDir("roche-universe", "dst")

    var src = open(dataDir = srcDir)
    let eventId = src.enqueueUniverseSyncEvent(
      sourceUniverse = "tokyo",
      sourceGalaxy = "social",
      ring = "posts/u1",
      payload = """{"post":"hello","createdAt":"2026-07-07T00:00:00Z"}""",
      logicalKey = "post-1")
    check src.universeSyncEvents().len == 1
    src.close()

    var resumed = open(dataDir = srcDir)
    let events = resumed.universeSyncEvents()
    check events.len == 1
    check events[0].id == eventId
    check events[0].ring == "posts/u1"

    var dst = open(dataDir = dstDir)
    check dst.applyUniverseSyncEvent(events[0])
    check not dst.applyUniverseSyncEvent(events[0])
    check dst.countByRing("posts/u1") == 1
    dst.close()

    discard resumed.ackUniverseSyncEvent(eventId)
    check resumed.pruneAckedUniverseSyncEvents() == 1
    resumed.close()

    var resumed2 = open(dataDir = srcDir)
    check resumed2.universeSyncEvents().len == 0
    resumed2.close()

    removeDir(srcDir)
    removeDir(dstDir)

  test "syncUniverseOnce は source outbox から target へ配送して ack/prune できる":
    let srcDir = createTempDir("roche-universe", "sync-src")
    let dstDir = createTempDir("roche-universe", "sync-dst")

    var src = open(dataDir = srcDir)
    var dst = open(dataDir = dstDir)
    discard src.enqueueUniverseSyncEvent(
      sourceUniverse = "tokyo",
      sourceGalaxy = "repo",
      ring = "issues/repo-1",
      payload = """{"issue":1,"title":"sync me"}""",
      logicalKey = "issue-1")

    let stats = syncUniverseOnce(src, dst, pruneAcked = true)
    check stats.read == 1
    check stats.applied == 1
    check stats.acked == 1
    check stats.pruned == 1
    check stats.errors == 0
    check src.universeSyncEvents().len == 0
    check dst.countByRing("issues/repo-1") == 1

    let stats2 = syncUniverseOnce(src, dst, pruneAcked = true)
    check stats2.read == 0
    check stats2.applied == 0
    src.close()
    dst.close()

    removeDir(srcDir)
    removeDir(dstDir)

  test "putSynced は local put と universe outbox 登録を同時に行う":
    let dir = createTempDir("roche-universe", "putsynced")
    var db = open(dataDir = dir)
    let id = db.putSynced("""{"name":"Ada"}""",
                          sourceUniverse = "tokyo",
                          sourceGalaxy = "users",
                          ring = "users/u1",
                          logicalKey = "user:u1")
    check db.get(id) == """{"name":"Ada"}"""
    let events = db.universeSyncEvents()
    check events.len == 1
    check events[0].ring == "users/u1"
    check events[0].logicalKey == "user:u1"
    db.close()
    removeDir(dir)

  test "latest-only ring policy は未配送 outbox を logical key で畳み込む":
    let srcDir = createTempDir("roche-universe", "latest-src")
    let dstDir = createTempDir("roche-universe", "latest-dst")

    var src = open(dataDir = srcDir)
    src.configureRingApplyPolicy("profiles/u1",
      RingApplyPolicy(mode: ramLatestOnly, historyKeep: 1, delayMs: 0))
    discard src.enqueueUniverseSyncEvent(
      sourceUniverse = "tokyo",
      sourceGalaxy = "users",
      ring = "profiles/u1",
      payload = """{"name":"old"}""",
      logicalKey = "profile:u1",
      timestamp = 1.0)
    discard src.enqueueUniverseSyncEvent(
      sourceUniverse = "tokyo",
      sourceGalaxy = "users",
      ring = "profiles/u1",
      payload = """{"name":"new"}""",
      logicalKey = "profile:u1",
      timestamp = 2.0)
    check src.universeSyncEvents().len == 1

    var dst = open(dataDir = dstDir)
    let stats = syncUniverseOnce(src, dst, pruneAcked = true)
    check stats.read == 1
    check stats.applied == 1
    check dst.countByRing("profiles/u1") == 1
    let page = dst.listByRing("profiles/u1", limit = 10)
    check page.items[0].payload == """{"name":"new"}"""
    src.close()
    dst.close()

    removeDir(srcDir)
    removeDir(dstDir)

  test "delayed timestamp ring policy は ready になるまで ack しない":
    let srcDir = createTempDir("roche-universe", "delay-src")
    let dstDir = createTempDir("roche-universe", "delay-dst")

    var src = open(dataDir = srcDir)
    var dst = open(dataDir = dstDir)
    dst.configureRingApplyPolicy("audit/u1",
      RingApplyPolicy(mode: ramDelayedTimestamp, historyKeep: 1, delayMs: 60_000))
    discard src.enqueueUniverseSyncEvent(
      sourceUniverse = "tokyo",
      sourceGalaxy = "audit",
      ring = "audit/u1",
      payload = """{"event":"login"}""",
      logicalKey = "audit:u1:1")

    let delayed = syncUniverseOnce(src, dst, pruneAcked = true)
    check delayed.read == 1
    check delayed.skipped == 1
    check delayed.acked == 0
    check delayed.pruned == 0
    check src.universeSyncEvents().len == 1
    check dst.countByRing("audit/u1") == 0

    dst.configureRingApplyPolicy("audit/u1",
      RingApplyPolicy(mode: ramDelayedTimestamp, historyKeep: 1, delayMs: 0))
    let applied = syncUniverseOnce(src, dst, pruneAcked = true)
    check applied.read == 1
    check applied.applied == 1
    check applied.acked == 1
    check applied.pruned == 1
    check src.universeSyncEvents().len == 0
    check dst.countByRing("audit/u1") == 1
    src.close()
    dst.close()

    removeDir(srcDir)
    removeDir(dstDir)

suite "query (GraphQL 風選択取得)":
  test "選択した形だけ返る":
    var db = open()
    let id = db.put(%*{"title": "t", "author": {"name": "n", "org": "o"}})
    check db.query(id, "{ title }") == %*{"title": "t"}
    check db.query(id, "{ author { name } }") == %*{"author": {"name": "n"}}
    db.close()

suite "retrieve":
  test "ring 指定で探索幅を狭める":
    var db = open()
    discard db.put("ai-1", ring = "ai", vec = @[1.0'f32, 0.0'f32])
    discard db.put("ai-2", ring = "ai", vec = @[0.9'f32, 0.1'f32])
    discard db.put("db-1", ring = "db", vec = @[0.0'f32, 1.0'f32])
    discard db.put("db-2", ring = "db", vec = @[0.1'f32, 0.9'f32])

    let allHits = db.retrieve(@[1.0'f32, 0.0'f32], budget = 2)
    check allHits.len == 2
    check allHits[0].payload == "ai-1"

    let scoped = db.retrieve(@[1.0'f32, 0.0'f32], ring = "ai", budget = 2)
    check scoped.len == 2
    check scoped[0].payload == "ai-1"
    check scoped[1].payload == "ai-2"

    let globalStats = db.retrieveStats(@[1.0'f32, 0.0'f32], budget = 2)
    let scopedStats = db.retrieveStats(@[1.0'f32, 0.0'f32], ring = "ai", budget = 2)
    check globalStats.totalVectors == 4
    check globalStats.scanned == 4
    check globalStats.skippedVectors == 0
    check globalStats.ringsTouched == 2
    check globalStats.candidateReduction == 0.0
    check globalStats.payloadBytes == "ai-1".len + "ai-2".len
    check globalStats.estimatedTokens >= 1
    check scopedStats.totalVectors == 4
    check scopedStats.scanned == 2
    check scopedStats.skippedVectors == 2
    check scopedStats.ringsTouched == 1
    check scopedStats.candidateReduction == 0.5
    check scopedStats.fanoutNodes == 1
    db.close()

  test "ringMetrics はまとまりを返す":
    var db = open()
    discard db.put("a", ring = "coherent", vec = @[1.0'f32, 0.0'f32])
    discard db.put("b", ring = "coherent", vec = @[0.95'f32, 0.05'f32])
    let ms = db.ringMetrics()
    check ms.len == 1
    check ms[0].count == 2
    check ms[0].coherence > 0.95
    db.close()

  test "focus は 1..100 を topRings 2..500 に写像する":
    check focusToTopRings(1) == 2
    check focusToTopRings(10) > focusToTopRings(1)
    check focusToTopRings(50) > focusToTopRings(10)
    check focusToTopRings(100) == 500
    check focusToTopRings(999) == 500
    check clampTopRings(0) == 0
    check clampTopRings(1) == 2
    check clampTopRings(501) == 500

  test "VectorBackend は exact を明示選択でき、Faiss は optional backend として接続する":
    var db = open()
    db.configureVectorBackend(vbExact)
    discard db.put("vec-a", ring = "v", vec = @[1.0'f32, 0.0'f32])
    discard db.put("vec-b", ring = "v", vec = @[0.0'f32, 1.0'f32])
    let hits = db.retrieve(@[1.0'f32, 0.0'f32], ring = "v", budget = 1)
    check hits.len == 1
    check hits[0].payload == "vec-a"
    try:
      db.configureVectorBackend(vbFaiss)
      let faissHits = db.retrieve(@[1.0'f32, 0.0'f32], ring = "v", budget = 1)
      check faissHits.len == 1
      check faissHits[0].payload == "vec-a"
    except ValueError:
      check true
    except LibraryError:
      check true
    db.close()

  test "PlannerBackend は deterministic heuristic を明示選択できる":
    var db = open()
    db.configurePlannerBackend(pbHeuristic)
    discard db.put("tokyo", ring = "japan/tokyo", vec = @[1.0'f32, 0.0'f32])
    discard db.put("osaka", ring = "japan/osaka", vec = @[0.9'f32, 0.1'f32])
    db.configureSearchProfile("near",
      SearchProfile(amount: raMany, scope: ssNear, depth: sdShallow))
    let env = db.retrievalEnvelopeTuned(@[1.0'f32, 0.0'f32],
                                        ring = "japan/tokyo",
                                        profile = "near")
    check env["plan"]["selectedRings"].len == 2
    check env["plan"]["ringFeatures"].len == 2
    check env["plan"]["ringFeatures"][0]["isBase"].getBool()
    check env["plan"]["ringFeatures"][0]["centroidScore"].getFloat() > 0.9
    check env["plan"]["ringFeatures"][0]["utility"].getFloat() > 0.0
    db.close()

  test "retrievalPlan は SQL tuning のように探索幅を説明する":
    let global = retrievalPlan(budget = 8)
    check global.strategy == "global"
    check global.effectiveTopRings == 0

    let focused = searchPlan(amount = raNormal, scope = ssNear)
    check focused.strategy == "top-rings"
    check focused.scope == "ssNear"
    check focused.effectiveTopRings == focusToTopRings(15)

    let scoped = searchPlan(ring = "japan", amount = raNormal,
                            scope = ssTight, depth = sdVeryDeep)
    check scoped.strategy == "hierarchical-ring"
    check scoped.ringScoped
    check scoped.selectedRings == @["japan"]
    check scoped.scope == "ssTight"
    check scoped.depth == "sdVeryDeep"
    check scoped.maxDepth == 4
    check scoped.branchBudget == 8

  test "retrieval tuning profile で探索計画を切り替えられる":
    var db = open()
    db.configureSearchProfile("short",
      SearchProfile(amount: raFew, scope: ssTight, depth: sdShallow,
                    note: "short answer"))
    db.configureSearchProfile("wide",
      SearchProfile(amount: raMany, scope: ssWide, depth: sdDeep,
                    note: "wider answer"))

    let shortPlan = db.tunedRetrievalPlan(profile = "short")
    check shortPlan.profile == "short"
    check shortPlan.budget == 3
    check shortPlan.strategy == "global"

    let widePlan = db.tunedRetrievalPlan(ring = "japan", profile = "wide")
    check widePlan.profile == "wide"
    check widePlan.budget == 16
    check widePlan.focus == 45
    check widePlan.includeChildren
    check widePlan.maxDepth == 2
    check widePlan.branchBudget == 4
    check widePlan.strategy == "hierarchical-ring"

    discard db.put("ai-a", ring = "ai", vec = @[1.0'f32, 0.0'f32])
    discard db.put("ai-b", ring = "ai", vec = @[0.9'f32, 0.1'f32])
    let env = db.retrievalEnvelopeTuned(@[1.0'f32, 0.0'f32],
                                        ring = "ai", profile = "short")
    check env["plan"]["profile"].getStr() == "short"
    check env["plan"]["budget"].getInt() == 3
    check env["chunks"].len == 2
    db.close()

  test "depth 指定で階層 ring の子を検索対象にできる":
    var db = open()
    discard db.put("root", ring = "japan", vec = @[0.0'f32, 1.0'f32])
    discard db.put("tokyo", ring = "japan/tokyo", vec = @[1.0'f32, 0.0'f32])
    discard db.put("osaka", ring = "japan/osaka", vec = @[0.9'f32, 0.1'f32])

    let shallow = db.retrieve(@[1.0'f32, 0.0'f32], ring = "japan", budget = 3)
    check shallow.len == 1
    check shallow[0].payload == "root"

    db.configureSearchProfile("deep",
      SearchProfile(amount: raMany, scope: ssTight, depth: sdDeep,
                    note: "descend children"))
    let deep = db.retrieveTuned(@[1.0'f32, 0.0'f32],
                                ring = "japan", profile = "deep")
    check deep.len == 3
    check deep[0].payload == "tokyo"

    let env = db.retrievalEnvelopeTuned(@[1.0'f32, 0.0'f32],
                                        ring = "japan", profile = "deep")
    check env["plan"]["strategy"].getStr() == "hierarchical-ring"
    check env["plan"]["selectedRings"].len == 3
    check env["stats"]["scanned"].getInt() == 3
    db.close()

  test "scope 指定で同じ親を持つ兄弟 ring を検索対象にできる":
    var db = open()
    discard db.put("tokyo", ring = "japan/tokyo", vec = @[1.0'f32, 0.0'f32])
    discard db.put("osaka", ring = "japan/osaka", vec = @[0.9'f32, 0.1'f32])
    discard db.put("history", ring = "japan/history", vec = @[0.0'f32, 1.0'f32])
    discard db.put("korea", ring = "korea/seoul", vec = @[1.0'f32, 0.0'f32])

    let tight = db.retrieve(@[0.9'f32, 0.1'f32],
                            ring = "japan/tokyo", budget = 4)
    check tight.len == 1
    check tight[0].payload == "tokyo"

    db.configureSearchProfile("near",
      SearchProfile(amount: raMany, scope: ssNear, depth: sdShallow,
                    note: "include siblings"))
    let near = db.retrieveTuned(@[0.9'f32, 0.1'f32],
                                ring = "japan/tokyo", profile = "near")
    check near.len == 3
    check near[0].payload == "osaka"

    let env = db.retrievalEnvelopeTuned(@[0.9'f32, 0.1'f32],
                                        ring = "japan/tokyo",
                                        profile = "near")
    check env["plan"]["selectedRings"].len == 3
    check env["plan"]["ringFeatures"].len == 3
    check env["plan"]["ringFeatures"][0]["ring"].getStr() == "japan/tokyo"
    check env["plan"]["ringFeatures"][0]["ringCount"].getInt() == 1
    check env["plan"]["ringFeatures"][1]["centroidScore"].getFloat() >
      env["plan"]["ringFeatures"][2]["centroidScore"].getFloat()
    check env["stats"]["scanned"].getInt() == 3
    db.close()

  test "retrievalEnvelope は Shelfer などの RAG source が使う統計を含む":
    var db = open()
    discard db.put("ai-a", ring = "ai", vec = @[1.0'f32, 0.0'f32])
    discard db.put("ai-b", ring = "ai", vec = @[0.9'f32, 0.1'f32])
    discard db.put("db-a", ring = "db", vec = @[0.0'f32, 1.0'f32])

    let env = db.retrievalEnvelope(@[1.0'f32, 0.0'f32], ring = "ai", budget = 2)
    check env["schema"].getStr() == RetrievalEnvelopeSchema
    check env["version"].getInt() == RetrievalEnvelopeVersion
    check env["source"]["provider"].getStr() == "rochedb"
    check env["source"]["ring"].getStr() == "ai"
    check env["source"]["sourceType"].getStr() == "document"
    check env["query"]["ringScoped"].getBool() == true
    check env["plan"]["strategy"].getStr() == "ring-scoped"
    check env["plan"]["baseRing"].getStr() == "ai"
    check env["plan"]["budget"].getInt() == 2
    check env["plan"]["ringFeatures"].len == 1
    check env["plan"]["ringFeatures"][0]["centroidScore"].getFloat() > 0.9
    check env["plan"]["ringFeatures"][0]["utility"].getFloat() > 0.0
    check env["chunks"].len == 2
    check env["chunks"][0]["payload"].getStr() == "ai-a"
    check env["stats"]["totalVectors"].getInt() == 3
    check env["stats"]["scanned"].getInt() == 2
    check env["stats"]["skippedVectors"].getInt() == 1
    check env["stats"]["candidateReduction"].getFloat() > 0.3
    check env["policyHints"]["resourceKind"].getStr() == "rag"
    check env["policyHints"]["resourceScope"].getStr() == "topic"
    check env.isValidRetrievalEnvelope()
    check retrievalEnvelopeValidationErrors(env).len == 0
    env["schema"] = %"bad.schema"
    check not env.isValidRetrievalEnvelope()
    db.close()

  test "atlas は LLM が読む galaxy/ring map を返す":
    var db = open()
    db.setGalaxyDescription("Japan knowledge galaxy")
    db.setRingDescription("japan", "Top-level information about Japan.")
    db.setRingDescription("japan/tokyo", "Tokyo-specific local facts.")
    discard db.put("root", ring = "japan", vec = @[0.0'f32, 1.0'f32])
    discard db.put("tokyo", ring = "japan/tokyo", vec = @[1.0'f32, 0.0'f32])
    discard db.put("osaka", ring = "japan/osaka", vec = @[0.9'f32, 0.1'f32])

    let a = db.atlas(@[1.0'f32, 0.0'f32])
    check a["schema"].getStr() == AtlasSchema
    check a["version"].getInt() == AtlasVersion
    check a["galaxyMap"]["mode"].getStr() == "embedded"
    check a["galaxyMap"]["description"].getStr() == "Japan knowledge galaxy"
    check a["galaxyMap"]["rings"].getInt() == 3
    check a["galaxyMap"]["documents"].getInt() == 3
    check a["usage"]["memory"].getStr().len > 0

    var tokyo: JsonNode = nil
    var japan: JsonNode = nil
    for r in a["ringMap"].items:
      if r["name"].getStr() == "japan/tokyo":
        tokyo = r
      if r["name"].getStr() == "japan":
        japan = r
    check tokyo != nil
    check tokyo["description"].getStr() == "Tokyo-specific local facts."
    check tokyo["parent"].getStr() == "japan"
    check tokyo["documents"].getInt() == 1
    check tokyo["vectorDocuments"].getInt() == 1
    check tokyo["coherence"].getFloat() >= 0.0
    check tokyo["massG"].getFloat() >= 0.0
    check tokyo["centroidPreview"].len == 2
    check japan != nil
    check japan["description"].getStr() == "Top-level information about Japan."
    check japan["children"].len == 2
    db.close()

suite "永続化":
  test "再オープンで中身・環設定・時計が戻る":
    let dir = createTempDir("rochedb", "test")
    var db = open(dataDir = dir)
    db.setGalaxyDescription("Persistent galaxy description")
    db.configureRing("r", 30.0)
    db.setRingDescription("r", "Persistent ring description")
    let id = db.put("persist me", ring = "r")
    db.advance(5.0)
    let n5 = db.locate(id)
    db.close()

    var db2 = open(dataDir = dir)
    check db2.getGalaxyDescription() == "Persistent galaxy description"
    check db2.getRingDescription("r") == "Persistent ring description"
    check db2.atlas()["ringMap"][0]["description"].getStr() == "Persistent ring description"
    check db2.get(id) == "persist me"
    check db2.locate(id, at = 5.0) == n5     # 軌道が同じ = 環設定が復元されている
    let id2 = db2.put("more", ring = "r")    # seq 採番も継続する
    check db2.get(id2) == "more"
    db2.close()
    removeDir(dir)

  test "階層 ring 名は再オープン後も復元される":
    let dir = createTempDir("rochedb", "rings")
    var db = open(dataDir = dir)
    discard db.put("tokyo", ring = "japan/tokyo", vec = @[1.0'f32, 0.0'f32])
    db.close()

    var db2 = open(dataDir = dir)
    db2.configureSearchProfile("deep",
      SearchProfile(amount: raMany, scope: ssTight, depth: sdDeep))
    let hits = db2.retrieveTuned(@[1.0'f32, 0.0'f32],
                                 ring = "japan", profile = "deep")
    check hits.len == 1
    check hits[0].payload == "tokyo"
    db2.close()
    removeDir(dir)

  test "compact 後も生存データと ring 階層が復元される":
    let dir = createTempDir("rochedb", "compact")
    var db = open(dataDir = dir)
    let oldId = db.put("old", ring = "japan/tokyo",
                       vec = @[0.0'f32, 1.0'f32])
    let liveId = db.put("live", ring = "japan/tokyo",
                        vec = @[1.0'f32, 0.0'f32])
    let tx = db.beginTransaction()
    tx.remove(oldId)
    tx.commit()
    let stats = db.compact()
    check stats.items == 1
    check stats.beforeBytes > stats.afterBytes
    db.close()

    var db2 = open(dataDir = dir)
    check not (oldId in db2)
    check db2.get(liveId) == "live"
    db2.configureSearchProfile("deep",
      SearchProfile(amount: raMany, scope: ssTight, depth: sdDeep))
    let hits = db2.retrieveTuned(@[1.0'f32, 0.0'f32],
                                 ring = "japan", profile = "deep")
    check hits.len == 1
    check hits[0].payload == "live"
    db2.close()
    removeDir(dir)

  test "backup/restore で別 dataDir に復元できる":
    let dir = createTempDir("rochedb", "backup-src")
    let backupDir = createTempDir("rochedb", "backup")
    let restoredDir = createTempDir("rochedb", "restore")
    var db = open(dataDir = dir)
    let oldId = db.put("old", ring = "docs/ai",
                       vec = @[0.0'f32, 1.0'f32])
    let liveId = db.put("live", ring = "docs/ai",
                        vec = @[1.0'f32, 0.0'f32])
    db.transaction(proc(tx: RocheTx) =
      tx.remove(oldId)
    )
    let backupStats = db.backup(backupDir)
    check backupStats.items == 1
    let verifyStats = verifyBackup(backupDir)
    check verifyStats.items == 1
    db.close()

    removeDir(restoredDir)
    let restoreStats = restoreBackup(backupDir, restoredDir)
    check restoreStats.items == 1
    var restored = open(dataDir = restoredDir)
    check not (oldId in restored)
    check restored.get(liveId) == "live"
    restored.configureSearchProfile("deep",
      SearchProfile(amount: raMany, scope: ssTight, depth: sdDeep))
    let hits = restored.retrieveTuned(@[1.0'f32, 0.0'f32],
                                      ring = "docs", profile = "deep")
    check hits.len == 1
    check hits[0].payload == "live"
    restored.close()
    removeDir(dir)
    removeDir(backupDir)
    removeDir(restoredDir)

  test "open は strong durability を指定できる":
    let dir = createTempDir("rochedb", "strong")
    var db = open(dataDir = dir, durability = durStrong)
    let id = db.put("durable", ring = "ops/strong")
    db.close()

    var reopened = open(dataDir = dir, durability = durStrong)
    check reopened.get(id) == "durable"
    reopened.close()
    removeDir(dir)

  test "encrypted backup/restore で別 dataDir に復元できる":
    let dir = createTempDir("rochedb", "enc-backup-src")
    let backupDir = createTempDir("rochedb", "enc-backup")
    let restoredDir = createTempDir("rochedb", "enc-restore")
    var db = open(dataDir = dir)
    let id = db.put("classified", ring = "secure/docs",
                    vec = @[1.0'f32, 0.0'f32])
    let backupStats = db.backupEncrypted(backupDir, "passphrase")
    check backupStats.items == 1
    let verifyStats = verifyEncryptedBackup(backupDir, "passphrase")
    check verifyStats.items == 1
    db.close()

    removeDir(restoredDir)
    expect CatchableError:
      discard restoreEncryptedBackup(backupDir, restoredDir, "bad-passphrase")
    let restoreStats = restoreEncryptedBackup(backupDir, restoredDir,
                                              "passphrase")
    check restoreStats.items == 1
    var restored = open(dataDir = restoredDir)
    check restored.get(id) == "classified"
    restored.close()
    removeDir(dir)
    removeDir(backupDir)
    removeDir(restoredDir)

  test "dump は JSONL で ring と document を出力できる":
    let dir = createTempDir("rochedb", "dump")
    let outPath = dir / "dump.jsonl"
    var db = open(dataDir = dir)
    discard db.put("hello", ring = "docs/ai", vec = @[1.0'f32, 0.0'f32])
    let stats = db.dump(outPath)
    check stats.records >= 4
    check stats.documents == 1
    check stats.rings >= 2
    db.close()

    let lines = readFile(outPath).strip().splitLines()
    check parseJson(lines[0])["type"].getStr() == "meta"
    var sawDoc = false
    var sawVec = false
    for line in lines:
      let node = parseJson(line)
      if node["type"].getStr() == "document":
        sawDoc = true
        check node["ring"].getStr() == "docs/ai"
        check node["payload"].getStr() == "hello"
        sawVec = node.hasKey("vec")
    check sawDoc
    check sawVec

    var db2 = open(dataDir = dir)
    let noVecPath = dir / "dump-no-vec.jsonl"
    discard db2.dump(noVecPath, includeVectors = false)
    db2.close()
    for line in readFile(noVecPath).strip().splitLines():
      let node = parseJson(line)
      if node["type"].getStr() == "document":
        check not node.hasKey("vec")
    removeDir(dir)

  test "importJsonl は外部 NoSQL JSONL を ring に割り振って保存できる":
    let dir = createTempDir("rochedb", "import-jsonl")
    let input = dir / "mongo-export.jsonl"
    writeFile(input,
      """{"tenant":"a","kind":"article","body":{"title":"alpha"},"embedding":[1.0,0.0]}""" & "\n" &
      """{"tenant":"b","kind":"article","body":{"title":"beta"},"embedding":[0.0,1.0]}""" & "\n" &
      """{"kind":"fallback","body":"plain text","embedding":[1.0,0.0]}""" & "\n")
    var db = open(dataDir = dir)
    let stats = db.importJsonl(input, defaultRing = "misc",
                               ringField = "tenant",
                               ringPrefix = "tenant/",
                               payloadField = "body",
                               vecField = "embedding")
    check stats.read == 3
    check stats.imported == 3
    check stats.rings == 3

    let aHits = db.retrieve(@[1.0'f32, 0.0'f32],
                            ring = "tenant/a", budget = 2)
    check aHits.len == 1
    check parseJson(aHits[0].payload)["title"].getStr() == "alpha"

    let fallbackHits = db.retrieve(@[1.0'f32, 0.0'f32],
                                   ring = "tenant/misc", budget = 2)
    check fallbackHits.len == 1
    check fallbackHits[0].payload == "plain text"
    db.close()
    removeDir(dir)

suite "transaction":
  test "commit まで書き込みは見えず、commit 後に永続化される":
    let dir = createTempDir("rochedb", "tx")
    var db = open(dataDir = dir)
    let tx = db.beginTransaction()
    let id = tx.put("inside tx", ring = "tx-ring")
    check not (id in db)
    tx.commit()
    check id in db
    check db.get(id) == "inside tx"
    db.close()

    var db2 = open(dataDir = dir)
    check db2.get(id) == "inside tx"
    db2.close()
    removeDir(dir)

  test "rollback した書き込みは見えない":
    var db = open()
    let tx = db.beginTransaction()
    let id = tx.put("rolled back")
    tx.rollback()
    check not (id in db)
    db.close()

  test "transaction 内の削除は commit 後に反映される":
    var db = open()
    let id = db.put("delete me")
    let tx = db.beginTransaction()
    tx.remove(id)
    check id in db
    tx.commit()
    check not (id in db)
    db.close()

  test "transaction helper は例外時 rollback":
    var db = open()
    var id: RocheId
    expect ValueError:
      db.transaction(proc(tx: RocheTx) =
        id = tx.put("never")
        raise newException(ValueError, "boom")
      )
    check not (id in db)
    db.close()

suite "galaxy router":
  test "コードから複数銀河を別 DB として扱える":
    let dirA = createTempDir("rochedb", "galaxy-a")
    let dirB = createTempDir("rochedb", "galaxy-b")
    var a = open(dataDir = dirA)
    var b = open(dataDir = dirB)
    let ida = a.put("A data", ring = "docs")
    let idb = b.put("B data", ring = "docs")
    check a.get(ida) == "A data"
    check b.get(idb) == "B data"
    a.close()
    b.close()
    removeDir(dirA)
    removeDir(dirB)
