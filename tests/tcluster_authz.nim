## 手動結合テスト: roched 3ノード起動後に実行する。

import std/[net, os, unittest]
import ../src/roche/wire

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

suite "cluster authz":
  test "allow-ring prefix permits matching named rings and denies others":
    let peers = getEnv("ROCHE_TEST_PEERS",
      "127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613")
    let ps = parsePeers(peers)
    var c = newClusterClient(ps, username = "alice", password = "secret")
    let id = c.putRingReq(0, "allowed/docs", "ok", @[])
    let got = c.getIdReq(0, id)
    check got.found
    check got.value == "ok"

    expect AssertionDefect:
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

  test "authz denial drains each framed body type and keeps the connection usable":
    let peers = getEnv("ROCHE_TEST_PEERS",
      "127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613")
    let ps = parsePeers(peers)
    var c = newClusterClient(ps, username = "alice", password = "secret")

    expect AssertionDefect:
      discard c.putRingReq(0, "blocked/docs", "putr-body",
                           @[1.0'f32, 2.0'f32, 3.0'f32])
    c.checkAlive(0, "putr")

    expect AssertionDefect:
      discard c.putReq(0, BlockedRing, Period, Head, "put-body",
                       @[1.0'f32, 2.0'f32])
    c.checkAlive(0, "put")

    expect AssertionDefect:
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

    expect AssertionDefect:
      discard c.listRingReq(0, BlockedRing, 10, "123456789")
    c.checkAlive(0, "list")

    expect AssertionDefect:
      c.transferReq(0, BlockedRing, 0'u32, Period, Head, 1.0, "trf-body",
                    @[1.0'f32, 2.0'f32], timeoutMs = 1000)
    c.checkAlive(0, "transfer")

    expect AssertionDefect:
      c.applyTxReq(0, 90'u64,
        TxWireOp(parent: BlockedRing, seq: 0'u32, period: Period,
                 head: Head, tWrite: 1.0, payload: "apply-body",
                 vec: @[1.0'f32, 2.0'f32]),
        timeoutMs = 1000)
    c.checkAlive(0, "applytx")

    let txid = c.txBeginReq(0)
    expect AssertionDefect:
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
    let peers = getEnv("ROCHE_TEST_PEERS",
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
