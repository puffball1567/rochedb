## KoutenDB pinpoint user read benchmark.
##
## Compares two data layouts with the same logical user records:
## - broad layout: all users are stored in one `users` ring and filtered by id
## - local layout: each user is stored in its own `users/<id>` ring
##
## The point is to measure the application pattern where a service already knows
## which user it wants and can make that placement part of the read path.

import std/[json, monotimes, os, parseopt, strformat, strutils, times]
import ../src/koutendb

proc elapsedUs(start: MonoTime): float =
  float((getMonoTime() - start).inNanoseconds) / 1e3

proc userId(i: int): string =
  &"user-{i:08d}"

proc userPayload(id: string; i: int): JsonNode =
  %*{
    "id": id,
    "name": "Benchmark User " & $i,
    "tier": if i mod 17 == 0: "enterprise" else: "standard",
    "region": if i mod 3 == 0: "japan" elif i mod 3 == 1: "us" else: "eu",
    "profile": {
      "email": id & "@example.test",
      "status": "active",
      "note": "Synthetic profile record for pinpoint user read validation."
    }
  }

proc populateBroad(dataDir: string; users: int; diskBacked: bool): tuple[setUs: float, packUs: float, packRecords: int] =
  if dirExists(dataDir):
    removeDir(dataDir)
  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()
  let start = getMonoTime()
  for i in 0 ..< users:
    let id = userId(i)
    discard db.put(userPayload(id, i), ring = "users")
  result.setUs = elapsedUs(start)
  if diskBacked:
    let packStart = getMonoTime()
    let stats = db.packDiskBackedSegments()
    result.packUs = elapsedUs(packStart)
    result.packRecords = stats.records

proc populateLocal(dataDir: string; users: int; diskBacked: bool): tuple[setUs: float, packUs: float, packRecords: int] =
  if dirExists(dataDir):
    removeDir(dataDir)
  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()
  let start = getMonoTime()
  for i in 0 ..< users:
    let id = userId(i)
    discard db.put(userPayload(id, i), ring = "users/" & id)
  result.setUs = elapsedUs(start)
  if diskBacked:
    let packStart = getMonoTime()
    let stats = db.packDiskBackedSegments()
    result.packUs = elapsedUs(packStart)
    result.packRecords = stats.records

proc readBroad(dataDir, target: string; diskBacked: bool): tuple[us: float, count: int] =
  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()
  let start = getMonoTime()
  let page = db.readRing("users", KoutenReadOptions(
    filter: %*{"id": target},
    selection: "{ id name tier region }",
    limit: 1,
    cursor: "",
    pagination: rpOff,
    page: 1,
    pageLimit: 20,
    sortField: "time",
    sortDirection: rsDesc))
  result.us = elapsedUs(start)
  result.count = page.count

proc readLocal(dataDir, target: string; diskBacked: bool; limit: int): tuple[us: float, count: int] =
  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()
  let start = getMonoTime()
  let page = db.readRing("users/" & target, KoutenReadOptions(
    filter: newJObject(),
    selection: "{ id name tier region }",
    limit: limit,
    cursor: "",
    pagination: rpOff,
    page: 1,
    pageLimit: 20,
    sortField: "time",
    sortDirection: rsDesc))
  result.us = elapsedUs(start)
  result.count = page.count

proc main() =
  var dataDir = ""
  var users = 100_000
  var targetIndex = -1
  var diskBacked = true
  var metrics = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "data": dataDir = val
      of "users": users = parseInt(val)
      of "target-index": targetIndex = parseInt(val)
      of "disk-backed": diskBacked = true
      of "memory": diskBacked = false
      of "metrics": metrics = true
      else: discard
    of cmdArgument, cmdShortOption, cmdEnd:
      discard

  if dataDir.len == 0:
    raise newException(ValueError,
      "usage: pinpoint_user_read_bench --data=DIR [--users=N] [--target-index=N] [--disk-backed|--memory]")
  if users <= 0:
    raise newException(ValueError, "users must be > 0")
  if targetIndex < 0:
    targetIndex = users div 2
  if targetIndex >= users:
    raise newException(ValueError, "target-index must be < users")

  createDir(dataDir)
  let broadDir = dataDir / "broad"
  let localDir = dataDir / "local"
  let target = userId(targetIndex)

  let broadSet = populateBroad(broadDir, users, diskBacked)
  let localSet = populateLocal(localDir, users, diskBacked)
  let broadRead = readBroad(broadDir, target, diskBacked)
  let localRead1 = readLocal(localDir, target, diskBacked, 1)
  let localRead20 = readLocal(localDir, target, diskBacked, 20)

  if metrics:
    echo &"pinpointUsers {users}"
    echo &"pinpointTarget {target}"
    echo &"pinpointDiskBacked {int(diskBacked)}"
    echo &"pinpointBroadSetLatencyUs {broadSet.setUs:.3f}"
    echo &"pinpointBroadSetUsPerRecord {broadSet.setUs / float(users):.6f}"
    echo &"pinpointBroadPackLatencyUs {broadSet.packUs:.3f}"
    echo &"pinpointBroadPackRecords {broadSet.packRecords}"
    echo &"pinpointLocalSetLatencyUs {localSet.setUs:.3f}"
    echo &"pinpointLocalSetUsPerRecord {localSet.setUs / float(users):.6f}"
    echo &"pinpointLocalPackLatencyUs {localSet.packUs:.3f}"
    echo &"pinpointLocalPackRecords {localSet.packRecords}"
    echo &"pinpointBroadReadLatencyUs {broadRead.us:.3f}"
    echo &"pinpointBroadReadCount {broadRead.count}"
    echo &"pinpointLocalReadOneLatencyUs {localRead1.us:.3f}"
    echo &"pinpointLocalReadOneCount {localRead1.count}"
    echo &"pinpointLocalReadTwentyLatencyUs {localRead20.us:.3f}"
    echo &"pinpointLocalReadTwentyCount {localRead20.count}"
    return

  echo "== KoutenDB pinpoint user read benchmark =="
  echo &"users={users} target={target} disk_backed={diskBacked}"
  echo &"broad set latency_us={broadSet.setUs:.3f} us_per_record={broadSet.setUs / float(users):.6f}"
  echo &"broad pack latency_us={broadSet.packUs:.3f} records={broadSet.packRecords}"
  echo &"local set latency_us={localSet.setUs:.3f} us_per_record={localSet.setUs / float(users):.6f}"
  echo &"local pack latency_us={localSet.packUs:.3f} records={localSet.packRecords}"
  echo &"broad users filter read latency_us={broadRead.us:.3f} count={broadRead.count}"
  echo &"local users/<id> read limit=1 latency_us={localRead1.us:.3f} count={localRead1.count}"
  echo &"local users/<id> read limit=20 latency_us={localRead20.us:.3f} count={localRead20.count}"

when isMainModule:
  main()
