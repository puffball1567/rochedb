# RocheDB v0.7.0

RocheDB v0.7.0 is a technical-preview release focused on hardening the storage,
wire, C ABI, TLS, and universe-sync paths while keeping RocheDB's scope honest:
it is still not presented as a production replacement for Redis, PostgreSQL,
MongoDB, Apache Arrow, or dedicated vector databases.

Release:

https://github.com/puffball1567/rochedb/releases/tag/v0.7.0

The main goal of this release is to reduce the number of silent-failure paths
around persistence, driver-facing builds, sync acknowledgements, and operational
misconfiguration. It also expands the runnable demo and smoke matrix so
RocheDB's locality model can be checked with more than happy-path examples.

## Main Changes

- Added `scripts/build_capi.sh` as the canonical C ABI shared-library build
  path. It builds with `--app:lib -d:ssl -d:release`.
- Updated driver installation docs and compatibility scripts to use the
  canonical C ABI build path.
- Added C ABI TLS smoke coverage.
- Added Linux and macOS CI coverage for the C ABI build path.
- Enabled `--panics:on` so internal Defects do not become false success values
  through C ABI calls.
- Added persistent data-directory locking to prevent two processes from
  opening the same store and corrupting transaction identity.
- Hardened universe sync acknowledgement handling, retry accounting,
  dead-letter handling, remote sync recovery, and idempotent replay.
- Added bounded applied-event dedup persistence for universe sync.
- Added server-side retrieve budget and scan guards for safer broad queries.
- Added lock fencing-token persistence for ring and stellar locks.
- Added `docs/data-migration.md` for JSONL dump/import as the main pre-v1
  compatibility boundary.
- Added `docs/time-orbit.md` for calculated time-bucket placement.
- Added `scripts/demo_smoke.sh` to exercise stellar, codec, and locality demos.
- Added cluster wire driver smoke coverage to the full smoke suite.

## Why This Release Matters

RocheDB's main bet is that meaningful placement can reduce unnecessary reads,
transfers, memory pressure, and downstream AI/RAG work. v0.7.0 does not change
that thesis; it makes the implementation more trustworthy around the boring
parts that matter for databases:

- storage must fail closed when a directory is already open elsewhere
- C ABI callers must not see false success after internal Defects
- TLS-capable driver builds need one canonical command
- universe sync must not prune events unless the target actually accepted them
- broad reads need explicit limits and diagnostics
- demo and smoke scripts must keep proving that core workflows still run

## Example: C ABI Build

```sh
scripts/build_capi.sh
```

The script writes the shared library to `build/capi/` and is the recommended
path for Rust, JavaScript / TypeScript, PHP, C++, Swift, Kotlin, Go, and C#
driver work.

## Example: Full Smoke

```sh
scripts/test_all_smoke.sh
```

The all-smoke suite now includes:

- core tests
- CLI CRUD smoke
- cluster transaction and failure recovery smoke
- authz / RBAC smoke
- driver wire-protocol smoke
- wire fuzz smoke
- TLS smoke
- recovery smoke
- universe sync failure and remote sync smoke
- demo smoke

## Documentation

New and updated documents include:

- `docs/audit-remediation.md`
- `docs/data-migration.md`
- `docs/time-orbit.md`
- `docs/driver-installation.md`
- `docs/protocol-compatibility.md`
- `docs/tls-transport.md`
- `docs/threat-model.md`
- `docs/query-safety.md`
- `docs/public-api.md`
- `docs/test-coverage.md`
- `docs/release-checklist.md`
- `docs/rochedb-status.md`

## Verification

The local release verification pass included:

- `scripts/test_all_smoke.sh`
- `nimble check`

`scripts/test_all_smoke.sh` includes the expanded cluster, TLS, recovery,
universe-sync, codec, stellar, and locality demo checks listed above.

## Known Boundaries

- RocheDB remains a technical preview / research OSS.
- Online dynamic membership and live rebalance are still planned, not complete.
- Cluster transaction coordinator redundancy is still planned.
- Universe sync remains a durable eventual-convergence primitive, not a
  consensus or quorum system.
- JSONL dump/import is the recommended compatibility boundary before v1.0.
- External driver packages may lag the core C ABI surface and should be checked
  against their own package release notes.
