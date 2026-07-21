## KoutenDB heterogeneous subring bundle benchmark.
##
## This models a common API shape: one root entity with several related
## collections, where each collection has its own limit and sort order.

import std/[json, monotimes, os, parseopt, strformat, strutils, tables, times]
import ../src/koutendb

const
  AddressCount = 8
  CareerCount = 5
  OrderCount = 50
  NotificationCount = 40

proc elapsedUs(start: MonoTime): float =
  float((getMonoTime() - start).inNanoseconds) / 1e3

proc userId(i: int): string =
  &"user-{i:08d}"

proc putBundle(db: KoutenDb; id: string; i: int) =
  discard db.put(%*{
    "kind": "profile",
    "userId": id,
    "name": "Bundle User " & $i,
    "tier": if i mod 17 == 0: "enterprise" else: "standard"
  }, ring = "users/" & id & "/profile")
  for n in 0 ..< AddressCount:
    discard db.put(%*{
      "kind": "address",
      "userId": id,
      "n": n,
      "country": if n mod 2 == 0: "JP" else: "US",
      "line": &"{n} Orbit Avenue"
    }, ring = "users/" & id & "/addresses")
  for n in 0 ..< CareerCount:
    discard db.put(%*{
      "kind": "career",
      "userId": id,
      "n": n,
      "company": &"Company {n}",
      "role": if n == 0: "Engineer" else: "Advisor"
    }, ring = "users/" & id & "/career")
  discard db.put(%*{
    "kind": "preferences",
    "userId": id,
    "locale": if i mod 3 == 0: "ja-JP" elif i mod 3 == 1: "en-US" else: "fr-FR",
    "newsletter": i mod 2 == 0
  }, ring = "users/" & id & "/preferences")
  for n in 0 ..< OrderCount:
    discard db.put(%*{
      "kind": "order",
      "userId": id,
      "n": n,
      "sku": &"SKU-{i mod 1000:04d}-{n:02d}",
      "amount": 1000 + ((i + n) mod 20000)
    }, ring = "users/" & id & "/orders")
  for n in 0 ..< NotificationCount:
    discard db.put(%*{
      "kind": "notification",
      "userId": id,
      "n": n,
      "unread": n mod 3 == 0,
      "title": &"Notification {n}"
    }, ring = "users/" & id & "/notifications")

proc populate(dataDir: string; users: int; diskBacked: bool):
              tuple[setUs: float, packUs: float, packRecords: int] =
  if dirExists(dataDir):
    removeDir(dataDir)
  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()
  let start = getMonoTime()
  for i in 0 ..< users:
    db.putBundle(userId(i), i)
  result.setUs = elapsedUs(start)
  if diskBacked:
    let packStart = getMonoTime()
    let stats = db.packDiskBackedSegments()
    result.packUs = elapsedUs(packStart)
    result.packRecords = stats.records

proc readBundle(db: KoutenDb; target: string): tuple[us: float, count: int, rings: int] =
  var limits = initTable[string, int]()
  limits["profile"] = 1
  limits["addresses"] = 3
  limits["career"] = 2
  limits["preferences"] = 1
  limits["orders"] = 10
  limits["notifications"] = 5
  var sortFields = initTable[string, string]()
  sortFields["orders"] = "time"
  sortFields["notifications"] = "time"
  var sortDirections = initTable[string, KoutenReadSortDirection]()
  sortDirections["orders"] = rsDesc
  sortDirections["notifications"] = rsDesc

  let start = getMonoTime()
  let page = db.readStellar("users/" & target, KoutenStellarOptions(
    filter: newJObject(),
    selection: "{ kind userId name tier country line company role locale newsletter sku amount title unread n }",
    limitPerRing: 20,
    subringLimits: limits,
    subringSortFields: sortFields,
    subringSortDirections: sortDirections,
    maxDepth: 1,
    branchBudget: 0,
    subrings: @["profile", "addresses", "career", "preferences", "orders", "notifications"],
    includeRoot: false,
    sortField: "id",
    sortDirection: rsAsc))
  result.us = elapsedUs(start)
  result.count = page.count
  result.rings = page.rings.len

proc main() =
  var dataDir = ""
  var users = 10_000
  var targetIndex = -1
  var diskBacked = true
  var metrics = false
  var reads = 1

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "data": dataDir = val
      of "users": users = parseInt(val)
      of "target-index": targetIndex = parseInt(val)
      of "reads": reads = parseInt(val)
      of "disk-backed": diskBacked = true
      of "memory": diskBacked = false
      of "metrics": metrics = true
      else: discard
    of cmdArgument, cmdShortOption, cmdEnd:
      discard

  if dataDir.len == 0:
    raise newException(ValueError,
      "usage: subring_bundle_bench --data=DIR [--users=N] [--reads=N] [--target-index=N] [--disk-backed|--memory]")
  if users <= 0:
    raise newException(ValueError, "users must be > 0")
  if reads <= 0:
    raise newException(ValueError, "reads must be > 0")
  if targetIndex < 0:
    targetIndex = users div 2
  if targetIndex >= users:
    raise newException(ValueError, "target-index must be < users")

  createDir(dataDir)
  let target = userId(targetIndex)
  let setup = populate(dataDir, users, diskBacked)

  var totalReadUs = 0.0
  var lastCount = 0
  var lastRings = 0
  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()
  for _ in 0 ..< reads:
    let r = db.readBundle(target)
    totalReadUs += r.us
    lastCount = r.count
    lastRings = r.rings

  let records = users * (1 + AddressCount + CareerCount + 1 + OrderCount + NotificationCount)
  let avgReadUs = totalReadUs / float(reads)

  if metrics:
    echo &"subringBundleUsers {users}"
    echo &"subringBundleLogicalRecords {records}"
    echo &"subringBundleTarget {target}"
    echo &"subringBundleDiskBacked {int(diskBacked)}"
    echo &"subringBundleReads {reads}"
    echo &"subringBundleSetLatencyUs {setup.setUs:.3f}"
    echo &"subringBundleSetUsPerRecord {setup.setUs / float(records):.6f}"
    echo &"subringBundlePackLatencyUs {setup.packUs:.3f}"
    echo &"subringBundlePackRecords {setup.packRecords}"
    echo &"subringBundleReadLatencyUs {avgReadUs:.3f}"
    echo &"subringBundleReadCount {lastCount}"
    echo &"subringBundleReadRings {lastRings}"
    return

  echo "== KoutenDB heterogeneous subring bundle benchmark =="
  echo &"users={users} logical_records={records} target={target} disk_backed={diskBacked} reads={reads}"
  echo &"set latency_us={setup.setUs:.3f} us_per_record={setup.setUs / float(records):.6f}"
  echo &"pack latency_us={setup.packUs:.3f} records={setup.packRecords}"
  echo &"bundle read latency_us={avgReadUs:.3f} count={lastCount} rings={lastRings}"

when isMainModule:
  main()
