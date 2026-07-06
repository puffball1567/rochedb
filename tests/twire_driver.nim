## Driver-facing wire protocol smoke test.
##
## Starts a small local roched cluster and verifies that drivers can use
## ring names without knowing ringKey/period/head derivation rules.

import std/[os, osproc, unittest]
import ../src/roche/[core, wire]

proc startNode(id: int, peers: string): Process =
  let exe = getCurrentDir() / "src" / "roched"
  startProcess(exe, args = ["--id=" & $id, "--peers=" & peers,
                            "--slow-tick=1000"],
               options = {poParentStreams})

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

suite "driver wire protocol":
  test "PUTR/GETID/QRYID hide ring internals from external drivers":
    let peers = getEnv("ROCHE_TEST_PEERS", "127.0.0.1:17631,127.0.0.1:17632")
    let ps = parsePeers(peers)
    check ps.len == 2

    var procs: seq[Process] = @[]
    for i in 0 ..< ps.len:
      procs.add startNode(i, peers)

    var c = newClusterClient(ps)
    try:
      check c.waitCluster(ps.len)

      let first = c.putRingReq(0, "japan/tokyo",
                               """{"title":"Tokyo","country":"JP"}""",
                               @[1.0'f32, 0.0'f32])
      let tbl = ArcTable(epoch: first.epoch, nNodes: uint16(ps.len))
      let owner = int(tbl.owner(first.head))
      let nonOwner = (owner + 1) mod ps.len

      let id = c.putRingReq(nonOwner, "japan/tokyo",
                            """{"title":"Shinjuku","country":"JP"}""",
                            @[0.95'f32, 0.05'f32])
      check int(tbl.owner(id.head)) == owner

      let got = c.getIdReq(nonOwner, id)
      check got.found
      check got.value == """{"title":"Shinjuku","country":"JP"}"""

      let projected = c.queryIdReq(nonOwner, id, "{ title }")
      check projected.found
      check projected.value == """{"title":"Shinjuku"}"""
    finally:
      c.close()
      for p in procs:
        try:
          p.terminate()
          discard p.waitForExit(timeout = 2_000)
        except CatchableError:
          discard
        p.close()
