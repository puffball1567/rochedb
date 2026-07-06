# Changelog

## v0.1.0 Technical Preview

Initial public technical preview target.

### Added

- Embedded RocheDB API with memory-only and WAL-backed `open(dataDir=...)`
  modes.
- Ring / galaxy data model, ring hierarchy, galaxy and ring descriptions, and
  atlas output for LLM / agent navigation.
- `put`, `get`, `query`, `locate`, `retrieve`, `batchGet`, `listByRing`,
  `countByRing`, `update`, `patch`, and `deleteById` foundations.
- Append-only WAL with replay repair for torn tails and invalid record tails.
- Embedded atomic transactions and strong durability mode.
- Compact, backup / restore, encrypted backup / restore, dump, and JSONL import.
- Cluster PoC with static peer lists, deterministic locate, landing-intent
  transactions, owner crash/restart retry smoke, and read-your-writes fallback.
- Username/password authentication, secret-key gate, ring-prefix authorization,
  and minimal reader / writer / admin RBAC.
- Wire protocol hardening for malformed and oversized frames.
- Warp belt PoC: WAL-backed delayed patch queue with progress, retry state,
  ack, dead-letter state, cleanup, and idempotent patch behavior.
- Vector retrieval with exact backend and optional FAISS dynamic bridge.
- C ABI plus minimal Python, Node.js / TypeScript / Bun, Rust, Go, PHP, Swift,
  C#, C++, and Kotlin/JVM driver or wrapper foundations.
- Benchmark records for mechanism cost, cluster TCP, PostgreSQL reference,
  Redis smoke, working-set reduction, memory-pressure reduction, and RAG-style
  synthetic retrieval.
- Threat model, third-party notices, driver roadmap, release checklist, and
  Flow-series integration policy.

### Known Gaps

- TLS is not implemented; do not expose `roched` directly on untrusted networks.
- Cluster membership is static, and node0 remains the landing coordinator.
- Cluster coordinator redundancy and epoch migration are not implemented.
- Server-side warp scheduling is not implemented.
- FAISS GPU backend is not planned for core.
- WASM / browser local-state support is planned for a later release.
- FlowBrigade / FlowLogbook adapters are post-v0.1 roadmap items rather than
  core v0.1.0 scope.
- Package publishing workflows are not complete.

### Positioning

RocheDB v0.1.0 should be described as a technical preview / research OSS
release. Do not claim general replacement status for Redis, PostgreSQL,
MongoDB, or Apache Arrow. The current defensible claim is that RocheDB can
reduce working-set size under documented synthetic conditions while local and
TCP read paths are being moved toward existing database speed bands.
