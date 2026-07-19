## 手動結合テスト: orbeliasd 3ノード起動後に実行する。

import std/[json, net, os, unittest]
import ../src/orbelias/wire

const
  BlockedRing = 9_999_991'u64
  Period = 60.0
  Head = 0.1

proc checkAlive(c: ClusterClient, node: int, label: string) =
  let id = c.putRingReq(node, "allowed/docs", "alive:" & label,
                        @[0.0'f32, 1.0'f32, 0.0'f32])
  let got = c.getIdReq(node, id)
  check got.found
  check got.value == "alive:" & label

proc authSocket(peers: seq[Peer]): Socket =
  result = newSocket()
  result.connect(peers[0].host, Port(peers[0].port))
  result.setSockOpt(OptNoDelay, true, level = IPPROTO_TCP.cint)
  result.sendFrame("AUTH alice secret")
  let r = result.readHeader()
  check r[0] == "OK"

proc expectProtocolErr(sock: Socket) =
  let r = sock.readHeader()
  check r[0] == "ERR"

proc universeEventJson(ring, key, payload: string): string =
  $(%*{
    "eventKey": key,
    "sourceUniverse": "tokyo",
    "sourceGalaxy": "authz",
    "ring": ring,
    "op": "put",
    "logicalKey": key,
    "payload": payload,
    "vec": [],
    "timestamp": 1.0,
    "originSeq": 1
  })

suite "cluster authz":
  test "allow-ring prefix permits matching named rings and denies others":
    let peers = getEnv("ORBELIAS_TEST_PEERS",
      "127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613")
    let ps = parsePeers(peers)
    var c = newClusterClient(ps, username = "alice", password = "secret")
    let id = c.putRingReq(0, "allowed/docs", "ok", @[])
    let got = c.getIdReq(0, id)
    check got.found
    check got.value == "ok"

    expect IOError:
      discard c.putRingReq(0, "blocked/docs", "no-with-body",
                           @[1.0'f32, 0.0'f32, 0.0'f32])

    # The denied PUTR has a body. The server must drain it and keep the
    # persistent connection usable for the next request.
    let afterDenied = c.putRingReq(0, "allowed/docs", "after-denied",
                                  @[0.0'f32, 1.0'f32, 0.0'f32])
    let gotAfterDenied = c.getIdReq(0, afterDenied)
    check gotAfterDenied.found
    check gotAfterDenied.value == "after-denied"
    c.close()

  test "UAPPLY is idempotent by eventKey":
    let peers = getEnv("ORBELIAS_TEST_PEERS",
      "127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613")
    let ps = parsePeers(peers)
    var c = newClusterClient(ps, username = "alice", password = "secret")
    let event = universeEventJson("allowed/universe", "uapply-idempotent",
                                  "remote-once")
    check c.universeApplyReq(0, event) == "APPLIED"
    check c.universeApplyReq(0, event) == "SKIPPED"
    c.close()

  test "authz denial drains each framed body type and keeps the connection usable":
    let peers = getEnv("ORBELIAS_TEST_PEERS",
      "127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613")
    let ps = parsePeers(peers)
    var c = newClusterClient(ps, username = "alice", password = "secret")

    expect IOError:
      discard c.putRingReq(0, "blocked/docs", "putr-body",
                           @[1.0'f32, 2.0'f32, 3.0'f32])
    c.checkAlive(0, "putr")

    expect IOError:
      discard c.putReq(0, BlockedRing, Period, Head, "put-body",
                       @[1.0'f32, 2.0'f32])
    c.checkAlive(0, "put")

    expect IOError:
      discard c.retrieveReq(0, true, BlockedRing, @[1.0'f32, 0.0'f32], 3)
    c.checkAlive(0, "retrieve")

    expect ValueError:
      discard c.queryReq(0, BlockedRing, 0'u32, Period, Head, 1.0,
                         "{ title author { name } }")
    c.checkAlive(0, "query")

    expect ValueError:
      discard c.txGetIdReq(0, WireId(parent: BlockedRing, epoch: 1'u32,
                                     seq: 0'u32, tWrite: 1.0,
                                     period: Period, head: Head),
                           "{ title }")
    c.checkAlive(0, "tx-query")

    expect IOError:
      discard c.listRingReq(0, BlockedRing, 10, "123456789")
    c.checkAlive(0, "list")

    expect IOError:
      c.transferReq(0, BlockedRing, 0'u32, Period, Head, 1.0, "trf-body",
                    @[1.0'f32, 2.0'f32], timeoutMs = 1000)
    c.checkAlive(0, "transfer")

    expect IOError:
      c.applyTxReq(0, 90'u64,
        TxWireOp(parent: BlockedRing, seq: 0'u32, period: Period,
                 head: Head, tWrite: 1.0, payload: "apply-body",
                 vec: @[1.0'f32, 2.0'f32]),
        timeoutMs = 1000)
    c.checkAlive(0, "applytx")

    expect IOError:
      discard c.universeApplyReq(0,
        universeEventJson("blocked/docs", "blocked-uapply", "uapply-body"))
    c.checkAlive(0, "uapply")

    let txid = c.txBeginReq(0)
    expect IOError:
      c.txCommitReq(0, txid, @[
        TxWireOp(parent: BlockedRing, seq: 0'u32, period: Period,
                 head: Head, tWrite: 1.0, payload: "tx-body",
                 vec: @[1.0'f32, 2.0'f32])
      ])
    c.checkAlive(0, "txcommit")

    let bget = c.batchGetReq(0, @[
      (parent: BlockedRing, seq: 0'u32, period: Period, head: Head,
       tWrite: 1.0)
    ])
    check bget == @[""]
    c.checkAlive(0, "bget")

    c.close()

  test "malformed or oversized denied frames close only that connection":
    let peers = getEnv("ORBELIAS_TEST_PEERS",
      "127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613")
    let ps = parsePeers(peers)

    var s1 = authSocket(ps)
    s1.sendFrame("PUTR 12 999999999 0", "blocked/docs")
    s1.expectProtocolErr()
    s1.close()

    var c = newClusterClient(ps, username = "alice", password = "secret")
    c.checkAlive(0, "after-oversized-putr")
    c.close()

    var s2 = authSocket(ps)
    s2.sendFrame("PUTR 12 -1 0")
    s2.expectProtocolErr()
    s2.close()

    c = newClusterClient(ps, username = "alice", password = "secret")
    c.checkAlive(0, "after-negative-putr")
    c.close()

    var sShort = authSocket(ps)
    sShort.sendFrame("PUTR")
    sShort.expectProtocolErr()
    sShort.close()

    c = newClusterClient(ps, username = "alice", password = "secret")
    c.checkAlive(0, "after-short-putr")
    c.close()

    var s3 = authSocket(ps)
    s3.sendFrame("RETRIEVE 1 " & $BlockedRing & " 1 999999999")
    s3.expectProtocolErr()
    s3.close()

    c = newClusterClient(ps, username = "alice", password = "secret")
    c.checkAlive(0, "after-oversized-retrieve")
    c.close()
