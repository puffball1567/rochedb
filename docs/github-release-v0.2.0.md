# RocheDB v0.2.0 Technical Preview

RocheDB v0.2.0 expands the ring/galaxy-oriented prototype with a stronger
operational surface: Universe sync, recovery-oriented topology configuration,
Docker Compose demos, CLI workflows, and GitHub Pages documentation.

This is still a technical preview / research OSS release. Do not present it as
a production replacement for Redis, PostgreSQL, MongoDB, Apache Arrow, or a
mature vector database. The defensible claim remains narrower: RocheDB can
reduce working-set size and downstream retrieval input when data is placed in
meaningful rings, while the implementation is gaining the operational checks
needed for broader evaluation.

## Highlights

- Universe sync outbox with WAL-backed events, idempotent apply, ack/prune,
  local data-dir sync, and remote `--peers` delivery through `UAPPLY`.
- Remote sync observability through `universe-status --peers --metrics`.
- Restart and duplicate-delivery smoke coverage for remote universe sync.
- Recovery topology configuration using `universes`, `galaxies`, local/remote
  archive placement, auth references, priorities, snapshot sequence checks, and
  readonly mirrors.
- Docker Compose demos for a single galaxy, a three-node galaxy, and a
  local/remote universe-shaped topology.
- `bin/roche` CLI CRUD workflows, ring list/count, atlas, and a minimal
  interactive shell.
- GitHub Pages documentation structure with public API, config, CLI, topology,
  universe sync, protocol compatibility, cloud metrics, and threat model pages.
- Wire/client errors now surface as user-facing CLI errors instead of assertion
  defects for normal operational failures such as failed authentication.

## Validation Run

The v0.2 pre-release verification pass should include:

- `scripts/test_core.sh`
- `scripts/test_all_smoke.sh`
- `scripts/cli_crud_smoke.sh`
- `scripts/universe_sync_failure_smoke.sh`
- `scripts/universe_sync_remote_smoke.sh`
- Docker Compose demo checks in `examples/compose/README.md`
- `nimble check`
- Markdown link checks for README and docs

## Known Gaps

- TLS is not implemented; do not expose `roched` directly on untrusted
  networks.
- Cluster membership is static.
- node0 remains the cluster transaction landing coordinator.
- Cluster coordinator redundancy, dynamic membership, and epoch migration are
  not implemented.
- Universe sync is durable eventual sync, not immediate global serializability.
- Server-side warp scheduling is not implemented.
- Package publication workflows are not complete.
- WASM browser support, React Native local-state support, Unity assets, Unreal
  plugins, Kubernetes manifests, and multi-VM / multi-AZ benchmarks are later
  roadmap items.

## Links

- README: `README.md`
- Status / roadmap: `docs/rochedb-status.md`
- Public API: `docs/public-api.md`
- Configuration reference: `docs/config-reference.md`
- CLI reference: `docs/cli-reference.md`
- Universe sync: `docs/universe-sync.md`
- Topology examples: `docs/topology-examples.md`
- Benchmarks: `docs/rochedb-bench.md`
- Release checklist: `docs/release-checklist.md`
- Driver installation guide: `docs/driver-installation.md`
- Threat model: `docs/threat-model.md`
- Third-party notices: `THIRD_PARTY_NOTICES.md`
