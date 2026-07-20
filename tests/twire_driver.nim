## Driver-facing wire protocol smoke test.
##
## Starts a small local koutend cluster and verifies that drivers can use
## ring names without knowing ringKey/period/head derivation rules.

import std/[net, os, osproc, strutils, unittest]
import ../src/kouten/[core, wire]

proc startNode(id: int, peers: string): Process =
  let exe = getCurrentDir() / "src" / "koutend"
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
    let peers = getEnv("KOUTEN_TEST_PEERS", "127.0.0.1:17631,127.0.0.1:17632")
    let ps = parsePeers(peers)
    check ps.len == 2

    var procs: seq[Process] = @[]
    for i in 0 ..< ps.len:
      procs.add startNode(i, peers)

    var c = newClusterClient(ps)
    try:
      check c.waitCluster(ps.len)
      check c.codecsReq(0) == @[pcRaw, pcJson, pcNif, pcBif]

      let first = c.putRingReq(0, "japan/tokyo",
                               """{"title":"Tokyo","country":"JP"}""",
                               @[1.0'f32, 0.0'f32], pcJson)
      let tbl = ArcTable(epoch: first.epoch, nNodes: uint16(ps.len))
      let owner = int(tbl.owner(first.head))
      let nonOwner = (owner + 1) mod ps.len

      let id = c.putRingReq(nonOwner, "japan/tokyo",
                            """{"title":"Shinjuku","country":"JP"}""",
                            @[0.95'f32, 0.05'f32], pcJson)
      check int(tbl.owner(id.head)) == owner

      let got = c.getIdReq(nonOwner, id)
      check got.found
      check got.value == """{"title":"Shinjuku","country":"JP"}"""
      check got.codec == pcJson

      var legacy = newSocket()
      legacy.connect(ps[owner].host, Port(ps[owner].port))
      legacy.sendFrame("GETID " & $id.parent & " " & $id.epoch & " " &
                       $id.seq & " " & $id.tWrite & " " & $id.period & " " &
                       $id.head)
      let legacyHeader = legacy.readHeader()
      check legacyHeader.len == 3
      check legacyHeader[0] == "VAL"
      discard legacy.readExact(parseInt(legacyHeader[2]))
      legacy.close()

      let projected = c.queryIdReq(nonOwner, id, "{ title }")
      check projected.found
      check projected.value == """{"title":"Shinjuku"}"""
      check projected.codec == pcJson

      # Repeated projections exercise the server's bounded compiled-selection cache.
      let projectedAgain = c.queryIdReq(owner, id, "{ title }")
      check projectedAgain.value == projected.value

      let bif = c.putRingReq(0, "japan/tokyo", "\x01\x00\x00\x00", @[], pcBif)
      let bifGot = c.getIdReq(0, bif)
      check bifGot.found
      check bifGot.codec == pcBif
      expect ValueError:
        discard c.queryIdReq(0, bif, "{ title }")
    finally:
      c.close()
      for p in procs:
        try:
          p.terminate()
          discard p.waitForExit(timeout = 2_000)
        except CatchableError:
          discard
        p.close()
