# RocheDB Benchmark Notes

This document records measurements made during the v0.1.0 technical-preview
implementation. The sections are intentionally separated by purpose and
conditions:

- Mechanism benchmarks measure in-process orbit evaluation, embedded API cost,
  predictive operations, and C ABI overhead.
- Cluster and PostgreSQL measurements exercise TCP, persistence, and a
  single-client network path.
- Redis measurements are local smoke tests for simple read and batch-read
  latency.
- Working-set, memory-pressure, and RAG-style measurements test RocheDB's main
  hypothesis: reduce the candidate set before downstream processing.

Do not read any single table as a universal performance claim. Read the
environment, purpose, and interpretation together.

---

# Mechanism Benchmarks

- Date: 2026-07-04
- Environment: AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10 `-d:danger` / gcc
  `-O2` / `--mm:arc`
- Reproduction: `bin/rochebench` (`src/rochebench.nim`) and `bin/cbench`
  (`examples/cbench.c`)
- Conditions: 1,000,000 stored records, 100-byte payloads, 10,000,000 location
  evaluations, single thread

## What This Section Measures

Measured: mechanism cost, including location resolution, in-memory reads and
writes, predictive operations, and C ABI boundary overhead.

Not measured in this section: persistence, networking, concurrency, or failure
behavior. Therefore this section alone is not a Redis, RocksDB, PostgreSQL, or
MongoDB comparison. The baseline is a simple in-process implementation of a
similar primitive, such as a directory table or raw hash table.

## A. Location Resolution

| Operation | ns/op | Notes |
|---|---:|---|
| ephemeris location calculation, core | **27.5** | One `sin` plus arc-table lookup; supports arbitrary time |
| directory-table lookup, 1M table | 28.9 | Equivalent to a local metadata cache; answers only current location |
| `db.locate`, public API, current time | 38.5 | Includes one ring metadata lookup |
| `db.locate`, public API, future time | 54.7 | No direct equivalent in a directory-only design |

Interpretation: computing placement is in the same cost range as a local table
lookup. The point is not raw speed alone. At similar cost, RocheDB also answers
future placement, avoids invalidating a central location table when data moves,
and avoids cross-node coordination for location discovery.

## B. Embedded Reads and Writes

| Operation | ns/op | Mops/s |
|---|---:|---:|
| `db.put` | 264.5 | 3.8 |
| `db.get`, random | 304.8 | 3.3 |
| raw table put, baseline | 122.0 | 8.2 |
| raw table get, random baseline | 33.4 | 29.9 |

Interpretation: the 2x to 9x overhead is the cost of RocheDB's orbit-aware ID
model, ring metadata lookup, tuple key, and owned-copy return path. This is an
optimization target. In distributed mode, network RTT usually dominates this
hundreds-of-nanoseconds difference.

## C. Predictive Operations

| Operation | ns/op |
|---|---:|
| `nextVisit`, next arrival at a node | 40.7 |
| `nextJoin`, next encounter between two records | 95.7 |

These operations are hard to express in a directory-only design. RocheDB can use
closed-form timing to reason about "wait vs move" style plans.

## D. C ABI Boundary

| Operation | ns/op | Notes |
|---|---:|---|
| `roche_put` | 362.5 | Nim API plus roughly 98 ns for FFI and payload copy |
| `roche_get` | 194.3 | Includes duplicate buffer, NUL terminator, and `roche_free`; access pattern differs from random get |
| `roche_locate`, future time | 77.7 |  |

The FFI boundary overhead is generally tens of nanoseconds per call. Bindings do
not change the mechanism's basic profile.

## Completion Gate

The design target of location evaluation below 100 ns/call is met at every
measured layer: core `27.5 ns`, public API `54.7 ns`, and C ABI `77.7 ns`.

---

# Cluster Mode and PostgreSQL Reference

- Date: 2026-07-08, after the v0.2.5 read-path and benchmark-ring fixes
- Environment: same machine, AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10
- RocheDB setup: three `roched` nodes, persistence enabled, single client,
  persistent TCP connection, 100-byte payload, `n=10000`
- Reproduction: start three `roched` processes with `--id=k --peers=...
  --data=...`, then run `roche bench --peers=... --n=10000`
- Reproduction helper: `N=10000 examples/postgres_bench.sh` starts a temporary
  three-node RocheDB cluster and a temporary local PostgreSQL cluster, then runs
  both benchmark shapes. It requires `initdb`, `pg_ctl`, `psql`, and `pgbench`
  from a local PostgreSQL installation.
- Benchmark guard: the client configures a long-period benchmark ring and
  samples `locate` across the measurement horizon. The selected ring must stay
  on one owner during the run so handoff traffic is not mixed into the local
  request-path measurement.

## RocheDB Cluster Path

| Operation | us/op | ops/s |
|---|---:|---:|
| put, location calculation + 1 RTT + append log | 48.5-49.0 | 20,388-20,601 |
| get, location calculation + 1 RTT | 45.2-46.5 | 21,506-22,100 |
| query, server-side JSON projection | 50.4-52.5 | 19,051-19,856 |

## PostgreSQL 14 Reference

Same machine, temporary local PostgreSQL 14.23 cluster, single client, single
thread, TCP endpoint `127.0.0.1:55432`, `pgbench -M prepared`.

### RocheDB Measurements

| Operation | us/op | Notes |
|---|---:|---|
| single-key read | 45.2-46.5 | Three `roched` nodes, persistence enabled |
| single-row write | 48.5-49.0 | Three `roched` nodes, persistence enabled |
| strong-durability write | not measured | `durStrong` / `--durability=strong` was not part of this comparison |

### PostgreSQL Measurements

| Operation | us/op | Notes |
|---|---:|---|
| primary-key `SELECT` | 75 | 13.3k tps |
| single-row write, `synchronous_commit=off` | 80 | 12.5k tps |
| single-row write, `synchronous_commit=on` | 1961 | 510 tps |

Interpretation: this compares a thin KV/document path with a SQL RDBMS path that
includes parsing, planning, MVCC, and index maintenance. The defensible claim is
that RocheDB's network KV path is in the same latency class as PostgreSQL
primary-key access and is ahead under these local conditions. RocheDB's
durability mode in this comparison was closer to `synchronous_commit=off`.
RocheDB now has `durStrong` / `--durability=strong`, but that path was not part
of the 2026-07-08 PostgreSQL comparison.

## Optimization History

An early cluster `get` measured around `1276 us`. Two issues dominated:

1. A handoff scan ran after each ready `select`, adding roughly `200 us` of orbit
   calculation per request. This was throttled with a monotonic 100 ms gate.
2. The benchmark accidentally chose a ring whose head angle sat on an arc
   boundary, so 10,000 records migrated during the run. The first guard only
   compared `locate(now)` with `locate(now + 60s)`, which can misclassify a
   full-period orbit as stable even when it crosses other nodes in between. The
   benchmark now uses a long-period ring and samples intermediate points across
   the measurement horizon. The storm itself was valid behavior, but reads
   during that interval pay the wake-fallback cost.
3. v0.2.4 added cluster transaction landing-zone reads. A first implementation
   checked the landing zone before ordinary cluster GET/BGET, adding an
   avoidable request to node0 on the normal read path. v0.2.5 tracks only IDs
   written through accepted-but-not-yet-applied operations on the current client,
   so ordinary reads use the direct owner path while those pending IDs can still
   read their landing intent.

During this work a TOCTOU race was found: a read could check the primary, then
the wake, while the record moved forward and missed both. A final primary
revisit fixes this because movement is forward-only.

---

# Redis Approximation and BGET

- Date: 2026-07-08, after the v0.2.5 landing-zone read-path fix
- Environment: same machine, AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10
  `-d:release`
- Redis: local `/usr/bin/redis-server`, Redis 6.0.16, endpoint
  `127.0.0.1:6379`
- RocheDB TCP: local one-node `roched`, endpoint `127.0.0.1:17301`,
  persistence disabled, persistent TCP connection
- Conditions: 100-byte payload, `n=1000`, single client, Redis pipeline batch
  size 256
- Reproduction: start one local `roched`, then run
  `roche redis-bench --n=1000 --payload-bytes=100 --redis=127.0.0.1:6379
  --peers=127.0.0.1:17301`
- Purpose: smoke-test whether RocheDB simple read and batch read are in the same
  latency class as Redis TCP and Redis pipeline under local constraints

| Operation | us/op | Interpretation |
|---|---:|---|
| RocheDB embedded get | 0.03 | In-process hot path; no TCP |
| RocheDB TCP get | 44.87 | One request / one response |
| RocheDB TCP BGET | 1.47 | Batch read; comparable axis to Redis pipeline |

Redis measurements under the same local benchmark shape:

| Operation | us/op | Interpretation |
|---|---:|---|
| Redis localhost GET | 41.23 | Local Redis, non-pipelined |
| Redis pipeline GET | 3.68 | Batch size 256 |

Interpretation: RocheDB TCP get is in the same latency class as non-pipelined
Redis GET, but local Redis was slightly faster for single GET. In this smoke
test, RocheDB TCP BGET was about 2.5x faster than Redis pipeline GET. This is
not a claim that RocheDB is always faster than Redis.
Payload size, batch size, Redis configuration, network mode, and data size need
broader measurement.

The important point for RocheDB is narrower: it is not merely reducing
working-set size while having an unusably slow local read path. The reduced local
working set can still be read in a competitive latency class.

---

# Semantic Working-Set Reduction

- Date: 2026-07-04
- Environment: same machine, AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10
  `-d:release`, embedded mode, persistence disabled
- Reproduction: `roche working-set-bench --n=10000 --rings=100
  --queries=10 --budget=20`
- Purpose: measure whether ring routing reduces physically scanned records per
  query, rather than full-scanning the entire corpus faster

| Condition | scanned/query | latency/query |
|---|---:|---:|
| global retrieve | 10000.0 | 2129.1 us |
| routed retrieve | 100.0 | 31.6 us |

```text
reduction scanned=99.00%
scan_ratio=100.0x
```

## Evidence That Scope Is Reduced Before Search

This benchmark is not merely returning fewer results. `retrieveStats` and
`retrievalEnvelope.stats` show that `scanned` goes down, which means the vector
backend touched fewer candidates.

A small API test pins the same property:

```text
totalVectors=4
global: scanned=4 skippedVectors=0 ringsTouched=2 candidateReduction=0.0
ring=ai: scanned=2 skippedVectors=2 ringsTouched=1 candidateReduction=0.5
```

With ring-scoped retrieve, two vectors in the other ring are skipped before the
candidate search. `skippedVectors` and `candidateReduction` are the guardrails
showing that RocheDB is not just filtering after retrieval.

| Measurement | global scanned | routed/scoped scanned | Reduction |
|---|---:|---:|---:|
| API minimum test | 4 | 2 | 50% |
| working-set bench | 10000/query | 100/query | 99% |
| RAG-style bench | 8000/query | 1000/query | 87.5% |

The "half" reduction belongs only to the tiny API test. In the 100-ring
synthetic working-set benchmark, search scope dropped to 1/100.

Interpretation: for a workload where the correct ring narrows the corpus by
100x, modest raw scan-efficiency differences can be absorbed by scanning far
fewer records.

---

# Memory-Pressure Case Study

- Date: 2026-07-05
- Environment: same machine, AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10
  `-d:release`, embedded mode, persistence disabled
- Reproduction: `roche memory-pressure-bench --n=100000 --rings=100
  --queries=50 --budget=20 --payload-bytes=512`
- Docker case-study script: `RUN_REDIS=0 examples/memory_pressure_case_study.sh`
- Purpose: evaluate the demand-side memory-reduction hypothesis as candidate
  working-set bytes per query

| Condition | scanned/query | candidate memory/query | latency/query |
|---|---:|---:|---:|
| global retrieve | 100000.0 | 93.079 MiB | 37186.3 us |
| routed retrieve | 1000.0 | 0.931 MiB | 508.9 us |

```text
reduction scanned=99.00% candidate_memory=99.00% memory_ratio=100.0x
```

Interpretation: in a 100-ring synthetic corpus, ring routing reduces candidate
working-set memory from about 93 MiB/query to about 0.93 MiB/query. This is not
total process RSS. It estimates the bytes that downstream ANN, rerank, or LLM
preprocessing would need to keep as candidates. RocheDB does not manufacture
memory; it reduces the demand created by reading, holding, and passing unneeded
records.

This benchmark keeps the return budget fixed at 20, so returned payload/token
size is roughly comparable. It measures memory pressure, not token reduction.
Token reduction is covered by the RAG-style quality-fixed benchmark.

---

# RAG-Style Quality-Fixed Benchmark

- Date: 2026-07-04
- Environment: same machine, AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10
  `-d:release`, embedded mode, persistence disabled
- Reproduction: `roche rag-bench --n=8000 --queries=80 --budget=20
  --routed-budget=3`
- Purpose: test whether scanned records and estimated tokens can be reduced
  while holding recall fixed

| Condition | recall | scanned/query | tokens/query | budget |
|---|---:|---:|---:|---:|
| global | 1.000 | 8000.0 | 3960.0 | 20 |
| routed | 1.000 | 1000.0 | 657.8 | 3 |

Interpretation: synthetic data showed no recall loss while reducing scanned
records to 1/8 and estimated tokens to roughly 1/6. This supports the first
smoke-level token and energy hypothesis. Real-corpus quality-fixed A/B
benchmarks remain a required next validation step.

---

# AI/RAG JSONL Case Study

- Date: 2026-07-06
- Environment: same machine, AMD Ryzen 5 5600H / Linux 6.8 / Nim 2.2.10
  `-d:release`, embedded mode, WAL-backed data directory
- Reproduction: `examples/ai_rag_case_study.sh`
- Data: the script generates a deterministic JSONL corpus and imports it through
  the same shape expected by `importJsonl`: `ring`, `body`, and `embedding`
- Corpus: 400 documents / 6 rings
  - `docs/japan`: 40
  - `docs/us`: 40
  - `support/errors`: 40
  - `papers/medicine`: 40
  - `papers/water`: 40
  - `noise/general`: 200
- Purpose: use a concrete generated corpus rather than a purely random
  benchmark, and show that correct ring routing can preserve recall while
  reducing both search scope and downstream token volume

| Condition | recall | scanned/query | tokens/query | budget |
|---|---:|---:|---:|---:|
| global | 1.000 | 400.0 | 615.2 | 8 |
| routed | 1.000 | 40.0 | 231.6 | 3 |
| wrong-ring | 0.000 | 40.0 | 231.6 | 3 |

```text
scanned reduction vs global=90.0%
token reduction vs global=62.4%
```

Interpretation: global retrieve scans all 400 vectors. Routed retrieve scans
only the 40 vectors in the correct ring and still keeps target-document recall
at 1.000. Wrong-ring retrieve scans the same small number of vectors but recall
drops to 0.000. This is an important guardrail: narrowing the search scope is
useful only when the ring, atlas, and import rule are correct enough to preserve
quality.
