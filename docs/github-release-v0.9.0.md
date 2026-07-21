# KoutenDB v0.9.0

KoutenDB v0.9.0 is a locality and validation release. It adds a more realistic
related-data read benchmark, improves bounded stellar/subring reads, and records
the large local validation results that drove the storage-path changes.

Release:

https://github.com/puffball1567/koutendb/releases/tag/v0.9.0

## What Changed

- Added `examples/subring_bundle_bench.nim`.
- Added `examples/subring_bundle_postgres_bench.sh`.
- Added per-subring limit and sort validation for stellar reads.
- Optimized `readStellar` by preparing projection state once and reusing it
  across subrings.
- Added a bounded ring-window read path for simple embedded reads with empty
  filters, positive limits, and `id` or `time` sorting.
- Added cached disk segment read streams for disk-backed segment reads.
- Updated benchmark documentation with the latest local PostgreSQL and
  KoutenDB related-data bundle comparison.
- Updated effect-validation documentation with the completed 13.5M-record local
  stress result.

## Why This Matters

This release focuses on a practical shape that appears in ordinary
applications: a detail endpoint that needs a root entity plus several related
collections, where each collection has its own limit and sort order.

In KoutenDB this can be expressed as nearby subrings:

```sh
kouten get --ring=users/<id> \
  --subring=profile,addresses,career,preferences,orders,notifications \
  --subring-limit=profile:1,addresses:3,career:2,preferences:1,orders:10,notifications:5 \
  --subring-rsort=orders:time,notifications:time
```

The goal is not to claim that KoutenDB is universally faster than PostgreSQL or
Redis. The goal is narrower and more important for KoutenDB's design: when the
application already has useful locality, KoutenDB should retrieve the nearby
working set directly, without turning the request into a broad scan or a
response-shaping query.

## Local Benchmark Result

Measured on 2026-07-21 with AMD Ryzen 5 5600H, Linux 6.8, Nim 2.2.10, and
PostgreSQL 14.23. The helper creates fresh temporary KoutenDB and PostgreSQL
data directories.

Reproduce:

```sh
N=10000 READS=1000 examples/subring_bundle_postgres_bench.sh
```

Result:

| Users | Logical records | Group | Query shape | Returned records | read latency us |
|---:|---:|---|---|---:|---:|
| 10,000 | 1,050,000 | KoutenDB | `users/<id>/*` stellar read with per-subring limits/sorts | 22 across 6 rings | 196.859 |
| 10,000 | 1,050,000 | PostgreSQL 14.23 | six indexed `SELECT` statements | 22 | 515 |
| 10,000 | 1,050,000 | PostgreSQL 14.23 | one JSON aggregate query over indexed limited subqueries | 1 JSON bundle | 236 |

This is a specific related-data bundle workload, not a universal PostgreSQL
claim. PostgreSQL can express the result with indexed limited subqueries and
JSON aggregation, but the query shape is no longer a plain join. KoutenDB
expresses the access pattern as bounded nearby subrings.

## Large Effect Validation

The generated scale-1000 effect-validation path also completed locally with
13,500,000 documents in the largest standard case. The measured result is
documented in `docs/effect-validation.md`.

Summary:

- `small-balanced`: `168000 -> 24000` scanned records, `692 -> 260` estimated
  tokens.
- `near-distractors`: `1860000 -> 120000` scanned records, `1730 -> 433`
  estimated tokens.
- `medium-noisy`: `13500000 -> 500000` scanned records, `2595 -> 692`
  estimated tokens.

The largest case also exposed a useful follow-up target: post-import segment
packing is much faster than the earlier unbuffered path, but still large enough
to keep optimizing.

## Verification

This release state was verified with:

- `nim check src/kouten/store.nim`
- `nim check src/koutendb.nim`
- `nim check src/koutencli.nim`
- `nim check tests/tapi.nim`
- `nim c --nimcache:/tmp/nimcache_kouten_tapi -r tests/tapi.nim`
- `scripts/test_all_smoke.sh`
- `nimble check`
- `git diff --check`

The large generated benchmark is intentionally manual and is not part of the
default CI smoke suite.
