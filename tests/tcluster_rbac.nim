## Manual integration test: start roched with --role users before running.

import std/[os, strutils, unittest]
import ../src/roche/wire

suite "cluster rbac":
  test "reader writer admin roles combine with ring prefixes":
    let peers = getEnv("ROCHE_TEST_PEERS", "127.0.0.1:17811")
    let ps = parsePeers(peers)

    var writer = newClusterClient(ps, username = "writer", password = "write")
    let id = writer.putRingReq(0, "allowed/docs", "writer-value", @[])
    let gotByWriter = writer.getIdReq(0, id)
    check gotByWriter.found
    check gotByWriter.value == "writer-value"

    expect IOError:
      discard writer.putRingReq(0, "blocked/docs", "blocked", @[])
    writer.close()

    var reader = newClusterClient(ps, username = "reader", password = "read")
    let gotByReader = reader.getIdReq(0, id)
    check gotByReader.found
    check gotByReader.value == "writer-value"

    expect IOError:
      discard reader.putRingReq(0, "allowed/docs", "reader-write", @[])
    reader.close()

    writer = newClusterClient(ps, username = "writer", password = "write")
    expect IOError:
      discard writer.metricsReq(0)
    writer.close()

    var admin = newClusterClient(ps, username = "admin", password = "admin")
    let metrics = admin.metricsReq(0)
    check metrics.contains("items")
    check metrics.contains("uptimeSec")
    check metrics.contains("requests")
    check metrics.contains("errors")
    check metrics.contains("authFailures")
    check metrics.contains("authzDenied")
    check metrics.contains("walBytes")
    check metrics.contains("warpJobs")
    check metrics.contains("activeConnections")
    admin.close()
