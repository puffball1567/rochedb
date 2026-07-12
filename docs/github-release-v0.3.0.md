# RocheDB v0.3.0 Technical Preview

RocheDB v0.3.0 expands the driver-facing and codec-aware read surface. The
notable change is C ABI v2 with `roche_read_ring_json`, which gives external
drivers a stable ring-read page shape similar to the CLI `roche get --ring=...`
workflow.

This is still a technical preview / research OSS release. Do not present it as
a production replacement for Redis, PostgreSQL, MongoDB, Apache Arrow, or a
mature vector database. The defensible claim remains narrower: RocheDB can
reduce working-set size and downstream retrieval input when data is placed in
meaningful rings, while the implementation is gaining the operational checks
needed for broader evaluation.

## Highlights

- C ABI v2 with `roche_read_ring_json` for JSON filters, optional projection,
  cursor/page reads, sorting, codec metadata, and stable page-shaped JSON
  responses.
- Unified ring-oriented CLI read behavior around one result shape for one or
  many records.
- Explicit CLI and documentation paths for JSON, NIF, BIF, raw, and
  ring-profile `--codec=auto` payload workflows.
- Expanded C ABI contract smoke coverage for JSON projection, NIF/BIF metadata,
  invalid filters, invalid sort fields, and null-ring errors.
- Expanded embedded API coverage for `readRing` filtering, pagination, sorting,
  defaulting, and codec-aware projection rejection.
- Expanded CLI smoke coverage for codec display, BIF base64/hex/adapter views,
  invalid filters, invalid sort fields, invalid projection requests, shell, and
  user-facing auth errors.
- Added `docs/test-coverage.md` to make the release validation matrix explicit.

## Validation Run

The v0.3.0 pre-release verification pass included:

- `scripts/test_core.sh`
- `scripts/cli_crud_smoke.sh`
- `scripts/test_all_smoke.sh`
- C ABI shared-library build
- `gcc examples/cabi_contract.c ...`
- `LD_LIBRARY_PATH=lib bin/cabi_contract`
- `nimble check`
- `git diff --check`

`scripts/test_all_smoke.sh` covers core tests, CLI CRUD, cluster transactions,
cluster failure, authz/RBAC, wire fuzz, recovery, universe sync failure, and
remote universe sync. Driver compatibility remains optional through
`ROCHE_TEST_DRIVERS=1`.

## Known Gaps

- TLS is not implemented; do not expose `roched` directly on untrusted
  networks.
- Cluster membership is static.
- node0 remains the cluster transaction landing coordinator.
- Cluster coordinator redundancy, dynamic membership, and epoch migration are
  not implemented.
- Universe sync is durable eventual sync, not immediate global serializability.
- Long-running cluster soak, mixed-version protocol, larger universe backlog,
  and multi-environment validation are expected to grow through external
  evaluation and reports.

## Links

- README: `README.md`
- Test coverage: `docs/test-coverage.md`
- Status / roadmap: `docs/rochedb-status.md`
- Public API: `docs/public-api.md`
- Configuration reference: `docs/config-reference.md`
- CLI reference: `docs/cli-reference.md`
- Payload codecs: `docs/payload-codecs.md`
- Universe sync: `docs/universe-sync.md`
- Topology examples: `docs/topology-examples.md`
- Benchmarks: `docs/rochedb-bench.md`
- Release checklist: `docs/release-checklist.md`
- Driver installation guide: `docs/driver-installation.md`
- Threat model: `docs/threat-model.md`
- Third-party notices: `THIRD_PARTY_NOTICES.md`

