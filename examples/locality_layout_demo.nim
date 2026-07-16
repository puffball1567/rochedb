## Physical locality demo for RocheDB's WAL layout.

import std/[json, os, strformat, strutils, tempfiles, times]
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

proc ringName(r: int): string =
  "locality/ring-" & $r

proc pickRing(i, rings: int): int =
  ## Deterministic pseudo-random ring selection for reproducible demos.
  let x = (int64(i) * 1103515245'i64 + 12345'i64) and 0x7fffffff'i64
  int(x mod int64(rings))

proc measureReadUs(db: RocheDb, ring: string, iters: int): float =
  if iters <= 0:
    return 0.0
  let start = cpuTime()
  var consumed = 0
  for _ in 0 ..< iters:
    let page = db.readRing(ring, RocheReadOptions(
      filter: newJObject(),
      limit: 100,
      sortField: "id",
      sortDirection: rsAsc))
    consumed += page.count
  let elapsed = cpuTime() - start
  if consumed < 0:
    echo "" # keep the loop observable to the optimizer
  elapsed * 1_000_000.0 / float(iters)

when isMainModule:
  let rings = max(1, argInt("rings", 8))
  let perRing = max(1, argInt("per-ring", 200))
  let backfill = max(0, argInt("backfill", 64))
  let readIters = max(0, argInt("read-iters", 100))
  let workload = argValue("workload", "interleaved")
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
    var ids: seq[seq[RocheId]] = newSeq[seq[RocheId]](rings)
    let total = rings * perRing

    case workload
    of "random":
      for i in 0 ..< total:
        let r = pickRing(i, rings)
        ids[r].add db.put(%*{
          "phase": "random",
          "ring": r,
          "i": i,
          "body": "record-" & $r & "-" & $i
        }, ring = ringName(r))
    of "hot-cold":
      for i in 0 ..< total:
        let r = if i mod 10 < 7: 0 else: 1 + (i mod max(1, rings - 1))
        let rr = r mod rings
        ids[rr].add db.put(%*{
          "phase": "hot-cold",
          "ring": rr,
          "i": i,
          "body": "record-" & $rr & "-" & $i
        }, ring = ringName(rr))
    else:
      for i in 0 ..< perRing:
        for r in 0 ..< rings:
          ids[r].add db.put(%*{
            "phase": workload,
            "ring": r,
            "i": i,
            "body": "record-" & $r & "-" & $i
          }, ring = ringName(r))

    if workload == "delete-heavy":
      for r in 0 ..< rings:
        for i, id in ids[r]:
          if i mod 3 == 0:
            db.deleteById(id)

    let backfillCount =
      if workload == "backfill-heavy": max(backfill, perRing * rings div 2)
      else: backfill
    for i in 0 ..< backfillCount:
      let r = (i * 7 + 3) mod rings
      discard db.put(%*{
        "phase": "backfill",
        "ring": r,
        "i": i
      }, ring = ringName(r))

    let readRing = ringName(0)
    let beforeReadUs = measureReadUs(db, readRing, readIters)
    printReport("before_compact", db.localityReport())
    echo &"read_before ring={readRing} iters={readIters} usPerRead={beforeReadUs:.3f}"
    let stats = db.compact()
    echo &"compact beforeBytes={stats.beforeBytes} afterBytes={stats.afterBytes} items={stats.items}"
    let afterReadUs = measureReadUs(db, readRing, readIters)
    printReport("after_compact", db.localityReport())
    echo &"read_after ring={readRing} iters={readIters} usPerRead={afterReadUs:.3f}"
  finally:
    db.close()
    if cleanup:
      removeDir(dataDir)
