## rochecli - cluster smoke and benchmark client
##
## usage:
##   rochecli demo  --peers=host:port,...   orbital handoff and projection demo
##   rochecli bench --peers=host:port,... [--n=10000]   network path benchmark
##   rochecli health --peers=host:port,...
##   rochecli metrics --peers=host:port,...
##   rochecli shutdown --peers=host:port,...
##   rochecli rings --peers=host:port,...
##   rochecli atlas [--data=DIR | --peers=host:port,...]
##   rochecli describe-galaxy --data=DIR --description=TEXT
##   rochecli describe-ring --data=DIR --ring=RING --description=TEXT
##   rochecli retrieve-bench --peers=host:port,... [--n=10000]
##   rochecli redis-bench [--n=10000] [--payload-bytes=100] [--redis=127.0.0.1:6379]
##   rochecli rag-bench [--n=10000] [--queries=50]
##   rochecli working-set-bench [--n=100000] [--rings=100] [--queries=50]
##   rochecli memory-pressure-bench [--n=100000] [--rings=100] [--queries=50] [--payload-bytes=512]
##   rochecli doctor
##   rochecli compact --data=DIR
##   rochecli backup --data=DIR --backup=DIR
##   rochecli restore --backup=DIR --data=DIR [--overwrite]
##   rochecli backup-encrypted --data=DIR --backup=DIR --passphrase=TEXT
##   rochecli restore-encrypted --backup=DIR --data=DIR --passphrase=TEXT [--overwrite]
##   rochecli recovery-backup --data=DIR --mirror=DIR [--mirror=DIR...] [--passphrase=TEXT]
##   rochecli recovery-verify --mirror=DIR [--passphrase=TEXT]
##   rochecli dump --data=DIR [--out=FILE] [--no-vectors]
##   rochecli import-jsonl --data=DIR --in=FILE [--ring-field=FIELD] [--default-ring=RING] [--payload-field=FIELD] [--vec-field=FIELD] [--ring-prefix=PREFIX]

import std/[os, strutils, strformat, json, times, monotimes, parseopt, net, dynlib]
import rochedb

const
  RagTopics = 8
  RagGoldSlots = 128

proc ringVec(ring, ringCount: int): seq[float32] =
  result = newSeq[float32](ringCount)
  result[ring mod ringCount] = 1.0'f32

proc topicVec(topic: int, goldSlot = -1): seq[float32] =
  result = newSeq[float32](RagTopics + RagGoldSlots)
  result[topic mod RagTopics] = 1.0'f32
  if goldSlot >= 0:
    result[RagTopics + (goldSlot mod RagGoldSlots)] = 0.5'f32

proc distractorVec(topic: int): seq[float32] =
  result = newSeq[float32](RagTopics + RagGoldSlots)
  result[topic mod RagTopics] = 0.92'f32
  result[(topic + 1) mod RagTopics] = 0.08'f32

proc tokenEstimate(payloads: seq[string]): int =
  var bytes = 0
  for p in payloads:
    bytes += p.len
  (bytes + 3) div 4

proc approxCandidateBytes(scanned, payloadBytes, vectorDim: int): int =
  ## Estimated working-set bytes if downstream ANN/rerank/LLM preprocessing
  ## keeps candidates in memory. 64B is a conservative estimate for candidate
  ## metadata such as ID, score, reference, and allocator overhead.
  scanned * (payloadBytes + vectorDim * sizeof(float32) + 64)

proc parseHostPort(endpoint: string): tuple[host: string, port: int] =
  let p = endpoint.rsplit(":", maxsplit = 1)
  if p.len == 2:
    (host: p[0], port: parseInt(p[1]))
  else:
    (host: endpoint, port: 6379)

proc checkFile(path, label: string): bool =
  result = fileExists(path)
  if result:
    echo "ok   ", label, ": ", path
  else:
    echo "miss ", label, ": ", path

proc checkDir(path, label: string): bool =
  result = dirExists(path)
  if result:
    echo "ok   ", label, ": ", path
  else:
    echo "miss ", label, ": ", path

proc runDoctor() =
  echo "RocheDB setup doctor"
  var ok = true
  ok = checkDir("third_party/faiss", "FAISS source") and ok
  ok = checkFile("third_party/faiss.version", "FAISS pinned version") and ok
  ok = checkFile("lib/libroche_faiss.so", "FAISS bridge") and ok

  if fileExists("lib/libroche_faiss.so"):
    let lib = loadLib("lib/libroche_faiss.so")
    if lib == nil:
      echo "fail FAISS bridge load: lib/libroche_faiss.so"
      echo "     Check that FAISS shared libraries are discoverable."
      ok = false
    else:
      unloadLib(lib)
      echo "ok   FAISS bridge load: lib/libroche_faiss.so"

  if ok:
    echo "status: ready"
  else:
    echo "status: setup incomplete"
    echo ""
    echo "Run:"
    echo "  scripts/fetch_faiss.sh"
    echo "  scripts/setup_faiss_toolchain.sh   # if system CMake is too old"
    echo "  scripts/build_faiss_bridge.sh"
    echo "  nim c -d:ssl -o:bin/rochecli src/rochecli.nim"
    echo "  bin/rochecli doctor"
    quit(1)

proc redisBulk(parts: varargs[string]): string =
  result.add "*" & $parts.len & "\r\n"
  for part in parts:
    result.add "$" & $part.len & "\r\n" & part & "\r\n"

proc readRedisLine(sock: Socket): string =
  result = sock.recvLine()
  if result.endsWith("\r"):
    result.setLen(result.len - 1)

proc readRedisReply(sock: Socket): string =
  let line = sock.readRedisLine()
  if line.len == 0:
    raise newException(IOError, "empty Redis reply")
  case line[0]
  of '+':
    result = line[1 .. ^1]
  of '-':
    raise newException(IOError, "Redis error: " & line[1 .. ^1])
  of ':':
    result = line[1 .. ^1]
  of '$':
    let n = parseInt(line[1 .. ^1])
    if n < 0:
      return ""
    result = sock.recv(n)
    discard sock.recv(2)
  else:
    raise newException(IOError, "unsupported Redis reply: " & line)

proc sendRedis(sock: Socket, parts: varargs[string]): string =
  sock.send(redisBulk(parts))
  sock.readRedisReply()

proc redisPipeline(sock: Socket, commands: seq[seq[string]]): seq[string] =
  var payload = ""
  for cmd in commands:
    payload.add redisBulk(cmd)
  sock.send(payload)
  for _ in 0 ..< commands.len:
    result.add sock.readRedisReply()

proc runDemo(peers, username, password, authToken, secretKey, galaxy: string) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  db.configureRing("docs", 12.0)   # short demo period: one orbit per 12 seconds
  let id = db.put(%*{
    "title": "ephemeris-based placement",
    "author": {"name": "holmes", "org": "oss"},
    "tags": ["distributed", "orbital"],
    "body": "...long body..."
  }, ring = "docs")

  echo "put complete. Server-side projection:"
  echo "  query {title author{name}} -> ", db.query(id, "{ title author { name } }")
  echo ""
  echo "A record orbits with a 12s period and moves between server processes:"
  let t0 = epochTime()
  for step in 0 .. 6:
    let node = db.locate(id)
    let v = db.query(id, "{ title }")
    var counts = ""
    for (n, c) in db.stats():
      counts.add &" node{n}={c}"
    echo &"  t={epochTime() - t0:5.1f}s  locate=node{node}  get=OK({v})  held:{counts}"
    if step < 6: sleep(2000)
  echo ""
  echo "Future location, computed locally with no lookup:"
  for dt in [5.0, 10.0, 20.0]:
    echo &"  after {dt:4.0f}s -> node", db.locate(id, at = epochTime() + dt)
  db.close()
  echo "OK"

proc pickStableRing(db: RocheDb, horizon: float): string =
  ## Choose a ring that does not cross an arc boundary during the measurement,
  ## using only the public API. This works because future location is computed.
  for i in 0 .. 20:
    result = "bench" & $i
    let probe = db.put("probe", ring = result)
    if db.locate(probe) == db.locate(probe, at = epochTime() + horizon):
      return
  result = "bench"

proc runBench(peers, username, password, authToken, secretKey, galaxy: string, n: int) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  let ring = db.pickStableRing(horizon = 60.0)
  var payload = newString(100)
  for i in 0 ..< 100: payload[i] = char(ord('a') + i mod 26)
  var ids = newSeq[RocheId](n)

  var t = getMonoTime()
  for i in 0 ..< n:
    ids[i] = db.put(payload, ring = ring)
  let putUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)

  t = getMonoTime()
  var got = 0
  for i in 0 ..< n:
    got += db.get(ids[i]).len
  let getUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)
  doAssert got == n * 100

  # Projection benchmark: store JSON and read only one field.
  let jid = db.put(%*{"a": 1, "big": payload}, ring = ring)
  t = getMonoTime()
  for i in 0 ..< n:
    discard db.query(jid, "{ a }")
  let qryUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)

  echo &"  put  (TCP, persistent connection) {putUs:8.1f} µs/op  ({1e6 / putUs:8.0f} ops/s)"
  echo &"  get  (TCP, locate+1RTT)           {getUs:8.1f} µs/op  ({1e6 / getUs:8.0f} ops/s)"
  echo &"  query(server-side projection)     {qryUs:8.1f} µs/op  ({1e6 / qryUs:8.0f} ops/s)"
  db.close()

proc runHealth(peers, username, password, authToken, secretKey, galaxy: string) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  for line in db.health():
    echo line
  db.close()

proc runMetrics(peers, username, password, authToken, secretKey, galaxy: string) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  for line in db.metrics():
    echo line
  db.close()

proc runShutdown(peers, username, password, authToken, secretKey, galaxy: string) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  for line in db.shutdownCluster():
    echo line
  db.close()

proc runRings(peers, username, password, authToken, secretKey, galaxy: string) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  for rs in db.ringSummaries():
    echo &"ring={rs.ringKey} count={rs.count} score={rs.score:.4f}"
  db.close()

proc runAtlas(dataDir, peers, username, password, authToken, secretKey,
              galaxy: string) =
  var db =
    if peers.len > 0:
      connect(peers, username = username, password = password,
              authToken = authToken, secretKey = secretKey, galaxy = galaxy)
    else:
      open(dataDir = dataDir)
  echo db.atlas().pretty
  db.close()

proc runDescribeGalaxy(dataDir, description: string) =
  if dataDir.len == 0:
    quit "describe-galaxy requires --data=DIR", 1
  var db = open(dataDir = dataDir)
  db.setGalaxyDescription(description)
  db.close()
  echo "describe-galaxy OK"

proc runDescribeRing(dataDir, ring, description: string) =
  if dataDir.len == 0:
    quit "describe-ring requires --data=DIR", 1
  if ring.len == 0:
    quit "describe-ring requires --ring=RING", 1
  var db = open(dataDir = dataDir)
  db.setRingDescription(ring, description)
  db.close()
  echo "describe-ring OK ring=" & ring

proc runRetrieveBench(peers, username, password, authToken, secretKey, galaxy: string,
                      n: int) =
  var db = connect(peers, username = username, password = password,
                   authToken = authToken, secretKey = secretKey, galaxy = galaxy)
  for i in 0 ..< n:
    let ring = if i mod 2 == 0: "ai" else: "logs"
    let v =
      if i mod 2 == 0:
        @[1.0'f32, float32(i mod 17) / 1000.0'f32]
      else:
        @[float32(i mod 17) / 1000.0'f32, 1.0'f32]
    discard db.put(%*{"i": i, "ring": ring, "body": "abcdefghijklmnopqrstuvwxyz"}, ring = ring, vec = v)

  let q = @[1.0'f32, 0.0'f32]
  var t = getMonoTime()
  let globalStats = db.retrieveStats(q, budget = 8)
  let globalHits = db.retrieve(q, budget = 8)
  let globalUs = float((getMonoTime() - t).inNanoseconds) / 1e3

  t = getMonoTime()
  let scopedStats = db.retrieveStats(q, ring = "ai", budget = 8)
  let scopedHits = db.retrieve(q, ring = "ai", budget = 8)
  let scopedUs = float((getMonoTime() - t).inNanoseconds) / 1e3

  echo &"  global retrieve       {globalUs:8.1f} µs  hits={globalHits.len} scanned={globalStats.scanned}/{globalStats.totalVectors} rings={globalStats.ringsTouched} tokens~={globalStats.estimatedTokens}"
  echo &"  ring-scoped retrieve  {scopedUs:8.1f} µs  hits={scopedHits.len} scanned={scopedStats.scanned}/{scopedStats.totalVectors} rings={scopedStats.ringsTouched} tokens~={scopedStats.estimatedTokens} reduction={scopedStats.candidateReduction * 100.0:5.1f}%"
  db.close()

proc runRedisBench(n, payloadBytes: int, redisEndpoint, peers, username,
                   password, authToken, secretKey, galaxy: string) =
  ## Simple KV comparison between localhost Redis GET and RocheDB embedded get.
  ## The workload is favorable to Redis; the goal is to observe the latency band.
  let ep = parseHostPort(redisEndpoint)
  var payload = newString(max(1, payloadBytes))
  for i in 0 ..< payload.len:
    payload[i] = char(ord('a') + i mod 26)

  var db = open()
  var ids = newSeq[RocheId](n)
  var t = getMonoTime()
  for i in 0 ..< n:
    ids[i] = db.put(payload, ring = "redis-bench")
  let rocheSetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)

  t = getMonoTime()
  var rocheGot = 0
  for i in 0 ..< n:
    rocheGot += db.get(ids[i]).len
  let rocheGetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)
  doAssert rocheGot == n * payload.len
  db.close()

  var rocheTcpPutUs = 0.0
  var rocheTcpGetUs = 0.0
  var rocheTcpBatchGetUs = 0.0
  const PipeBatch = 256
  if peers.len > 0:
    var tcp = connect(peers, username = username, password = password,
                      authToken = authToken, secretKey = secretKey,
                      galaxy = galaxy)
    var tcpIds = newSeq[RocheId](n)
    t = getMonoTime()
    for i in 0 ..< n:
      tcpIds[i] = tcp.put(payload, ring = "redis-bench")
    rocheTcpPutUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)

    t = getMonoTime()
    var tcpGot = 0
    for i in 0 ..< n:
      tcpGot += tcp.get(tcpIds[i]).len
    rocheTcpGetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)
    doAssert tcpGot == n * payload.len

    t = getMonoTime()
    var tcpBatchGot = 0
    var start = 0
    while start < n:
      let stop = min(n, start + PipeBatch)
      for value in tcp.batchGet(tcpIds[start ..< stop]):
        tcpBatchGot += value.len
      start = stop
    rocheTcpBatchGetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)
    doAssert tcpBatchGot == n * payload.len
    tcp.close()

  var sock = newSocket()
  sock.connect(ep.host, Port(ep.port))
  defer: sock.close()
  discard sock.sendRedis("PING")
  let prefix = "rochedb:bench:" & $epochTime() & ":"

  t = getMonoTime()
  for i in 0 ..< n:
    discard sock.sendRedis("SET", prefix & $i, payload)
  let redisSetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)

  t = getMonoTime()
  var redisGot = 0
  for i in 0 ..< n:
    redisGot += sock.sendRedis("GET", prefix & $i).len
  let redisGetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)
  doAssert redisGot == n * payload.len

  t = getMonoTime()
  var start = 0
  while start < n:
    let stop = min(n, start + PipeBatch)
    var cmds: seq[seq[string]] = @[]
    for i in start ..< stop:
      cmds.add @["SET", prefix & "pipe:" & $i, payload]
    discard sock.redisPipeline(cmds)
    start = stop
  let redisPipeSetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)

  t = getMonoTime()
  var redisPipeGot = 0
  start = 0
  while start < n:
    let stop = min(n, start + PipeBatch)
    var cmds: seq[seq[string]] = @[]
    for i in start ..< stop:
      cmds.add @["GET", prefix & "pipe:" & $i]
    for value in sock.redisPipeline(cmds):
      redisPipeGot += value.len
    start = stop
  let redisPipeGetUs = float((getMonoTime() - t).inNanoseconds) / 1e3 / float(n)
  doAssert redisPipeGot == n * payload.len

  for i in 0 ..< n:
    discard sock.sendRedis("DEL", prefix & $i)
    discard sock.sendRedis("DEL", prefix & "pipe:" & $i)

  echo &"  payload={payload.len}B n={n} redis={redisEndpoint}"
  echo &"  RocheDB embedded put {rocheSetUs:8.2f} µs/op ({1e6 / rocheSetUs:9.0f} ops/s)"
  echo &"  RocheDB embedded get {rocheGetUs:8.2f} µs/op ({1e6 / rocheGetUs:9.0f} ops/s)"
  if peers.len > 0:
    echo &"  RocheDB TCP put      {rocheTcpPutUs:8.2f} µs/op ({1e6 / rocheTcpPutUs:9.0f} ops/s)"
    echo &"  RocheDB TCP get      {rocheTcpGetUs:8.2f} µs/op ({1e6 / rocheTcpGetUs:9.0f} ops/s)"
    echo &"  RocheDB TCP batch get{rocheTcpBatchGetUs:8.2f} µs/op ({1e6 / rocheTcpBatchGetUs:9.0f} ops/s)"
  echo &"  Redis localhost SET  {redisSetUs:8.2f} µs/op ({1e6 / redisSetUs:9.0f} ops/s)"
  echo &"  Redis localhost GET  {redisGetUs:8.2f} µs/op ({1e6 / redisGetUs:9.0f} ops/s)"
  echo &"  Redis pipeline SET   {redisPipeSetUs:8.2f} µs/op ({1e6 / redisPipeSetUs:9.0f} ops/s)"
  echo &"  Redis pipeline GET   {redisPipeGetUs:8.2f} µs/op ({1e6 / redisPipeGetUs:9.0f} ops/s)"
  if peers.len > 0:
    echo &"  get_ratio redis_tcp/roche_tcp={redisGetUs / rocheTcpGetUs:6.2f}x redis_pipe/roche_tcp={redisPipeGetUs / rocheTcpGetUs:6.2f}x"
    echo &"  batch_ratio redis_pipe/roche_batch={redisPipeGetUs / rocheTcpBatchGetUs:6.2f}x"
  echo &"  get_ratio redis_tcp/roche_embedded={redisGetUs / rocheGetUs:6.2f}x redis_pipe/roche_embedded={redisPipeGetUs / rocheGetUs:6.2f}x"

proc runRagBench(n, queries, globalBudget, routedBudget: int) =
  ## Synthetic RAG benchmark without an LLM. Each query has one gold document;
  ## this checks whether routing keeps the gold document while reducing tokens.
  var db = open()
  let docsPerTopic = max(1, n div RagTopics)
  var goldIds: seq[string] = @[]

  for topic in 0 ..< RagTopics:
    let ring = "topic-" & $topic
    for i in 0 ..< docsPerTopic:
      let gold = i < queries
      let gid = "topic-" & $topic & "-gold-" & $i
      let body =
        if gold:
          gid & " " & repeat("relevant scientific medical water treatment evidence ", 20)
        else:
          "distractor-" & $topic & "-" & $i & " " & repeat("background unrelated archive material ", 20)
      discard db.put(body, ring = ring,
                     vec = (if gold: topicVec(topic, i) else: distractorVec(topic)))
      if gold:
        goldIds.add gid

  var globalHit = 0
  var routedHit = 0
  var wrongHit = 0
  var globalTokens = 0
  var routedTokens = 0
  var wrongTokens = 0
  var globalScanned = 0
  var routedScanned = 0
  var wrongScanned = 0

  let qn = min(queries, goldIds.len)
  for qi in 0 ..< qn:
    let topic = qi mod RagTopics
    let gold = "topic-" & $topic & "-gold-" & $(qi div RagTopics)
    let q = topicVec(topic, qi div RagTopics)

    let gh = db.retrieve(q, budget = globalBudget)
    let gs = db.retrieveStats(q, budget = globalBudget)
    var gp: seq[string] = @[]
    var gFound = false
    for h in gh:
      gp.add h.payload
      if gold in h.payload:
        gFound = true
    if gFound:
      inc globalHit
    globalTokens += tokenEstimate(gp)
    globalScanned += gs.scanned

    let rh = db.retrieve(q, ring = "topic-" & $topic, budget = routedBudget)
    let rs = db.retrieveStats(q, ring = "topic-" & $topic, budget = routedBudget)
    var rp: seq[string] = @[]
    var rFound = false
    for h in rh:
      rp.add h.payload
      if gold in h.payload:
        rFound = true
    if rFound:
      inc routedHit
    routedTokens += tokenEstimate(rp)
    routedScanned += rs.scanned

    let wrongRing = "topic-" & $((topic + 1) mod RagTopics)
    let wh = db.retrieve(q, ring = wrongRing, budget = routedBudget)
    let ws = db.retrieveStats(q, ring = wrongRing, budget = routedBudget)
    var wp: seq[string] = @[]
    var wFound = false
    for h in wh:
      wp.add h.payload
      if gold in h.payload:
        wFound = true
    if wFound:
      inc wrongHit
    wrongTokens += tokenEstimate(wp)
    wrongScanned += ws.scanned

  let gRecall = if qn == 0: 0.0 else: float(globalHit) / float(qn)
  let rRecall = if qn == 0: 0.0 else: float(routedHit) / float(qn)
  let wRecall = if qn == 0: 0.0 else: float(wrongHit) / float(qn)
  let tokenReduction =
    if globalTokens == 0: 0.0
    else: 1.0 - float(routedTokens) / float(globalTokens)
  let scanReduction =
    if globalScanned == 0: 0.0
    else: 1.0 - float(routedScanned) / float(globalScanned)

  echo &"  global      recall={gRecall:5.3f} scanned/query={float(globalScanned)/float(qn):8.1f} tokens/query~={float(globalTokens)/float(qn):8.1f} budget={globalBudget}"
  echo &"  routed      recall={rRecall:5.3f} scanned/query={float(routedScanned)/float(qn):8.1f} tokens/query~={float(routedTokens)/float(qn):8.1f} budget={routedBudget}"
  echo &"  wrong-ring  recall={wRecall:5.3f} scanned/query={float(wrongScanned)/float(qn):8.1f} tokens/query~={float(wrongTokens)/float(qn):8.1f}"
  echo &"  reduction   scanned={scanReduction * 100.0:5.1f}% tokens={tokenReduction * 100.0:5.1f}% quality_delta={rRecall - gRecall:6.3f}"
  db.close()

proc runWorkingSetBench(n, ringCount, queries, budget: int) =
  ## Minimal "full corpus vs semantic working set" benchmark for workloads
  ## where same-quality candidates are localized by ring.
  let rings = max(1, ringCount)
  var db = open()
  var payload = newString(96)
  for i in 0 ..< payload.len:
    payload[i] = char(ord('a') + i mod 26)

  for i in 0 ..< n:
    let r = i mod rings
    discard db.put(%*{"i": i, "ring": r, "body": payload},
                   ring = "bench/ring-" & $r,
                   vec = ringVec(r, rings))

  var globalScanned = 0
  var routedScanned = 0
  var globalTokens = 0
  var routedTokens = 0
  var globalNs = 0
  var routedNs = 0
  let qn = max(1, queries)
  for qi in 0 ..< qn:
    let r = qi mod rings
    let q = ringVec(r, rings)
    var t = getMonoTime()
    let gs = db.retrieveWithStats(q, budget = budget)
    globalNs += int((getMonoTime() - t).inNanoseconds)
    t = getMonoTime()
    let rs = db.retrieveWithStats(q, ring = "bench/ring-" & $r, budget = budget)
    routedNs += int((getMonoTime() - t).inNanoseconds)
    globalScanned += gs.stats.scanned
    routedScanned += rs.stats.scanned
    globalTokens += gs.stats.estimatedTokens
    routedTokens += rs.stats.estimatedTokens

  let scanReduction =
    if globalScanned == 0: 0.0
    else: 1.0 - float(routedScanned) / float(globalScanned)
  let tokenReduction =
    if globalTokens == 0: 0.0
    else: 1.0 - float(routedTokens) / float(globalTokens)
  let workset =
    if rings == 0: n else: (n + rings - 1) div rings
  let scanRatio =
    if routedScanned == 0: 0.0 else: float(globalScanned) / float(routedScanned)
  echo &"  corpus={n} rings={rings} working_set~={workset} budget={budget} queries={qn}"
  echo &"  global   scanned/query={float(globalScanned)/float(qn):10.1f} tokens/query~={float(globalTokens)/float(qn):8.1f} latency/query={float(globalNs)/1e3/float(qn):10.1f} µs"
  echo &"  routed   scanned/query={float(routedScanned)/float(qn):10.1f} tokens/query~={float(routedTokens)/float(qn):8.1f} latency/query={float(routedNs)/1e3/float(qn):10.1f} µs"
  echo &"  reduction scanned={scanReduction * 100.0:6.2f}% tokens={tokenReduction * 100.0:6.2f}% scan_ratio={scanRatio:8.1f}x"
  db.close()

proc runMemoryPressureBench(n, ringCount, queries, budget, payloadBytes: int) =
  ## Synthetic benchmark for the demand-side memory reduction hypothesis.
  ## Compares estimated candidate working-set bytes for full-corpus candidates
  ## and ring-routed semantic working-set candidates.
  let rings = max(1, ringCount)
  let docPayloadBytes = max(1, payloadBytes)
  var db = open()
  var payload = newString(docPayloadBytes)
  for i in 0 ..< payload.len:
    payload[i] = char(ord('a') + i mod 26)

  for i in 0 ..< n:
    let r = i mod rings
    discard db.put(%*{"i": i, "ring": r, "body": payload},
                   ring = "memory/ring-" & $r,
                   vec = ringVec(r, rings))

  var globalScanned = 0
  var routedScanned = 0
  var globalCandidateBytes = 0
  var routedCandidateBytes = 0
  var globalTokens = 0
  var routedTokens = 0
  var globalNs = 0
  var routedNs = 0
  let qn = max(1, queries)
  for qi in 0 ..< qn:
    let r = qi mod rings
    let q = ringVec(r, rings)

    var t = getMonoTime()
    let gs = db.retrieveWithStats(q, budget = budget)
    globalNs += int((getMonoTime() - t).inNanoseconds)

    t = getMonoTime()
    let rs = db.retrieveWithStats(q, ring = "memory/ring-" & $r, budget = budget)
    routedNs += int((getMonoTime() - t).inNanoseconds)

    globalScanned += gs.stats.scanned
    routedScanned += rs.stats.scanned
    globalTokens += gs.stats.estimatedTokens
    routedTokens += rs.stats.estimatedTokens
    globalCandidateBytes += approxCandidateBytes(gs.stats.scanned, docPayloadBytes, rings)
    routedCandidateBytes += approxCandidateBytes(rs.stats.scanned, docPayloadBytes, rings)

  let scanReduction =
    if globalScanned == 0: 0.0
    else: 1.0 - float(routedScanned) / float(globalScanned)
  let tokenReduction =
    if globalTokens == 0: 0.0
    else: 1.0 - float(routedTokens) / float(globalTokens)
  let memoryReduction =
    if globalCandidateBytes == 0: 0.0
    else: 1.0 - float(routedCandidateBytes) / float(globalCandidateBytes)
  let memoryRatio =
    if routedCandidateBytes == 0: 0.0
    else: float(globalCandidateBytes) / float(routedCandidateBytes)
  let workset =
    if rings == 0: n else: (n + rings - 1) div rings

  echo &"  corpus={n} rings={rings} working_set~={workset} payload={docPayloadBytes}B vector_dim={rings} budget={budget} queries={qn}"
  echo &"  global   scanned/query={float(globalScanned)/float(qn):10.1f} candidate_memory/query~={float(globalCandidateBytes)/1024.0/1024.0/float(qn):10.3f} MiB tokens/query~={float(globalTokens)/float(qn):8.1f} latency/query={float(globalNs)/1e3/float(qn):10.1f} µs"
  echo &"  routed   scanned/query={float(routedScanned)/float(qn):10.1f} candidate_memory/query~={float(routedCandidateBytes)/1024.0/1024.0/float(qn):10.3f} MiB tokens/query~={float(routedTokens)/float(qn):8.1f} latency/query={float(routedNs)/1e3/float(qn):10.1f} µs"
  echo &"  reduction scanned={scanReduction * 100.0:6.2f}% candidate_memory={memoryReduction * 100.0:6.2f}% tokens={tokenReduction * 100.0:6.2f}% memory_ratio={memoryRatio:8.1f}x"
  echo "  note      candidate_memory is estimated scanned working-set bytes, not whole-process RSS"
  db.close()

proc runCompact(dataDir: string) =
  if dataDir.len == 0:
    raise newException(ValueError, "compact requires --data=DIR")
  var db = open(dataDir = dataDir)
  let stats = db.compact()
  db.close()
  echo &"compact OK before={stats.beforeBytes} after={stats.afterBytes} items={stats.items} rings={stats.ringMeta} names={stats.ringNames} clusterTx={stats.clusterTx}"

proc runBackup(dataDir, backupDir: string) =
  if dataDir.len == 0 or backupDir.len == 0:
    raise newException(ValueError, "backup requires --data=DIR --backup=DIR")
  var db = open(dataDir = dataDir)
  let stats = db.backup(backupDir)
  db.close()
  echo &"backup OK bytes={stats.bytes} items={stats.items} rings={stats.ringMeta} names={stats.ringNames} from={stats.source} to={stats.destination}"

proc runRestore(backupDir, dataDir: string, overwrite: bool) =
  if dataDir.len == 0 or backupDir.len == 0:
    raise newException(ValueError, "restore requires --backup=DIR --data=DIR")
  let stats = restoreBackup(backupDir, dataDir, overwrite = overwrite)
  echo &"restore OK bytes={stats.bytes} items={stats.items} rings={stats.ringMeta} names={stats.ringNames} from={stats.source} to={stats.destination}"

proc runBackupEncrypted(dataDir, backupDir, passphrase: string) =
  if dataDir.len == 0 or backupDir.len == 0 or passphrase.len == 0:
    raise newException(ValueError,
      "backup-encrypted requires --data=DIR --backup=DIR --passphrase=TEXT")
  var db = open(dataDir = dataDir)
  let stats = db.backupEncrypted(backupDir, passphrase)
  db.close()
  echo &"backup-encrypted OK bytes={stats.bytes} items={stats.items} rings={stats.ringMeta} names={stats.ringNames} from={stats.source} to={stats.destination}"

proc runRestoreEncrypted(backupDir, dataDir, passphrase: string,
                         overwrite: bool) =
  if dataDir.len == 0 or backupDir.len == 0 or passphrase.len == 0:
    raise newException(ValueError,
      "restore-encrypted requires --backup=DIR --data=DIR --passphrase=TEXT")
  let stats = restoreEncryptedBackup(backupDir, dataDir, passphrase,
                                     overwrite = overwrite)
  echo &"restore-encrypted OK bytes={stats.bytes} items={stats.items} rings={stats.ringMeta} names={stats.ringNames} from={stats.source} to={stats.destination}"

proc recoveryManifest(encrypted: bool, mirror, backupFile: string,
                      stats: BackupStats): JsonNode =
  %*{
    "version": 1,
    "kind": "rochedb-recovery-mirror",
    "createdAt": $now(),
    "encrypted": encrypted,
    "mirror": mirror,
    "backupFile": backupFile,
    "bytes": stats.bytes,
    "items": stats.items,
    "rings": stats.ringMeta,
    "names": stats.ringNames,
    "clusterTx": stats.clusterTx,
    "appliedClusterTx": stats.appliedClusterTx,
    "warpJobs": stats.warpJobs
  }

proc writeRecoveryManifest(mirror: string, manifest: JsonNode) =
  writeFile(mirror / "roche.recovery.json", pretty(manifest))

proc runRecoveryBackup(dataDir: string, mirrors: seq[string],
                       passphrase: string) =
  if dataDir.len == 0 or mirrors.len == 0:
    raise newException(ValueError,
      "recovery-backup requires --data=DIR --mirror=DIR [--mirror=DIR...]")
  var db = open(dataDir = dataDir)
  try:
    for mirror in mirrors:
      let encrypted = passphrase.len > 0
      let stats =
        if encrypted: db.backupEncrypted(mirror, passphrase)
        else: db.backup(mirror)
      let verified =
        if encrypted: verifyEncryptedBackup(mirror, passphrase)
        else: verifyBackup(mirror)
      let backupFile = mirror / (if encrypted: "roche.backup" else: "roche.log")
      writeRecoveryManifest(mirror, recoveryManifest(encrypted, mirror,
                                                    backupFile, verified))
      echo &"recovery-backup OK mirror={mirror} encrypted={encrypted} bytes={verified.bytes} items={verified.items} source={stats.source}"
  finally:
    db.close()

proc runRecoveryVerify(mirror, passphrase: string) =
  if mirror.len == 0:
    raise newException(ValueError, "recovery-verify requires --mirror=DIR")
  let encrypted = passphrase.len > 0
  let stats =
    if encrypted: verifyEncryptedBackup(mirror, passphrase)
    else: verifyBackup(mirror)
  let manifestPath = mirror / "roche.recovery.json"
  if fileExists(manifestPath):
    let manifest = parseFile(manifestPath)
    if manifest.hasKey("encrypted") and manifest["encrypted"].getBool() != encrypted:
      raise newException(IOError, "recovery manifest encryption mode mismatch")
    if manifest.hasKey("items") and manifest["items"].getInt() != stats.items:
      raise newException(IOError, "recovery manifest item count mismatch")
  echo &"recovery-verify OK mirror={mirror} encrypted={encrypted} bytes={stats.bytes} items={stats.items} rings={stats.ringMeta} names={stats.ringNames}"

proc runDump(dataDir, outPath: string, includeVectors: bool) =
  if dataDir.len == 0:
    raise newException(ValueError, "dump requires --data=DIR")
  var db = open(dataDir = dataDir)
  let stats = db.dump(path = outPath, includeVectors = includeVectors)
  db.close()
  if outPath.len > 0 and outPath != "-":
    echo &"dump OK bytes={stats.bytes} records={stats.records} rings={stats.rings} documents={stats.documents} to={stats.destination}"

proc runImportJsonl(dataDir, inPath, defaultRing, ringField, ringPrefix,
                    payloadField, vecField: string, maxRecords: int) =
  if dataDir.len == 0 or inPath.len == 0:
    raise newException(ValueError, "import-jsonl requires --data=DIR --in=FILE")
  var db = open(dataDir = dataDir)
  let stats = db.importJsonl(inPath, defaultRing = defaultRing,
                             ringField = ringField, ringPrefix = ringPrefix,
                             payloadField = payloadField, vecField = vecField,
                             maxRecords = maxRecords)
  db.close()
  echo &"import-jsonl OK read={stats.read} imported={stats.imported} skipped={stats.skipped} errors={stats.errors} rings={stats.rings} source={stats.source}"

when isMainModule:
  var cmd = ""
  var peers = ""
  var dataDir = ""
  var backupDir = ""
  var mirrors: seq[string] = @[]
  var outPath = ""
  var inPath = ""
  var defaultRing = "imported"
  var ringName = ""
  var description = ""
  var ringField = ""
  var ringPrefix = ""
  var payloadField = ""
  var vecField = ""
  var overwrite = false
  var includeVectors = true
  var username = ""
  var password = ""
  var authToken = ""
  var secretKey = ""
  var backupPassphrase = ""
  var galaxy = ""
  var redisEndpoint = "127.0.0.1:6379"
  var n = 10_000
  var queries = 50
  var budget = 20
  var routedBudget = 3
  var ringCount = 100
  var payloadBytes = 100
  for kind, key, val in getopt():
    case kind
    of cmdArgument: cmd = key
    of cmdLongOption:
      case key
      of "peers": peers = val
      of "data": dataDir = val
      of "backup": backupDir = val
      of "mirror": mirrors.add val
      of "out": outPath = val
      of "in": inPath = val
      of "default-ring": defaultRing = val
      of "ring": ringName = val
      of "description": description = val
      of "ring-field": ringField = val
      of "ring-prefix": ringPrefix = val
      of "payload-field": payloadField = val
      of "vec-field": vecField = val
      of "overwrite": overwrite = true
      of "no-vectors": includeVectors = false
      of "user": username = val
      of "password": password = val
      of "auth-token": authToken = val
      of "secret-key": secretKey = val
      of "passphrase": backupPassphrase = val
      of "galaxy": galaxy = val
      of "redis": redisEndpoint = val
      of "n": n = parseInt(val)
      of "queries": queries = parseInt(val)
      of "budget": budget = parseInt(val)
      of "routed-budget": routedBudget = parseInt(val)
      of "rings": ringCount = parseInt(val)
      of "payload-bytes": payloadBytes = parseInt(val)
      else: discard
    else: discard
  case cmd
  of "demo": runDemo(peers, username, password, authToken, secretKey, galaxy)
  of "bench": runBench(peers, username, password, authToken, secretKey, galaxy, n)
  of "health": runHealth(peers, username, password, authToken, secretKey, galaxy)
  of "metrics": runMetrics(peers, username, password, authToken, secretKey, galaxy)
  of "shutdown": runShutdown(peers, username, password, authToken, secretKey, galaxy)
  of "rings": runRings(peers, username, password, authToken, secretKey, galaxy)
  of "atlas": runAtlas(dataDir, peers, username, password, authToken, secretKey,
                       galaxy)
  of "describe-galaxy": runDescribeGalaxy(dataDir, description)
  of "describe-ring": runDescribeRing(dataDir, ringName, description)
  of "retrieve-bench": runRetrieveBench(peers, username, password, authToken, secretKey, galaxy, n)
  of "redis-bench": runRedisBench(n, payloadBytes, redisEndpoint, peers,
                                  username, password, authToken, secretKey,
                                  galaxy)
  of "rag-bench": runRagBench(n, queries, budget, routedBudget)
  of "working-set-bench": runWorkingSetBench(n, ringCount, queries, budget)
  of "memory-pressure-bench": runMemoryPressureBench(n, ringCount, queries,
                                                     budget, payloadBytes)
  of "doctor": runDoctor()
  of "compact": runCompact(dataDir)
  of "backup": runBackup(dataDir, backupDir)
  of "restore": runRestore(backupDir, dataDir, overwrite)
  of "backup-encrypted": runBackupEncrypted(dataDir, backupDir, backupPassphrase)
  of "restore-encrypted": runRestoreEncrypted(backupDir, dataDir,
                                              backupPassphrase, overwrite)
  of "recovery-backup": runRecoveryBackup(dataDir, mirrors, backupPassphrase)
  of "recovery-verify":
    let mirror = if mirrors.len > 0: mirrors[0] else: backupDir
    runRecoveryVerify(mirror, backupPassphrase)
  of "dump": runDump(dataDir, outPath, includeVectors)
  of "import-jsonl": runImportJsonl(dataDir, inPath, defaultRing, ringField,
                                    ringPrefix, payloadField, vecField, n)
  else:
    echo "usage: rochecli [demo|bench|retrieve-bench|redis-bench|rag-bench|working-set-bench|memory-pressure-bench|health|metrics|rings|atlas|shutdown|doctor] --peers=host:port,... [--user=U --password=P --secret-key=K] [--galaxy=G] [--n=N]"
    echo "       rochecli compact --data=DIR"
    echo "       rochecli backup --data=DIR --backup=DIR"
    echo "       rochecli restore --backup=DIR --data=DIR [--overwrite]"
    echo "       rochecli backup-encrypted --data=DIR --backup=DIR --passphrase=TEXT"
    echo "       rochecli restore-encrypted --backup=DIR --data=DIR --passphrase=TEXT [--overwrite]"
    echo "       rochecli recovery-backup --data=DIR --mirror=DIR [--mirror=DIR...] [--passphrase=TEXT]"
    echo "       rochecli recovery-verify --mirror=DIR [--passphrase=TEXT]"
    echo "       rochecli dump --data=DIR [--out=FILE] [--no-vectors]"
    echo "       rochecli import-jsonl --data=DIR --in=FILE [--ring-field=FIELD] [--default-ring=RING] [--payload-field=FIELD] [--vec-field=FIELD] [--ring-prefix=PREFIX]"
    echo "       rochecli describe-galaxy --data=DIR --description=TEXT"
    echo "       rochecli describe-ring --data=DIR --ring=RING --description=TEXT"
    quit(1)
