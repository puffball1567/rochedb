# Data Locality

RocheDB uses rings as logical locality hints, but locality is not only a
logical concept. Persistent embedded stores also expose physical WAL locality
metrics so users can inspect whether related live records are physically grouped
after real write patterns.

This document describes the current locality model and the first measurement
surface. It is intentionally conservative: these metrics describe RocheDB's WAL
layout, not a universal storage-performance claim.

## Logical Locality

Applications place records into rings. A ring is not just a directory-like
route. It is the retrieval unit RocheDB uses to reduce unnecessary scans,
candidate memory, and downstream payload work.

For AI/RAG-style workloads, this means the application can make the natural
structure of the corpus part of the retrieval model. For web workloads, it means
user-, tenant-, topic-, region-, or time-oriented records can be grouped in a
way that matches common reads.

## Physical Locality

Persistent embedded stores use an append-only WAL. Before compaction, physical
record order mostly follows write order. If writes are interleaved across many
rings, the physical layout can also be interleaved.

Compaction rewrites a compact WAL snapshot from live state. RocheDB writes live
particle records in stable `(ringKey, seq)` order during snapshot creation. That
makes compaction locality-aware for the primary ring layout:

- live records from the same ring are grouped together;
- deleted or overwritten particle records are removed from the compact snapshot;
- ring metadata and durable queues are written in deterministic order;
- the append-only operational WAL remains simple between compactions.

This is the first step toward answering locality questions with measurements
rather than only design language.

## Locality Report

The embedded API exposes:

```nim
let report = db.localityReport()
```

The CLI exposes the same information:

```bash
roche locality --data=/var/lib/rochedb
roche locality --data=/var/lib/rochedb --metrics
```

Important fields:

| Field | Meaning |
| --- | --- |
| `walBytes` | Current WAL size in bytes |
| `totalParticleRecords` | Particle records physically present in the WAL |
| `liveParticleRecords` | Particle records that still match live store state |
| `deadParticleRecords` | Older overwritten or removed particle records |
| `ringCount` | Number of rings with live particle records |
| `ringRuns` | Number of contiguous live particle runs by ring |
| `fragmentedRings` | Rings that appear in more than one physical run |
| `avgRunRecords` | Average live records per physical ring run |
| `maxRunRecords` | Largest contiguous live ring run |
| `localityScore` | `ringCount / ringRuns`; `1.0` means one run per ring |

`ringRuns` is the most direct physical locality signal. If `ringCount=10` and
`ringRuns=10`, each ring appears as one contiguous live run in the WAL. If
`ringRuns=1000`, writes have fragmented ring locality and compaction may help.

## Demo

Run:

```bash
examples/locality_layout_demo.sh
```

Example output from a small local run:

```text
before_compact ... ringCount=4 ringRuns=43 fragmentedRings=4 avgRunRecords=1.023 localityScore=0.093023
compact beforeBytes=4964 afterBytes=4968 items=44
after_compact ... ringCount=4 ringRuns=4 fragmentedRings=0 avgRunRecords=11.000 localityScore=1.000000
```

The demo intentionally writes records in an interleaved pattern, then runs
compaction. The important result is not the exact byte count; it is that the
same live records become physically grouped by ring after compaction.

## Current Scope

This is not a full LSM-tree, B+ tree, or columnar layout. RocheDB's current
layout bet is simpler:

1. Use rings to reduce the logical working set before retrieval.
2. Keep normal writes append-only.
3. Use compaction to restore physical ring grouping for live records.
4. Measure the effect directly through locality metrics.

Secondary access paths should avoid fighting this primary layout. In the current
design, secondary mechanisms should remain hints, projections, or lookup maps
that point back into ring-local reads instead of becoming a competing primary
layout.

## What Still Needs Work

The next locality work should add benchmark cases for:

- random writes;
- delete-heavy workloads;
- backfill-heavy workloads;
- hot/cold ring skew;
- read latency before and after locality-aware compaction;
- larger datasets where OS page cache and SSD read behavior become visible.

Those cases are deliberately separate from the first metric surface so the core
behavior remains easy to audit.
