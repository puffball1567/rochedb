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

## Stellar Neighborhood Reads

RocheDB treats nearby rings as a natural read neighborhood. The mental model is
closer to a telescope than to a late join: when the read is centered on a ring,
nearby child, parent, and sibling rings can be in the same field of view. Distant
rings are not forced into the read path.

For example, an application can store a user profile at `users/123` and then
place orders and billing records nearby:

```bash
roche put --ring=users/123 \
  --payload='{"kind":"user","name":"Alice"}' --codec=json

roche put --ring=orders --near=users/123 \
  --payload='{"kind":"order","orderNo":"A-001"}' --codec=json

roche put --ring=billing --near=users/123 \
  --payload='{"kind":"billing","plan":"pro"}' --codec=json
```

The `--near=users/123 --ring=orders` write resolves to the concrete coordinate
`users/123/orders`. The `near` hint is not stored as a separate relationship.
After the write, the coordinate is the relationship.

Reading the user ring can naturally return the nearby user, order, and billing
records:

```bash
roche get --ring=users/123
roche get --stellar=users/123 --filter='{"kind":"order"}' --subring=orders
```

Reading from the order side also sees the nearby user because the order is in
the same stellar neighborhood:

```bash
roche get --ring=users/123/orders
```

To narrow the field of view, use `--subring`:

```bash
roche get --ring=users/123 --subring=orders,billing
```

Existing coordinates can also be attached to or detached from a stellar
coordinate's lens:

```bash
roche stellar attach --stellar=commerce/order/A-001 --ring=users/123
roche stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
roche stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001
roche stellar detach --stellar=commerce/order/A-001 --ring=shops/1123
```

Attach/detach changes visibility metadata only. It does not copy payloads,
delete payloads, or create a strict relational constraint.

This is not a hidden global join. RocheDB only walks the configured nearby
coordinate neighborhood, controlled by depth and branch budget. If a record is
far away, such as `users/999/orders`, it is not read when the telescope is
pointed at `users/123`.

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

- random writes;
- delete-heavy workloads;
- backfill-heavy workloads;
- hot/cold ring skew;
- read latency before and after locality-aware compaction;
- larger datasets where OS page cache and SSD read behavior become visible.

Those cases are deliberately separate from the first metric surface so the core
behavior remains easy to audit.
