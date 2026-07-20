# Time Orbit Design

Time orbit is an early KoutenDB placement model for time-series records such as
logs, events, audit trails, metrics, traces, and AI/RAG execution history.

The goal is to make time itself part of KoutenDB's coordinate model. Instead of
walking a tree, scanning from the top, or relying only on a separate secondary
index, KoutenDB can calculate where a time range should live and read only those
time-local rings.

This document is both a design note and the current early implementation guide.
The embedded API and CLI path exist, but cluster administration and wire-level
profile management are still future work.

## Core Idea

A timestamp can be mapped into a large circular coordinate space:

```text
timestamp_ms -> 60-bit millisecond orbit -> bucket -> ring-local coordinate
```

A 60-bit millisecond orbit has `2^60` positions. Interpreted as milliseconds,
one full cycle is about 36.5 million years:

```text
2^60 ms ~= 1.1529e18 ms ~= 36.5 million years
```

That is large enough that ordinary application time ranges do not need to think
about wraparound in practice, while still being compact enough to fit in a
simple integer coordinate.

## Ring-Local Orbits

The orbit must not be global-only. Different rings can receive data at very
different rates, and the same timestamp may appear in many unrelated datasets.

Therefore, each ring should be able to define its own time-orbit profile:

```text
ring: logs/api
  timeOrbit:
    bits: 60
    bucketMs: 1000
    phase: auto
    salt: logs-api

ring: logs/audit
  timeOrbit:
    bits: 60
    bucketMs: 60000
    phase: auto
    salt: logs-audit

ring: metrics/gpu
  timeOrbit:
    bits: 60
    bucketMs: 100
    phase: auto
    salt: metrics-gpu
```

The same timestamp in different rings should not be forced into the same
coordinate. A ring-local phase or salt lets those datasets occupy separate
orbits, like distant paths that never practically meet.

Conceptually:

```text
bucket       = timestamp_ms div bucketMs
orbit        = bucket mod 2^bits
coordinate   = (phase(ring) + orbit) mod 2^bits
storageRing  = ring + "/@time/" + coordinate
```

The exact physical ring name can evolve. The important contract is that the
mapping is deterministic from:

- the base ring;
- the timestamp;
- the ring's time-orbit profile.

## Writes

For logs and events, a write can place the record into the calculated
time-coordinate:

```text
putTime(ring = "logs/api", timestampMs = t, payload = doc)
  profile = timeOrbitProfile("logs/api")
  bucket  = t div profile.bucketMs
  coord   = profile.phase + bucket mod 2^profile.bits
  target  = "logs/api/@time/" + coord
  put(target, payload with timestamp metadata)
```

The payload should still carry at least:

- `eventTimeMs`: the time the event claims to describe;
- `ingestTimeMs`: the time KoutenDB received the event;
- an optional source id, sequence, or trace id for tie-breaking.

This keeps clock-skew and duplicate-event handling explicit.

## Reads

A time-range read calculates the affected buckets first:

```text
getTime(ring = "logs/api", fromMs = a, toMs = b)
  profile = timeOrbitProfile("logs/api")
  buckets = [a div bucketMs .. b div bucketMs]
  rings   = buckets mapped through profile.phase
  read only those time-local rings
  filter by eventTimeMs
  sort by eventTimeMs, ingestTimeMs, sequence
```

The read path should not need to start at a root node and descend through a
time tree. The coordinate calculation is the first-stage access path.

## Why This Is Useful

For log-like workloads, time is often the strongest natural locality signal.
Users usually ask questions like:

- "show the last 5 minutes of API errors";
- "show audit events for this user around this incident";
- "show traces generated during this deployment";
- "show RAG retrieval events around this model response".

If KoutenDB can calculate the time-local coordinate directly, it can avoid
searching unrelated historical data. This is the same broad design direction as
KoutenDB's ring and stellar locality: make application structure part of the
retrieval model.

## Bucket Width

The bucket width is the main tuning knob.

Small buckets reduce candidate records per read, but create more time rings.
Large buckets reduce ring count, but increase candidate records per read.

Possible defaults:

| Workload | Example bucket |
|---|---:|
| High-volume metrics | 100 ms - 1 s |
| API/application logs | 1 s - 1 min |
| Audit logs | 1 min - 1 hour |
| Batch/import history | 1 hour - 1 day |

The profile should be ring-specific because one application may have dense API
logs and sparse audit logs at the same time.

## Collision And Density

The design does not assume that one timestamp maps to one record. Many records
can share the same bucket and coordinate.

The goal is not to make every log event globally unique by coordinate. The goal
is to make the first read set small and predictable.

Record identity and ordering should still be represented with metadata such as:

- event timestamp;
- ingest timestamp;
- source id;
- per-source sequence;
- generated KoutenDB id.

## Relationship To Ring And Stellar Locality

Time orbit is not a replacement for ordinary rings or stellar lenses.

It is an additional placement profile for data whose dominant access pattern is
time-based. It can compose with existing KoutenDB ideas:

```text
logs/api/@time/<coord>
users/123/logs/@time/<coord>
rag/sessions/<session-id>/events/@time/<coord>
```

Stellar lenses can still connect related coordinates. For example, an incident
stellar lens could attach:

- an API log time range;
- a deployment event range;
- a trace range;
- a user audit range.

The time orbit narrows each stream; the stellar lens groups the related streams.

## Compaction And Retention

Time-local placement gives compaction and retention a clear unit of work.

Examples:

- compact old buckets into larger buckets;
- archive buckets older than a retention window;
- keep hot recent buckets on faster storage;
- move cold buckets to cheaper storage;
- remove expired buckets by ring-local policy.

Future compaction should preserve logical results while improving physical
layout metrics such as candidate-set size, disk span, and latency.

## Initial Implementation Shape

The current embedded implementation exposes numeric millisecond timestamps:

```sh
kouten time-orbit \
  --ring=logs/api \
  --bucket-ms=1000 \
  --bits=60 \
  --phase=100 \
  --salt=api

kouten time-put \
  --ring=logs/api \
  --time-ms=1784376000000 \
  --payload='{"level":"error","message":"timeout"}'

kouten time-get \
  --ring=logs/api \
  --from-ms=1784376000000 \
  --to-ms=1784376300000 \
  --filter='{"level":"error"}'
```

The embedded API equivalents are `configureTimeOrbitProfile`, `putTime`, and
`readTime`. ISO-8601 parsing and remote cluster profile administration are
future conveniences, not part of the first implementation.

## Non-Goals

Time orbit should not try to become a full analytics engine.

It should not replace:

- OLAP systems for wide ad-hoc aggregation;
- strict financial ledgers;
- complete trace analysis platforms;
- external object storage for long-term cold archives.

The intended scope is narrower: make time-series placement and retrieval more
direct for KoutenDB's coordinate-local access model.
