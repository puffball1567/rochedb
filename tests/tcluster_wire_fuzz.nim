## Deterministic wire-protocol robustness smoke.
##
## This is not coverage-guided fuzzing. It is a regression matrix for malformed
## frames that previously could block or escape the connection boundary.

import std/[net, os, strutils, unittest]
import ../src/roche/wire

type FuzzCase = object
  name: string
  header: string
  payload: string
  closeAfterSend: bool

proc authSocket(peer: Peer): Socket =
  result = newSocket()
  result.connect(peer.host, Port(peer.port))
  result.sendFrame("AUTH alice secret")
  let r = result.readHeader(timeoutMs = 1_000)
  check r[0] == "OK"

proc tryReadResponse(sock: Socket) =
  try:
    discard sock.readHeader(timeoutMs = 500)
  except CatchableError:
    discard

proc checkAlive(peers: seq[Peer], label: string) =
  var c = newClusterClient(peers, username = "alice", password = "secret")
  let h = c.healthReq(0)
  check h.contains("node=0")
  let id = c.putRingReq(0, "allowed/fuzz/" & label, "ok-" & label, @[])
  let got = c.getIdReq(0, id)
  check got.found
  check got.value == "ok-" & label
  c.close()

suite "cluster wire fuzz":
  test "malformed frames close only the offending connection":
    let peers = getEnv("ROCHE_TEST_PEERS",
      "127.0.0.1:17711,127.0.0.1:17712,127.0.0.1:17713")
    let ps = parsePeers(peers)

    let cases = @[
      FuzzCase(name: "short-putr", header: "PUTR"),
      FuzzCase(name: "huge-ring", header: "PUTR 999999999 0 0"),
      FuzzCase(name: "negative-ring", header: "PUTR -1 0 0"),
      FuzzCase(name: "huge-payload", header: "PUTR 7 999999999 0",
               payload: "allowed"),
      FuzzCase(name: "huge-vector", header: "PUTR 7 0 999999999",
               payload: "allowed"),
      FuzzCase(name: "short-put", header: "PUT"),
      FuzzCase(name: "huge-put-payload", header: "PUT 1 60 0 999999999 0"),
      FuzzCase(name: "negative-put-payload", header: "PUT 1 60 0 -1 0"),
      FuzzCase(name: "short-get", header: "GET"),
      FuzzCase(name: "bad-number", header: "GET not-a-number"),
      FuzzCase(name: "huge-header",
               header: "GET " & repeat("9", MaxWireHeaderBytes + 1)),
      FuzzCase(name: "huge-query-selection",
               header: "QRY 1 0 60 0 1 999999999"),
      FuzzCase(name: "huge-bget", header: "BGET 1 999999999"),
      FuzzCase(name: "negative-bget", header: "BGET 1 -1"),
      FuzzCase(name: "huge-retrieve-vector",
               header: "RETRIEVE 1 1 3 999999999"),
      FuzzCase(name: "short-applytx", header: "APPLYTX"),
      FuzzCase(name: "short-trf", header: "TRF"),
      FuzzCase(name: "unknown-command", header: "WHAT_IS_THIS 1 2 3"),
      FuzzCase(name: "truncated-txcommit", header: "TXCOMMIT 1 1",
               closeAfterSend: true)
    ]

    for tc in cases:
      var s = authSocket(ps[0])
      s.send(tc.header & "\n" & tc.payload)
      if not tc.closeAfterSend:
        s.tryReadResponse()
      s.close()
      checkAlive(ps, tc.name)
