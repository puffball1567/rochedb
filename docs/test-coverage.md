# Test Coverage

This document tracks RocheDB's test coverage by product surface. It is not a
claim of exhaustive production certification; it is the current engineering
matrix used before releases.

## Coverage Matrix

| Area | Primary checks | Current status |
| --- | --- | --- |
| Orbital placement core | `tests/tcore.nim` | Unit-covered: angle wrapping, ownership, future arrival, conjunctions |
| Field / halo movement | `tests/tfield.nim` | Unit-covered: field state and ring movement behavior |
| Selection parser | `tests/tselect.nim` | Unit-covered: GraphQL-like selection parsing and projection basics |
| Store / WAL | `tests/tstore.nim` | Unit-covered: codec persistence, torn-tail repair, transaction replay, compact, backup/restore |
| Public embedded API | `tests/tapi.nim` | Unit-covered: put/get, codec-aware projection, ring profiles, readRing filtering, pagination, sorting, warp, universe sync |
| CLI embedded usage | `scripts/cli_crud_smoke.sh` | Smoke-covered: help, put/get/query/list/count, readRing options, codec display, ring profile auto codec, shell, auth error text |
| C ABI | `examples/cabi_contract.c`, `scripts/driver_compat.sh` | Contract-covered: ABI version, put/get, codec metadata, read ring page shape, validation errors, atlas |
| Wire protocol | `tests/twire_driver.nim`, `scripts/cluster_wire_fuzz_smoke.sh` | Smoke-covered: driver-facing PUTR/GETID/QRYID, codec metadata negotiation, malformed frame behavior |
| Cluster transactions | `tests/tcluster_tx.nim`, `scripts/cluster_tx_smoke.sh` | Smoke-covered: landing intent, apply retry, basic owner failure path |
| Cluster auth / RBAC | `tests/tcluster_authz.nim`, `tests/tcluster_rbac.nim`, related scripts | Smoke-covered: username/password/secret key and role/ring-prefix authorization |
| Cluster failure | `tests/tcluster_failure.nim`, `scripts/cluster_failure_smoke.sh` | Smoke-covered: owner restart and retry boundaries |
| Universe sync | `examples/universe_sync_demo.nim`, `scripts/universe_sync_*_smoke.sh` | Smoke-covered: local export/apply, remote apply, idempotency, malformed JSONL handling |
| Recovery | `scripts/recovery_smoke.sh` | Smoke-covered: backup/restore and recovery status paths |
| Driver compatibility | `scripts/driver_compat.sh` | Optional smoke: C, C++, and published driver-facing C ABI paths when enabled |

## Release Gate

For a normal core release, run:

```sh
scripts/test_core.sh
scripts/cli_crud_smoke.sh
scripts/cluster_tx_smoke.sh
scripts/cluster_failure_smoke.sh
scripts/cluster_authz_smoke.sh
scripts/cluster_rbac_smoke.sh
scripts/cluster_wire_fuzz_smoke.sh
scripts/recovery_smoke.sh
scripts/universe_sync_failure_smoke.sh
scripts/universe_sync_remote_smoke.sh
```

`scripts/test_all_smoke.sh` runs the same sequence and skips driver
compatibility by default. Set `ROCHE_TEST_DRIVERS=1` when the local driver
toolchains are available.

## Remaining Depth Targets

The following areas are intentionally tracked as deeper follow-up work rather
than hidden assumptions:

- long-running cluster soak tests with node restarts during active traffic;
- mixed-version wire protocol compatibility tests;
- TLS deployment tests once transport TLS is added;
- larger universe sync replay and backlog-pressure tests;
- driver matrix CI across all published language repositories.

