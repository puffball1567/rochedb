# RocheDB 상태 / 로드맵

이 문서는 참고 번역입니다. 영어 문서 [rochedb-status.md](./rochedb-status.md)가
정본이며, 이 번역은 늦게 반영될 수 있습니다.

Release checklist: [release-checklist.md](./release-checklist.md)

## Core DB

| Feature | Status | Notes |
|---|---|---|
| Embedded DB | Done | `open(dataDir=...)` and memory-only mode |
| put / get | Done | Ring-scoped writes and ID-based reads |
| ORM foundation API | Done | Foundation for `update`, JSON `patch`, `deleteById`, `listByRing`, `countByRing`; driver exposure is still pending |
| Warp belt | PoC | WAL-backed delayed patch queue with minimal retry / ack / dead-letter state |
| JSON document query | Done | GraphQL-style selection |
| Vector retrieve | Done | FAISS bridge is the intended production path; exact backend remains for tests and fallback |
| Ring / hierarchy | Done | `ring = "a/b/c"` and child-ring expansion |
| Galaxy isolation | Done | Separate data dir / peer list / credential boundary |
| Atlas / ring map | Done | `atlas()` and `roche atlas` |
| Retrieval tuning profile | Done | amount / scope / depth |
| FAISS vector backend | PoC | Dynamic bridge via `libroche_faiss.so`; default fetch tag is FAISS `v1.14.3`; exact commit pinning is optional via `ROCHE_FAISS_COMMIT` |
| WASM browser embedded | Post-v0.1 candidate | Browser state boundary / IndexedDB / OPFS |

## Persistence / Operations

| Feature | Status | Notes |
|---|---|---|
| Append-only WAL | Done | Batched flush by default; strong durability adds flush + fsync |
| Reopen recovery | Done | Items / vectors / ring metadata / descriptions |
| Transaction | Done | Embedded atomic transaction |
| Cluster transaction landing | PoC | node0 landing with failure retry smoke |
| Compact | Done | Rebuilds WAL from live records |
| Backup / restore | Done | Backup as compacted WAL and restore into another data dir |
| Dump / import-jsonl | Done | NoSQL JSONL import rules |
| Crash recovery tests | Partial | Torn WAL tail, compact interruption, partial commit |
| Core test suite | Done | `scripts/test_core.sh` |
| Full smoke suite | Done | `scripts/test_all_smoke.sh` |
| Kubernetes manifests | Planned | liveness/readiness, PVC, rolling restart |

## Cluster / Network

| Feature | Status | Notes |
|---|---|---|
| Static cluster | Done | `roched --id --peers` |
| Deterministic locate | Done | `E(id,t) -> node` |
| Handoff / forwarder | PoC | Slow tick integration exists |
| Driver-friendly wire | Done | `PUTR/GETID/QRYID` |
| Authn + secret key | Done | username/password/secret-key |
| Authz / RBAC | PoC | Ring prefix authz and role matrix smoke |
| Wire fuzz smoke | Done | Malformed frame cases |
| Dynamic membership | Planned | Current peer list is static |
| TLS | Planned | Required for public-network deployments |

## Drivers / Bindings

| Target | Status | Notes |
|---|---|---|
| Nim API | Done | Native public API |
| C ABI | Done | ABI version / last error / put/get/retrieve/batch/atlas |
| Python | Done | Native wire minimal |
| Node.js / TypeScript / Bun | Done | ESM native wire minimal |
| Rust / Go | Done | C ABI wrapper minimal |
| PHP / Swift / Kotlin | Done | Docker smoke available |
| C# / C++ | Done | OSS generic wrappers; Unity / Unreal official assets are separate candidates |
| React Native / WASM | Post-v0.1 candidate | Browser / local state boundary |
| Nimble package publishing | Done | `nimble install rochedb` is available. Non-Nim registries remain future work |

## Benchmarks / Demos

| Item | Status | Notes |
|---|---|---|
| Working-set bench | Done | scanned/query reduction |
| Memory-pressure bench | Done | candidate memory/query |
| RAG-style bench | Done | recall retained while tokens/query are reduced |
| AI/RAG JSONL case study | Done | deterministic multi-ring JSONL corpus |
| PostgreSQL / Redis comparison | Done | documented smoke/reference measurements |
| Cluster failure retry smoke | Partial | owner kill/restart retry |
| Multi-node cloud case study | Planned | VM/AZ, latency, failover |

## Security / Safety

| Item | Status | Notes |
|---|---|---|
| Username/password auth | Done | roched and driver path |
| Secret key gate | Done | ID/password alone can be insufficient |
| nimsodium encryption primitive | Partial | auth transport; scope may expand |
| Galaxy isolation | Done | limits blast radius by galaxy |
| Backup encryption | Done | nimsodium secretbox |
| Threat model | Draft | [threat-model.md](./threat-model.md) |

## v0.1 이후 로드맵 후보

이 항목들은 v0.2 및 이후 릴리스의 후보이며, 모두 단일 v0.2.0 범위라는 뜻은 아닙니다.

- WASM browser embedded
- IndexedDB / OPFS persistence
- React hooks / browser state boundary
- React Native / WASM local state module
- Unity official asset
- Unreal official plugin
- package publishing workflows for language drivers
