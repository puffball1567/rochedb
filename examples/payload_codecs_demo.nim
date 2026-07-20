## Embedded payload codec and prepared selection demo.

import std/[json, os, strutils]
import ../src/koutendb

proc argValue(name, defaultValue: string): string =
  let prefix = "--" & name & "="
  for arg in commandLineParams():
    if arg.startsWith(prefix):
      return arg[prefix.len .. ^1]
  defaultValue

when isMainModule:
  let dataDir = argValue("data", "")
  var db = open(dataDir = dataDir)
  try:
    let jsonId = db.put(%*{
      "title": "KoutenDB",
      "kind": "document",
      "author": {"name": "Ada", "team": "storage"}
    }, ring = "docs/codec")
    let nifBytes = "(object (title KoutenDB) (kind artifact))"
    let nifId = db.put(encodedPayload(nifBytes, pcNif), ring = "artifacts/nif")
    let bifBytes = "\x01\x00\x00\x00\x7f"
    let bifId = db.put(encodedPayload(bifBytes, pcBif), ring = "artifacts/bif")

    let fields = prepareSelection("{ title author { name } }")
    echo "JSON projection: ", $db.query(jsonId, fields)
    for id in [jsonId, nifId, bifId]:
      let value = db.getEncoded(id)
      echo "stored codec=", value.codec.payloadCodecName,
           " bytes=", value.data.len

    try:
      discard db.query(nifId, fields)
    except ValueError as err:
      echo "NIF projection rejected: ", err.msg
  finally:
    db.close()

  if dataDir.len > 0:
    var reopened = open(dataDir = dataDir)
    try:
      let page = reopened.listByRing("artifacts/bif", limit = 1)
      echo "reopen codec=", page.items[0].codec.payloadCodecName,
           " bytes=", page.items[0].payload.len
    finally:
      reopened.close()
