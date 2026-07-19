# OrbeliasDB v0.5.0

OrbeliasDB v0.5.0 is a technical-preview release focused on making OrbeliasDB's
placement-aware data model more explicit and more useful for ordinary
application workflows.

Release:

https://github.com/puffball1567/orbeliasdb/releases/tag/v0.5.0

OrbeliasDB is still not presented as a production replacement for Redis,
PostgreSQL, MongoDB, Apache Arrow, or a dedicated vector database. The stronger
claim in this release is narrower: OrbeliasDB can make meaningful data placement
part of the read path, operating boundary, and high-integrity application
workflow.

## Main Changes

- Added stellar locality lens workflows.
- Added `orbelias get --stellar=...` with `--subring`, filter, selection, and
  grouped output.
- Added `orbelias stellar attach|detach|list`.
- Added non-copy visibility metadata for existing rings.
- Added embedded atomic bulk helpers:
  - `batchPutAtomic`
  - `batchUpdateAtomic`
  - `batchDeleteAtomic`
- Added opt-in embedded cooperative coordinate locks:
  - `acquireRingLock`
  - `acquireStellarLock`
  - `withRingLock`
  - `withStellarLock`
  - `releaseLock`
  - `lockActive`
- Added `docs/unique-data-model.md`.
- Added `examples/stellar_data_model_demo.sh`.
- Updated benchmark comparison tables and benchmark notes with the latest local
  and Docker-Docker measurements.

## Why This Release Matters

OrbeliasDB's model is no longer only "place records in rings and retrieve from
rings". This release adds a clearer shape for application data:

```text
ring     = meaningful coordinate
stellar  = locality lens over related coordinates
subring  = narrowed field of view
lock     = opt-in coordination around a coordinate or lens
atomic   = all-or-nothing embedded bulk workflow
```

This makes OrbeliasDB more useful for ordinary application domains such as SaaS,
CRM, support tools, catalogs, user/order detail views, and AI/RAG knowledge
systems. It does not turn OrbeliasDB into a payment ledger or a financial core
database, but it gives application workflows stronger primitives around
external payment systems, retries, webhooks, and coordinated updates.

## Example

```sh
orbelias put --ring=users/123 \
  --payload='{"kind":"user","name":"Alice"}' --codec=json

orbelias put --ring=shops/1123 \
  --payload='{"kind":"shop","name":"Orbit Store"}' --codec=json

orbelias put --ring=orders/A-001 \
  --payload='{"kind":"order","orderNo":"A-001","total":42}' --codec=json

orbelias stellar attach --stellar=commerce/order/A-001 --ring=users/123
orbelias stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
orbelias stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001

orbelias get --stellar=commerce/order/A-001 \
  --selection='{ kind name orderNo total }'

orbelias get --stellar=commerce/order/A-001 --subring=shops
```

## Benchmark Notes

The benchmark documents were updated with the latest local verification pass.
The headline working-set results remain stable:

- Working-set benchmark: scanned/query `10000 -> 100`.
- Memory-pressure benchmark: candidate memory/query `46.539 MiB -> 0.465 MiB`
  in the light verification run.
- Synthetic RAG benchmark: recall stayed `1.000` while scanned/query dropped
  `8000 -> 1000` and estimated tokens/query dropped `3955 -> 657`.
- Local Redis comparison: OrbeliasDB single TCP GET remains in the same latency
  class as Redis GET, while OrbeliasDB batch get remains faster than Redis
  pipeline GET in the local helper run.

These are local benchmark results, not universal performance claims. The point
is that the reduced working set is not being bought with an obviously slow
local read path.

## Verification

The local verification pass included:

- `nim check src/orbeliasdb.nim`
- `nim check src/orbeliascli.nim`
- `scripts/test_core.sh`
- `scripts/cli_crud_smoke.sh`
- working-set, memory-pressure, RAG, Redis, PostgreSQL, and Docker-Docker
  comparison helpers during the feature branch verification cycle
- `git diff --check`

## Known Boundaries

- Cluster transaction coordinator redundancy is still planned.
- Dynamic membership / arc-table based remapping is still planned.
- Cooperative locks are embedded opt-in workflow guards in this release; normal
  `put`, `get`, `list`, and `retrieve` paths do not check them.
- OrbeliasDB is not a payment ledger or a financial-core database.
