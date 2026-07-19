## Cluster payload codec and legacy wire-header compatibility demo.

import std/[net, os, sequtils, strutils]
import ../src/orbelias/core
import ../src/orbelias/[wire]

proc requireArg(name: string): string =
  let prefix = "--" & name & "="
  for arg in commandLineParams():
    if arg.startsWith(prefix):
      return arg[prefix.len .. ^1]
  raise newException(ValueError, "missing " & prefix & "...")

when isMainModule:
  let peers = parsePeers(requireArg("peers"))
  var client = newClusterClient(peers)
  try:
    echo "node codecs: ", client.codecsReq(0).mapIt(it.payloadCodecName).join(", ")
    let id = client.putRingReq(0, "demo/codec", "\x01\x00\x00\x00", @[], pcBif)
    let stored = client.getIdReq(0, id)
    echo "negotiated get: codec=", stored.codec.payloadCodecName,
         " bytes=", stored.value.len

    # No CODECMETA negotiation: this models released legacy wire drivers.
    let owner = int(ArcTable(epoch: id.epoch, nNodes: uint16(peers.len)).owner(id.head))
    var legacy = newSocket()
    legacy.connect(peers[owner].host, Port(peers[owner].port))
    legacy.sendFrame("GETID " & $id.parent & " " & $id.epoch & " " &
                     $id.seq & " " & $id.tWrite & " " & $id.period & " " &
                     $id.head)
    let header = legacy.readHeader()
    discard legacy.readExact(parseInt(header[2]))
    legacy.close()
    echo "legacy get header fields: ", header.len, " (VAL node length)"
  finally:
    client.close()
