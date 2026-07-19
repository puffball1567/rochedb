# OrbeliasDB v0.6.0

OrbeliasDB v0.6.0 is a technical-preview release focused on topology remapping
foundations, locality validation, and easier operational configuration.

Release:

https://github.com/puffball1567/orbeliasdb/releases/tag/v0.6.0

OrbeliasDB is still not presented as a production replacement for Redis,
PostgreSQL, MongoDB, Apache Arrow, or a dedicated vector database. The stronger
claim in this release is narrower: OrbeliasDB now has more measurable support for
preserving logical query results while exercising locality-oriented layouts,
and it has a clearer foundation for future topology changes.

## Main Changes

- Added typed `OrbeliasFilterBuilder` helpers for safer read filters without
  string-concatenated JSON.
- Added topology remapping primitives:
  - explicit arc tables
  - weighted arcs
  - deterministic virtual arcs
  - topology validation
  - `remapFraction`
- Added `docs/topology-remapping.md` to describe the boundary between remapping
  primitives and future online rebalance.
- Added locality validation workloads for random, delete-heavy, backfill-heavy,
  hot/cold, and interleaved write patterns.
- Added locality invariant checks: the same logical ring query must return the
  same ID/payload set before and after compaction while disk-span and candidate
  metrics are reported.
- Added CLI connection config loading with `--config=FILE` and `ORBELIAS_CONFIG`.
- Added `docs/use-case-recipes.md` with application recipes for list/detail,
  membership, inventory locks, webhook idempotency, SaaS tenant isolation,
  stellar neighborhoods, and RAG corpus layout.

## Why This Release Matters

OrbeliasDB's thesis is that meaningful placement should reduce unnecessary reads,
transfers, memory pressure, and downstream AI/RAG work. v0.6.0 strengthens the
engineering around that thesis in two ways.

First, locality is now easier to test as an invariant rather than only a
narrative. The demo workloads mutate, delete, backfill, compact, and re-read
the same logical rings, then report whether the result set stayed stable and
how the physical layout metrics changed.

Second, topology remapping now has explicit primitives. OrbeliasDB still does not
perform online dynamic membership or live rebalance in this release, but the
core can model ownership with arc tables and compare remapping behavior without
falling back to naive `mod nNodes` reasoning.

## Example

Connection config:

```json
{
  "peers": ["127.0.0.1:17301"],
  "galaxy": "docs",
  "user": "alice",
  "password": "secret",
  "tls": {
    "enabled": true,
    "ca": "certs/ca.pem",
    "cert": "certs/client.pem",
    "key": "certs/client-key.pem"
  }
}
```

Use it from the CLI:

```sh
orbelias --config=orbelias.json health

ORBELIAS_CONFIG=orbelias.json orbelias put \
  --ring=docs/japan \
  --payload='{"title":"Hello","status":"draft"}' \
  --codec=json

ORBELIAS_CONFIG=orbelias.json orbelias get \
  --ring=docs/japan \
  --filter='{"status":"draft"}' \
  --selection='{ title status }'
```

Run locality validation:

```sh
examples/locality_layout_demo.sh
```

The demo prints invariant and layout metrics such as:

```text
invariant ring=docs/topic/7 sameSet=true beforeCandidates=... afterCandidates=...
```

## Documentation

New and updated documents:

- `docs/topology-remapping.md`
- `docs/use-case-recipes.md`
- `docs/data-locality.md`
- `docs/config-reference.md`
- `docs/cli-reference.md`
- `docs/test-coverage.md`
- `docs/orbeliasdb-status.md`

## Verification

The local verification pass included:

- `nim check examples/locality_layout_demo.nim`
- `nim c -r --nimcache:/tmp/nimcache_orbelias_tstore tests/tstore.nim`
- `scripts/test_core.sh`
- `scripts/cli_crud_smoke.sh`
- `scripts/test_all_smoke.sh`
- `examples/locality_layout_demo.sh` workloads for random, delete-heavy,
  backfill-heavy, hot/cold, and interleaved cases during the feature branch
  verification cycle
- `git diff --check`

## Known Boundaries

- OrbeliasDB remains a technical preview / research OSS.
- Online dynamic membership and live rebalance are still planned, not complete.
- Cluster transaction coordinator redundancy is still planned.
- Universe sync remains a durable eventual-convergence primitive, not a
  consensus or quorum system.
- The next hardening track should focus on the audit items around C ABI failure
  handling, crash-safe compact/backup/restore, WAL integrity, sync ack safety,
  data-directory locking, and server resource limits.
