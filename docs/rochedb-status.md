# RocheDB Status / Roadmap

This is the canonical English status document. Translations are secondary
references and may lag behind this file.

Release checklist: [release-checklist.md](./release-checklist.md)

Translations:

- Japanese: [rochedb-status.ja.md](./rochedb-status.ja.md)
- German: [rochedb-status.de.md](./rochedb-status.de.md)
- French: [rochedb-status.fr.md](./rochedb-status.fr.md)
- Chinese: [rochedb-status.zh.md](./rochedb-status.zh.md)
- Korean: [rochedb-status.ko.md](./rochedb-status.ko.md)

## Core DB

| Feature | Status | Notes |
|---|---|---|
| Embedded DB | Done | `open(dataDir=...)` and memory-only mode |
| put / get | Done | Ring-scoped writes and ID-based reads |
| ORM foundation API | Done | Embedded APIs plus cluster PoC for `update`, JSON `patch`, `deleteById`, `listByRing`, `countByRing`; canonical data is expected to live in one galaxy/ring, with alternate views handled by ring hierarchy, naming, import rules, and retrieval profiles; driver exposure is still pending |
| Warp belt | PoC | WAL-backed delayed patch queue: `enqueueWarp`, `warpStep`, `warpDrain`; scans specified rings in registration order and drops merge patches onto matching JSON documents; includes minimal attempts / retryAt / maxAttempts / ack / dead-letter state plus acked-job cleanup; FlowBrigade and FlowLogbook adapters are planned instead of core dependencies; server scheduling is still pending |
| JSON document query | Done | GraphQL-style selection |
| Vector retrieve | Done | FAISS bridge is the intended production vector path. Exact backend remains for small datasets, tests, and fallback |
| Ring / hierarchy | Done | `ring = "a/b/c"` and child-ring expansion |
| Galaxy isolation | Done | Separate data dir / peer list / credential boundary |
| Atlas / ring map | Done | `atlas()` and `roche atlas` |
| Galaxy/ring description | Done | Atlas map annotations, not payload text |
| Retrieval tuning profile | Done | amount / scope / depth |
| FAISS vector backend | PoC | Dynamic bridge via `libroche_faiss.so`; default fetch tag is FAISS `v1.14.3`, exact commit pinning is optional via `ROCHE_FAISS_COMMIT`; `roche doctor`, bridge build, `tests/tapi.nim`, and `examples/vector_backend_bench.sh` are verified locally |
| FAISS GPU backend | Not planned for core | RocheDB is designed to reduce the search set before ANN/LLM work. Needing GPU FAISS is treated as a placement or retrieval-profile issue first |
| Retrieval planner | PoC | Deterministic heuristic planner. Stronger planner claims require larger real-corpus benchmarks and further tuning |
| WASM browser embedded | Post-v0.1 candidate | Browser state boundary / IndexedDB / OPFS |

## Persistence / Operations

| Feature | Status | Notes |
|---|---|---|
| Append-only WAL | Done | Batched flush by default; `durStrong` / `--durability=strong` adds flush + fsync write boundaries |
| Reopen recovery | Done | Items / vectors / ring metadata / descriptions |
| Transaction | Done | Embedded atomic transaction |
| Cluster transaction landing | PoC | node0 landing. `scripts/cluster_tx_smoke.sh` covers apply smoke; `scripts/cluster_failure_smoke.sh` covers owner crash/restart retry; redundancy is not implemented yet |
| Cluster CRUD/list/count | PoC | `update`, `deleteById`, JSON `patch`, `listByRing`, `countByRing` use landing intents or node fan-out; `scripts/cluster_tx_smoke.sh` covers smoke |
| Compact | Done | Rebuilds WAL from live records |
| Backup / restore | Done | Backup as compacted WAL and restore into another data dir |
| Dump / import-jsonl | Done | NoSQL JSONL import rules |
| Universe sync outbox | PoC | WAL-backed eventual sync event queue with idempotent apply, ack/prune, `putSynced`, latest-only pending coalescing, delayed timestamp apply windows, `roche universe-export` / `universe-apply` JSONL handoff, one-shot `roche universe-sync` between local data dirs, remote `--peers` delivery via `UAPPLY`, and `universe-status` operational counters. It is a durable scheduler boundary, not immediate global consistency |
| Crash recovery tests | Partial | Torn WAL tail repair, compact interruption, partial commit cases |
| Strong durability / fsync knob | Done | `open(dataDir=..., durability=durStrong)` and `roched --durability=strong`; store/API tests cover reopen, transaction, compact |
| Core test suite | Done | `scripts/test_core.sh` runs orbital core, selection, field, store, and public API tests |
| Full smoke suite | Done | `scripts/test_all_smoke.sh` runs core tests plus cluster tx, failure retry, authz, wire fuzz, recovery, and remote universe sync smoke; driver compatibility is opt-in |
| Generation snapshot / checkpoint | Planned | Generational snapshot and checkpoint are pending; encrypted backup is available |
| Kubernetes manifests | Planned | liveness/readiness, PVC, rolling restart |

## Cluster / Network

| Feature | Status | Notes |
|---|---|---|
| Static cluster | Done | `roched --id --peers` |
| Deterministic locate | Done | `E(id,t) -> node` |
| Handoff / forwarder | PoC | Slow tick integration exists. Fully distributed forwarder placement is not done |
| Driver-friendly wire | Done | `PUTR/GETID/QRYID`; `WIREVER` exposes the current protocol version. Compatibility policy is documented in `docs/protocol-compatibility.md` |
| Health / metrics / rings | Done | CLI and wire protocol; metrics include uptime, request/error/auth counters, connection counts, WAL bytes, warp backlog, universe apply counters, cluster tx backlog, and storage/ring counts |
| Authn + secret key | Done | username/password/secret-key |
| TLS | Planned | Required for public-network deployments |
| Authz / RBAC | PoC | `roched --allow-ring=prefix[,prefix...]` and `--role=user:password:reader|writer|admin[:prefixes]`; `scripts/cluster_authz_smoke.sh` and `scripts/cluster_rbac_smoke.sh` cover prefix and role matrix behavior |
| Wire fuzz smoke | Done | `scripts/cluster_wire_fuzz_smoke.sh` runs deterministic malformed-frame cases, including oversized headers, and verifies the cluster stays healthy |
| Dynamic membership / epoch migration | Planned | Current peer list is static |
| Cluster transaction coordinator redundancy | Planned | Remove node0 as a single point of failure |
| Read-your-writes for cluster tx | PoC | `get/query/batchGet` fallback to node0 landing intent before owner apply; cluster smoke covers update/delete |
| Fault-tolerance improvements | Planned | Post-v0.1 work; universe sync outbox is now the first durable eventual-convergence primitive |
| Multi-VM / multi-AZ benchmark | Planned | Real-world latency and failure behavior |

## Drivers / Bindings

| Target | Status | Notes |
|---|---|---|
| Nim API | Done | Native public API |
| C ABI | Done | ABI version / last error / put/get/retrieve/batch/atlas; C ABI vectors are host-native float arrays, while TCP wire vectors are canonical little-endian float32 |
| Python | Done | Native wire minimal |
| JavaScript / TypeScript | Published | npm [`rochedb` v0.1.2](https://www.npmjs.com/package/rochedb); repository [`puffball1567/rochedb-js`](https://github.com/puffball1567/rochedb-js); Node-API C ABI wrapper with TypeScript API |
| Bun | Partial | The npm package uses Node-API and includes Bun compatibility verification, but Bun support remains experimental |
| Rust | Published | crates.io [`rochedb` v0.1.3](https://crates.io/crates/rochedb); repository [`puffball1567/rochedb-rust`](https://github.com/puffball1567/rochedb-rust); C ABI wrapper |
| Go | Done | C ABI wrapper minimal |
| PHP | Published | Packagist [`rochedb/rochedb` v0.1.1](https://packagist.org/packages/rochedb/rochedb); repository [`puffball1567/rochedb-php`](https://github.com/puffball1567/rochedb-php); FFI / C ABI wrapper with Docker smoke |
| Swift | Done | SwiftPM C ABI wrapper with Linux Docker smoke |
| C# minimal | Done | OSS generic C# wrapper. Unity official asset is separate |
| C++ minimal | Done | OSS generic C++ wrapper. Unreal official plugin is separate |
| Kotlin-first JVM | Done | JNI / C ABI wrapper with Docker smoke |
| React Native / WASM local state | Post-v0.1 candidate | Browser / React Native state boundary; handled with the WASM line, not before Kotlin |
| Driver discovery CLI | Done | `roche driver list/info/install` prints official driver metadata and setup commands without executing remote scripts |
| Driver compatibility test suite | Partial | `scripts/driver_compat.sh`; Docker-backed PHP / Swift / Kotlin are opt-in and verified |
| Package publishing | Partial | `nimble install rochedb`, `cargo add rochedb`, `npm install rochedb`, and `composer require rochedb/rochedb` are available. PyPI, NuGet, Maven, Go, SwiftPM, and other registry packages remain future work |

## Benchmarks / Demos

| Item | Status | Notes |
|---|---|---|
| Working-set bench | Done | scanned/query reduction |
| Memory-pressure bench | Done | estimated candidate memory/query |
| RAG-style bench | Done | recall retained while tokens/query are reduced |
| AI/RAG JSONL case study | Done | `examples/ai_rag_case_study.sh` generates a deterministic multi-ring JSONL corpus, imports it, and compares global / routed / wrong-ring retrieval |
| PostgreSQL comparison | Done | Limited reference comparison |
| Redis comparison | Done | Smoke test with conditions and limits documented |
| C ABI bench | Done | `examples/cbench.c` |
| Docker case study | Partial | memory pressure / PHP / Swift smoke |
| Cluster transaction smoke | Partial | `scripts/cluster_tx_smoke.sh` starts 3 local nodes and verifies apply / retrieve |
| Cluster failure retry smoke | Partial | `scripts/cluster_failure_smoke.sh` kills the owner node, verifies the intent remains pending, restarts the owner, and verifies retry apply |
| Universe sync demo | Done | `examples/universe_sync_demo.sh` builds a small source/target pair, demonstrates API-level sync, then demonstrates the CLI export/sync/prune boundary. `scripts/universe_sync_failure_smoke.sh` verifies malformed JSONL handling, replay idempotency, and explicit ack/prune. `scripts/universe_sync_remote_smoke.sh` verifies remote `--peers` delivery and target-down retry behavior |
| Crash / failure case study | Partial | Store-level WAL tail repair, compact interruption, partial commit, and cluster owner crash/restart retry are covered |
| Multi-node cloud case study | Planned | VM/AZ, latency, failover behavior |
| Prometheus / Datadog exporter | Post-v0.1 candidate | Core exposes key/value metrics now; OpenMetrics / Datadog collector should be added outside the core server loop |
| State boundary demo | Post-v0.1 candidate | browser/RN local-global state demo |

## Security / Safety

| Item | Status | Notes |
|---|---|---|
| Username/password auth | Done | roched and driver path |
| Secret key gate | Done | ID/password alone can be insufficient |
| nimsodium encryption primitive | Partial | Used for auth transport; scope may expand |
| Galaxy isolation | Done | Limits blast radius by galaxy |
| TLS | Planned | Required for public-network deployments |
| Ring/galaxy authz | PoC | Ring prefix authorization is implemented for named-ring wire operations; richer role policy is pending |
| Backup encryption | Done | `backupEncrypted` / `restoreEncryptedBackup` and `roche backup-encrypted` / `restore-encrypted` use nimsodium secretbox |
| General audit log | Planned | Full append-only access/change audit for enterprise / regulated workloads. Warp jobs already persist attempts / retryAt / ack / dead-letter state, but that is job state, not a database-wide audit log |
| Threat model document | Draft | `docs/threat-model.md` covers assets, trust boundaries, current controls, and known gaps |

## Post-v0.1 Roadmap Candidates

These are candidates for v0.2 and later releases. They are not all scoped to a
single v0.2.0 milestone.

- WASM browser embedded
- IndexedDB / OPFS persistence
- React hooks / browser state boundary
- React Native / WASM local state module
- Unity official asset
- Unreal official plugin
- package publishing workflows for remaining language drivers
- API reference documentation
- Prometheus / OpenMetrics and Datadog metrics adapters
- Fault-tolerance improvements

## Managed Service Readiness Gaps

RocheDB should be able to become a managed service in the same operational
category as hosted cache, document, search, or AI-context databases. Some
managed-service requirements are already expressible through RocheDB concepts:
replication-style redundancy maps to universes, logical isolation maps to
galaxies, read scope maps to rings, and backup verification maps to recovery
universes.

The following items are the remaining implementation candidates that are not
fully covered by the current concepts or code:

| Candidate | Why it is needed |
|---|---|
| Durable eventual universe sync | Universes currently cover recovery topology. A managed service also needs live delayed convergence between same-name galaxies across universes without global commit waits. |
| Ring apply policy | Managed deployments need per-ring behavior such as latest-only, append-only, bounded-history, and delayed timestamp apply. This keeps consistency rules explicit without making the whole DB strongly serializable. |
| Read-your-writes across local pending state | Local users should not feel universe-sync delay. The cluster landing-intent fallback is a start; universe-level pending overlays are still missing. |
| Dynamic node replacement | Managed services must replace failed or upgraded nodes without manual peer-list surgery. Current clusters use static peers. |
| Cluster coordinator redundancy | Node0 is currently the transaction landing zone. Managed service readiness needs the coordinator role to survive node replacement or failover. |
| TLS and certificate rotation | Username/password/secret-key auth exists, but managed public or VPC deployments need transport TLS and rotation workflows. |
| Secret rotation | `authProfiles` reference external secrets, but the server and drivers need an explicit rotation story for username/password/secret-key credentials. |
| Point-in-time recovery / generation checkpoints | Backup/restore exists. Managed services normally require recoverable generations, restore-point selection, and verification before promotion. |
| Drain / quiesce / snapshot barrier | Rolling maintenance and consistent managed backups need a control-plane hook to stop accepting new writes, flush durable state, and report readiness. |
| OpenMetrics / CloudWatch / Datadog adapters | RocheDB exposes key/value metrics, but managed integrations need standard exporters or collectors. |
| Quotas and capacity guardrails | Galaxy isolation exists, but managed multi-tenant operation needs limits for WAL bytes, item count, ring count, payload size, and connection pressure. |
| Protocol / storage compatibility policy | Managed upgrades need clear compatibility rules for wire protocol, WAL records, snapshots, and drivers. |

These gaps define the boundary between a promising server database and a
provider-ready managed database. RocheDB should not copy every Redis, RDS, or
ElastiCache mechanism one-to-one; it should provide equivalent operational
outcomes where RocheDB's universe / galaxy / ring model already gives a simpler
or more natural shape.
