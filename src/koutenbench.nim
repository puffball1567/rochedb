## koutenbench - mechanism benchmark
##
## Measures KoutenDB mechanism costs: location resolution, reads/writes, and
## predictive operations, compared with simple baseline implementations.
## Does not measure persistence, networking, or concurrency.
##
## build: nim c -d:danger -o:bin/koutenbench src/koutenbench.nim

import std/[monotimes, times, tables, strformat]
import kouten/core
import koutendb

# Deterministic LCG for reproducibility.
var rngState: uint64 = 0x9E3779B97F4A7C15'u64
proc nextU64(): uint64 =
  rngState = rngState * 6364136223846793005'u64 + 1442695040888963407'u64
  rngState

proc report(name: string, ns: float) =
  let mops = 1000.0 / ns
  echo &"  {name:<52} {ns:9.1f} ns/op  ({mops:8.2f} Mops/s)"

template bench(name: string, iters: int, body: untyped) =
  block:
    let start = getMonoTime()
    body
    report(name, float((getMonoTime() - start).inNanoseconds) / float(iters))

const
  N = 1_000_000       # stored records
  Lookups = 10_000_000
  Payload = 100        # bytes per record

echo &"records N = {N}, payload = {Payload} bytes, lookup count = {Lookups}"
echo ""

# ---------------------------------------------------------------- A. Location resolution
echo "[A] Location resolution: ephemeris calculation vs directory-table lookup"

block:
  let tbl = ArcTable(epoch: 1, nNodes: 8)
  let o = Orbit(a: 1.0, phi: 1.234, period: 60.0, e: 0.2, pomega: 0.7)
  var acc: uint64 = 0
  bench("ephemeris location, core, arbitrary time", Lookups):
    for i in 0 ..< Lookups:
      acc += uint64(tbl.node(o, float(i) * 0.001))
  doAssert acc > 0

block:
  # Baseline: a local id -> node table, equivalent to a metadata-cache lookup.
  # It answers only current placement and needs invalidation when data moves.
  var dir = initTable[uint64, uint16](N)
  for i in 0 ..< N:
    dir[uint64(i)] = uint16(i mod 8)
  var acc: uint64 = 0
  bench("directory-table lookup, 1M records, current only", Lookups):
    for i in 0 ..< Lookups:
      acc += uint64(dir[nextU64() mod uint64(N)])
  doAssert acc > 0

block:
  var db = koutendb.open()
  let id = db.put("x")
  var acc = 0
  bench("db.locate, public API, current time", Lookups):
    for i in 0 ..< Lookups:
      acc += db.locate(id)
  bench("db.locate, public API, future time", Lookups):
    for i in 0 ..< Lookups:
      acc += db.locate(id, at = float(i))
  doAssert acc > 0
  db.close()

# ---------------------------------------------------------------- B. Reads and writes
echo ""
echo "[B] In-memory reads/writes: public API vs raw table baseline"

var payload = newString(Payload)
for i in 0 ..< Payload: payload[i] = char(ord('a') + i mod 26)

var ids = newSeq[KoutenId](N)
block:
  var db = koutendb.open()
  bench(&"db.put, {N} records", N):
    for i in 0 ..< N:
      ids[i] = db.put(payload, ring = "bench")
  var got = 0
  bench(&"db.get, random {N} reads", N):
    for i in 0 ..< N:
      got += db.get(ids[int(nextU64() mod uint64(N))]).len
  doAssert got == N * Payload
  db.close()

block:
  var raw = initTable[uint64, string](N)
  bench(&"raw table put, {N} records, baseline", N):
    for i in 0 ..< N:
      raw[uint64(i)] = payload
  var got = 0
  bench(&"raw table get, random {N} reads, baseline", N):
    for i in 0 ..< N:
      got += raw[nextU64() mod uint64(N)].len
  doAssert got == N * Payload

# ---------------------------------------------------------------- C. Predictive operations
echo ""
echo "[C] Predictive operations without a directory-table equivalent"

block:
  var db = koutendb.open()
  db.configureRing("docs", 30.0)
  db.configureRing("logs", 60.0)
  let a = db.put("doc", ring = "docs")
  let b = db.put("log", ring = "logs")
  var acc = 0.0
  bench("nextVisit, arrival time at a selected node", 1_000_000):
    for i in 0 ..< 1_000_000:
      acc += db.nextVisit(a, i mod 8)
  bench("nextJoin, encounter time for two records", 100_000):
    for i in 0 ..< 100_000:
      acc += db.nextJoin(a, b)
  doAssert acc > 0.0
  db.close()
