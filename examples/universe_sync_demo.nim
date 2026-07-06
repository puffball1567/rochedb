import std/[json, os, strutils]
import ../src/rochedb

proc requireArg(name: string): string =
  let prefix = "--" & name & "="
  for arg in commandLineParams():
    if arg.startsWith(prefix):
      return arg[prefix.len .. ^1]
  raise newException(ValueError, "missing " & prefix & "...")

proc argValue(name, defaultValue: string): string =
  let prefix = "--" & name & "="
  for arg in commandLineParams():
    if arg.startsWith(prefix):
      return arg[prefix.len .. ^1]
  defaultValue

proc enqueueSample(sourceDir: string) =
  var source = open(dataDir = sourceDir)
  try:
    discard source.enqueueUniverseSyncEvent(
      sourceUniverse = "tokyo",
      sourceGalaxy = "social",
      ring = "posts/u1",
      payload = $(%*{
        "postId": "p-001",
        "author": "u1",
        "body": "hello from tokyo",
        "createdAt": "2026-07-07T00:00:00Z"
      }),
      logicalKey = "post:p-001")
  finally:
    source.close()

proc printPending(sourceDir, label: string) =
  var db = open(dataDir = sourceDir)
  try:
    echo label, ": ", db.universeSyncEvents().len
  finally:
    db.close()

proc syncAndPrint(sourceDir, targetDir: string) =
  var syncSource = open(dataDir = sourceDir)
  var syncTarget = open(dataDir = targetDir)
  try:
    let stats = syncUniverseOnce(syncSource, syncTarget, pruneAcked = true)
    echo "sync read=", stats.read,
         " applied=", stats.applied,
         " skipped=", stats.skipped,
         " acked=", stats.acked,
         " pruned=", stats.pruned,
         " errors=", stats.errors
  finally:
    syncTarget.close()
    syncSource.close()

  var target = open(dataDir = targetDir)
  try:
    let page = target.listByRing("posts/u1", limit = 10)
    echo "target posts/u1 count: ", page.items.len
    for item in page.items:
      echo item.payload
  finally:
    target.close()

when isMainModule:
  let sourceDir = requireArg("source")
  let targetDir = requireArg("target")
  let mode = argValue("mode", "full")

  case mode
  of "enqueue":
    enqueueSample(sourceDir)
    printPending(sourceDir, "source pending after enqueue")
  of "sync":
    printPending(sourceDir, "source pending before sync")
    syncAndPrint(sourceDir, targetDir)
    printPending(sourceDir, "source pending after sync")
  of "full":
    enqueueSample(sourceDir)
    printPending(sourceDir, "source pending before sync")
    syncAndPrint(sourceDir, targetDir)
    printPending(sourceDir, "source pending after sync")
  else:
    raise newException(ValueError, "unknown --mode=" & mode)
