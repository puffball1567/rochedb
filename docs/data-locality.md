# Data Locality

KoutenDB uses rings as logical locality hints, but locality is not only a
logical concept. Persistent embedded stores also expose physical WAL locality
metrics so users can inspect whether related live records are physically grouped
after real write patterns.

This document describes the current locality model and the first measurement
surface. It is intentionally conservative: these metrics describe KoutenDB's WAL
layout, not a universal storage-performance claim.

## Logical Locality

Applications place records into rings. A ring is not just a directory-like
route. It is the retrieval unit KoutenDB uses to reduce unnecessary scans,
candidate memory, and downstream payload work.

For AI/RAG-style workloads, this means the application can make the natural
structure of the corpus part of the retrieval model. For web workloads, it means
user-, tenant-, topic-, region-, or time-oriented records can be grouped in a
way that matches common reads.

## Stellar Neighborhood Reads

KoutenDB treats nearby rings as a natural read neighborhood. The mental model is
closer to a telescope than to a late join: when the read is centered on a ring,
nearby child, parent, and sibling rings can be in the same field of view. Distant
rings are not forced into the read path.

For example, an application can store a user profile at `users/123` and then
place orders and billing records nearby:

```bash
kouten put --ring=users/123 \
  --payload='{"kind":"user","name":"Alice"}' --codec=json

kouten put --ring=orders --near=users/123 \
  --payload='{"kind":"order","orderNo":"A-001"}' --codec=json

kouten put --ring=billing --near=users/123 \
  --payload='{"kind":"billing","plan":"pro"}' --codec=json
```

The `--near=users/123 --ring=orders` write resolves to the concrete coordinate
`users/123/orders`. The `near` hint is not stored as a separate relationship.
After the write, the coordinate is the relationship.

Reading the user ring can naturally return the nearby user, order, and billing
records:

```bash
kouten get --ring=users/123
kouten get --stellar=users/123 --filter='{"kind":"order"}' --subring=orders
```

Reading from the order side also sees the nearby user because the order is in
the same stellar neighborhood:

```bash
kouten get --ring=users/123/orders
```

To narrow the field of view, use `--subring`:

```bash
kouten get --ring=users/123 --subring=orders,billing
```

Existing coordinates can also be attached to or detached from a stellar
coordinate's lens:

```bash
kouten stellar attach --stellar=commerce/order/A-001 --ring=users/123
kouten stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
kouten stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001
kouten stellar detach --stellar=commerce/order/A-001 --ring=shops/1123
```

Attach/detach changes visibility metadata only. It does not copy payloads,
delete payloads, or create a strict relational constraint.

This is not a hidden global join. KoutenDB only walks the configured nearby
coordinate neighborhood, controlled by depth and branch budget. If a record is
far away, such as `users/999/orders`, it is not read when the telescope is
pointed at `users/123`.

## Physical Locality

Persistent embedded stores use an append-only WAL. Before compaction, physical
record order mostly follows write order. If writes are interleaved across many
rings, the physical layout can also be interleaved.

Compaction rewrites a compact WAL snapshot from live state. KoutenDB writes live
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
kouten locality --data=/var/lib/koutendb
kouten locality --data=/var/lib/koutendb --metrics
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

The demo also prints an `invariant` line:

```text
invariant ring=locality/ring-0 sameSet=true beforeCandidates=22 afterCandidates=22 beforeDiskSpanRuns=88 afterDiskSpanRuns=4 beforeFragmentedRings=4 afterFragmentedRings=0 beforeLatencyUs=30.050 afterLatencyUs=29.894
```

This is the important safety check. The same logical ring query must return the
same ID/payload set before and after compaction. Locality improvement is only
useful if the logical result set is preserved.

The demo can also run less clean write patterns:

```bash
WORKLOAD=random examples/locality_layout_demo.sh
WORKLOAD=delete-heavy examples/locality_layout_demo.sh
WORKLOAD=backfill-heavy examples/locality_layout_demo.sh
WORKLOAD=hot-cold examples/locality_layout_demo.sh
```

Useful knobs:

| Environment variable | Meaning |
| --- | --- |
| `RINGS` | Number of rings to write |
| `PER_RING` | Baseline records per ring |
| `BACKFILL` | Additional backfill records |
| `WORKLOAD` | `interleaved`, `random`, `delete-heavy`, `backfill-heavy`, or `hot-cold` |
| `READ_ITERS` | Number of repeated ring reads used for before/after latency sampling |

The output includes `read_before` and `read_after` lines. These are local
micro-samples, not universal latency claims. They exist to catch large
regressions and to make compact-before/compact-after behavior observable next
to the physical locality metrics.

The output also reports candidate/result counts and physical span indicators in
the invariant line:

- `beforeCandidates` / `afterCandidates`: records returned by the logical ring
  query;
- `beforeDiskSpanRuns` / `afterDiskSpanRuns`: physical live ring runs in the
  WAL;
- `beforeFragmentedRings` / `afterFragmentedRings`: rings split across multiple
  physical runs;
- `beforeLatencyUs` / `afterLatencyUs`: repeated read micro-samples.

## Current Scope

This is not a full LSM-tree, B+ tree, or columnar layout. KoutenDB's current
layout bet is simpler:

1. Use rings to reduce the logical working set before retrieval.
2. Keep normal writes append-only.
3. Use compaction to restore physical ring grouping for live records.
4. Measure the effect directly through locality metrics.

Secondary access paths should avoid fighting this primary layout. In the current
design, secondary mechanisms should remain hints, projections, or lookup maps
that point back into ring-local reads instead of becoming a competing primary
layout.

Stellar attach/detach is part of that rule. It changes which coordinates are
visible through a lens. The current compact implementation still groups live
records by ring. A future compaction pass can use stellar lens metadata to place
small nearby coordinates immediately when cheap, or defer large/crowded rings to
scheduled compaction.

Another future option is shadow compaction through a parallel universe: keep the
active universe serving reads/writes, compact a synced universe in the
background, verify it, then promote it. That is roadmap work; the current
implementation keeps compaction simple and local.

## What Still Needs Work

The next locality work should add benchmark cases for:

- larger adversarial datasets for random writes;
- larger adversarial datasets for delete-heavy workloads;
- larger adversarial datasets for backfill-heavy workloads;
- larger adversarial datasets for hot/cold ring skew;
- larger datasets where OS page cache and SSD read behavior become visible.

The v0.6 locality-validation branch starts adding these cases to the runnable
demo and store test matrix. The current invariant checks verify that compaction
does not change the logical result set while locality metrics improve. Larger
OS page-cache and SSD-sensitive benchmarks still need separate benchmark runs
because tiny local unit tests cannot prove hardware-level locality behavior.
