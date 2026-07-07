# RocheDB v0.1.0 Technical Preview

RocheDB v0.1.0 is the first public technical preview of a ring/galaxy-oriented
document and vector database prototype focused on reducing working-set size for
retrieval-heavy systems.

This is a research OSS release, not a production replacement claim for Redis,
PostgreSQL, MongoDB, Apache Arrow, or a mature vector database. The useful claim
for this release is narrower: RocheDB can route reads through explicit rings and
retrieval plans so fewer candidates are scanned and fewer chunks/tokens need to
reach downstream RAG or application logic under the documented benchmark
conditions.

## Highlights

- Embedded memory-only and WAL-backed `open(dataDir=...)` modes.
- Ring / galaxy model with hierarchy, descriptions, and atlas output.
- Document operations: `put`, `get`, `query`, `batchGet`, `listByRing`,
  `countByRing`, `update`, `patch`, and `deleteById` foundations.
- Vector retrieval with exact backend and optional FAISS dynamic bridge.
- Append-only WAL, replay repair, strong durability option, compact,
  backup/restore, encrypted backup/restore, dump, and JSONL import.
- Embedded atomic transactions and cluster landing-intent transaction PoC.
- Static cluster smoke with deterministic locate, owner crash/restart retry,
  read-your-writes fallback, authz/RBAC smoke, and wire fuzz smoke.
- Username/password auth, secret-key gate, ring-prefix authorization, and
  minimal reader/writer/admin roles.
- Warp belt PoC: WAL-backed delayed patch queue with retry, ack, cleanup, and
  dead-letter state.
- C ABI plus minimal driver/wrapper foundations for Nim, Python, Node.js,
  TypeScript, Bun, Rust, Go, PHP, Swift, C#, C++, and Kotlin/JVM.
- Benchmark notes covering mechanism cost, PostgreSQL reference, Redis smoke,
  working-set reduction, memory-pressure reduction, and RAG-style retrieval.

## Validation Run

The pre-release verification pass covered:

- `scripts/test_core.sh`
- `scripts/test_all_smoke.sh`
- `scripts/driver_compat.sh`
- Docker-backed PHP / Swift / Kotlin driver smoke
- `examples/ai_rag_case_study.sh`
- `roche doctor` for the FAISS bridge

## Known Gaps

- TLS is not implemented; do not expose `roched` directly on untrusted networks.
- Cluster membership is static.
- node0 remains the cluster transaction landing coordinator.
- Cluster coordinator redundancy and epoch migration are not implemented.
- Server-side warp scheduling is not implemented.
- Package publication to npm / PyPI / Cargo / Go / Composer / SwiftPM / NuGet /
  Maven is a post-v0.1 roadmap item.
- WASM browser support, React Native local-state support, Unity assets, Unreal
  plugins, Kubernetes manifests, and multi-VM / multi-AZ benchmarks are
  post-v0.1 roadmap items.

## Links

- README: `README.md`
- Status / roadmap: `docs/rochedb-status.md`
- Benchmarks: `docs/rochedb-bench.md`
- Release checklist: `docs/release-checklist.md`
- Driver installation guide: `docs/driver-installation.md`
- Threat model: `docs/threat-model.md`
- Third-party notices: `THIRD_PARTY_NOTICES.md`
