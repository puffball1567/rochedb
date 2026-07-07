## Cluster failure smoke:
## - start 3 local roched nodes
## - create a cluster tx whose owner is not node0
## - kill the owner before commit
## - verify node0 keeps the committed intent pending
## - restart the owner and verify retry applies the value

import std/[json, os, osproc, strutils, unittest]
import ../src/rochedb
import ../src/roche/wire

type NodeProc = object
  id: int
  procHandle: Process

proc startNode(id: int, peers, dataRoot: string, slowTick = "0.05"): NodeProc =
  let exe = getCurrentDir() / "src" / "roched"
  let p = startProcess(exe,
                       args = ["--id=" & $id, "--peers=" & peers,
                               "--data=" & (dataRoot / ("node" & $id)),
                               "--slow-tick=" & slowTick],
                       options = {poParentStreams})
  NodeProc(id: id, procHandle: p)

proc stopNode(n: var NodeProc, crash = false) =
  if n.procHandle.isNil:
    return
  try:
    if crash:
      n.procHandle.kill()
    else:
      n.procHandle.terminate()
    discard n.procHandle.waitForExit(timeout = 2_000)
  except CatchableError:
    discard
  n.procHandle.close()

proc waitNode(c: ClusterClient, node: int): bool =
  for _ in 0 ..< 50:
    try:
      discard c.healthReq(node)
      return true
    except CatchableError:
      sleep(100)
  false

proc waitCluster(c: ClusterClient, n: int): bool =
  for _ in 0 ..< 50:
    var ok = true
    for node in 0 ..< n:
      try:
        discard c.healthReq(node)
      except CatchableError:
        ok = false
    if ok:
      return true
    sleep(100)
  false

proc metricValue(metrics, name: string): int =
  let parts = metrics.splitWhitespace()
  for i in 0 ..< parts.len - 1:
    if parts[i] == name:
      return parseInt(parts[i + 1])
  raise newException(ValueError, "metric not found: " & name & " in " & metrics)

proc waitNode0Metric(c: ClusterClient, name: string, value: int): bool =
  for _ in 0 ..< 60:
    try:
      if metricValue(c.metricsReq(0), name) == value:
        return true
    except CatchableError:
      discard
    sleep(100)
  false

suite "cluster transaction failure recovery":
  test "committed landing intent retries after owner node crash and restart":
    let basePort = parseInt(getEnv("ROCHE_CLUSTER_FAILURE_BASE_PORT", "17511"))
    let peers = "127.0.0.1:" & $basePort & ",127.0.0.1:" & $(basePort + 1) &
                ",127.0.0.1:" & $(basePort + 2)
    let dataRoot = getTempDir() / ("rochedb-cluster-failure-" & $getCurrentProcessId())
    createDir(dataRoot)

    var nodes: seq[NodeProc] = @[]
    var c = newClusterClient(parsePeers(peers))
    var db: RocheDb = nil
    try:
      for id in 0 ..< 3:
        nodes.add startNode(id, peers, dataRoot)
      check c.waitCluster(3)

      db = connect(peers)

      var tx: RocheTx = nil
      var id: RocheId
      var owner = 0
      for i in 0 ..< 32:
        let ring = "cluster/failure/" & $i
        db.configureRing(ring, 3600.0)
        tx = db.beginTransaction()
        id = tx.put($(%*{"value": "retry-value-" & $i}),
                    ring = ring,
                    vec = @[1.0'f32, float32(i) / 32.0'f32])
        owner = db.locate(id)
        if owner != 0:
          break
        tx.rollback()
        tx = nil
      check owner in 1 .. 2
      check tx != nil

      nodes[owner].stopNode(crash = true)
      check not c.waitNode(owner)

      tx.commit()
      check c.waitNode0Metric("clusterTxPending", 1)
      check db.get(id).contains("retry-value-")
      check db.query(id, "{ value }")["value"].getStr().startsWith("retry-value-")

      nodes[owner] = startNode(owner, peers, dataRoot)
      check c.waitNode(owner)

      var ok = false
      for _ in 0 ..< 80:
        try:
          if db.get(id).contains("retry-value-"):
            ok = true
            break
        except KeyError, IOError, OSError:
          discard
        sleep(100)
      check ok
      check c.waitNode0Metric("clusterTxPending", 0)
      check metricValue(c.metricsReq(0), "clusterTxApplied") >= 1
    finally:
      if not db.isNil:
        db.close()
      c.close()
      for i in 0 ..< nodes.len:
        nodes[i].stopNode()
      removeDir(dataRoot)
