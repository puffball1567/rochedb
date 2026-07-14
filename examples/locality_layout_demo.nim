## Physical locality demo for RocheDB's WAL layout.

import std/[json, os, strformat, strutils, tempfiles]
import ../src/rochedb

proc argValue(name, defaultValue: string): string =
  let prefix = "--" & name & "="
  for arg in commandLineParams():
    if arg.startsWith(prefix):
      return arg[prefix.len .. ^1]
  defaultValue

proc argInt(name: string, defaultValue: int): int =
  parseInt(argValue(name, $defaultValue))

proc printReport(label: string, r: LocalityReport) =
  echo &"{label} persistent={r.persistent} walBytes={r.walBytes} totalParticleRecords={r.totalParticleRecords} liveParticleRecords={r.liveParticleRecords} deadParticleRecords={r.deadParticleRecords} ringCount={r.ringCount} ringRuns={r.ringRuns} fragmentedRings={r.fragmentedRings} avgRunRecords={r.avgRunRecords:.3f} maxRunRecords={r.maxRunRecords} localityScore={r.localityScore:.6f}"

when isMainModule:
  let rings = max(1, argInt("rings", 8))
  let perRing = max(1, argInt("per-ring", 200))
  let backfill = max(0, argInt("backfill", 64))
  let explicitDataDir = argValue("data", "")
  let dataDir =
    if explicitDataDir.len > 0: explicitDataDir
    else: createTempDir("rochedb", "locality-layout-demo")
  let cleanup = explicitDataDir.len == 0

  if dirExists(dataDir):
    removeDir(dataDir)
  createDir(dataDir)

  var db = open(dataDir = dataDir)
  try:
    for i in 0 ..< perRing:
      for r in 0 ..< rings:
        discard db.put(%*{
          "phase": "interleaved",
          "ring": r,
          "i": i,
          "body": "record-" & $r & "-" & $i
        }, ring = "locality/ring-" & $r)

    for i in 0 ..< backfill:
      let r = (i * 7 + 3) mod rings
      discard db.put(%*{
        "phase": "backfill",
        "ring": r,
        "i": i
      }, ring = "locality/ring-" & $r)

    printReport("before_compact", db.localityReport())
    let stats = db.compact()
    echo &"compact beforeBytes={stats.beforeBytes} afterBytes={stats.afterBytes} items={stats.items}"
    printReport("after_compact", db.localityReport())
  finally:
    db.close()
    if cleanup:
      removeDir(dataDir)
