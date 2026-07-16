# Changelog

## v0.6.0 - Unreleased

### Added

- Added typed `RocheFilterBuilder` helpers for safer read filters without
  string-concatenated JSON.
- Added locality validation workloads for interleaved, random, delete-heavy,
  backfill-heavy, and hot/cold write patterns, including compact-before/after
  read micro-samples.
- Added topology remapping primitives: explicit arc tables, weighted arcs,
  deterministic virtual arcs, topology validation, and `remapFraction`.
- Added `docs/topology-remapping.md` to explain the boundary between remapping
  primitives and future online rebalance.
- Added `docs/use-case-recipes.md` with application recipes for list/detail,
  membership, inventory locks, webhook idempotency, SaaS tenant isolation,
  stellar neighborhoods, and RAG corpus layout.
- Added CLI connection config loading with `--config=FILE` and `ROCHE_CONFIG`.
  Config can provide peers, auth, galaxy, and TLS defaults while command-line
  flags remain the override.

### Changed

- Updated technical FAQ and status documents to reflect that arc-table based
  remapping has a foundation, while live dynamic membership remains future
  work.
- Expanded CLI and configuration documentation for cluster/TLS connection
  defaults.

### Fixed / Hardened

- Expanded CLI smoke coverage to verify config-driven cluster health, put, and
  get workflows.
- Expanded core tests for explicit arc ownership, weighted arcs, virtual arc
  remap reduction, and malformed topology rejection.

## v0.5.0

### Added

- Added stellar locality lens workflows. Existing rings can be attached to or
  detached from a stellar coordinate, allowing related records to be read
  together without copying payloads.
- Added `readStellar` / `roche get --stellar=...` workflows with `--subring`,
  filter, selection, and grouped ring output.
- Added embedded all-or-nothing bulk helpers:
  `batchPutAtomic`, `batchUpdateAtomic`, and `batchDeleteAtomic`.
- Added opt-in embedded cooperative coordinate locks:
  `acquireRingLock`, `acquireStellarLock`, `withRingLock`,
  `withStellarLock`, `releaseLock`, and `lockActive`.
- Added `docs/unique-data-model.md` and
  `examples/stellar_data_model_demo.sh` to demonstrate RocheDB-specific
  ring/stellar data modeling.

### Changed

- Updated Redis, PostgreSQL, Docker-Docker, working-set, memory-pressure, and
  RAG benchmark documentation with the latest local verification numbers.
- Documented that benchmark helpers use fresh temporary RocheDB/PostgreSQL
  data directories, fresh Docker containers where applicable, or unique Redis
  key prefixes that are deleted before exit.
- Expanded public API and test coverage documentation for high-integrity
  application workflows.
- Bumped package metadata to `0.5.0`.

### Fixed / Hardened

- Added matrix coverage for atomic batch commit/rollback, update/delete
  failure rollback, persistence replay, ring lock conflicts, stellar/member
  lock conflicts, disjoint lock coexistence, TTL expiry, and release on
  exception.
- Kept cooperative locks opt-in so ordinary `put`, `get`, `list`, and
  `retrieve` paths remain outside the lock-check path.

## v0.3.0

### Added

- Added the C ABI v2 `roche_read_ring_json` entry point so external drivers can
  read ring-shaped pages with JSON filters, optional projection, sorting,
  cursor/page options, codec metadata, and a stable JSON response shape.
- Added explicit CLI examples for JSON, NIF, BIF, raw, and ring-profile
  `--codec=auto` payload workflows.
- Added `docs/test-coverage.md` to track the current unit, smoke, contract,
  recovery, cluster, universe sync, and driver compatibility test matrix.

### Changed

- Unified recent ring-oriented CLI read behavior around one page-shaped result
  for single and multiple records.
- Bumped package metadata to `0.3.0`.

### Fixed / Hardened

- Expanded public API coverage for `readRing` filtering, ID lookup, pagination,
  sorting defaults, sort aliases, empty-result behavior, and invalid sort
  rejection.
- Expanded codec coverage for JSON-compatible projection and NIF/BIF projection
  rejection.
- Expanded CLI smoke coverage for codec display, BIF base64/hex/adapter views,
  invalid filters, invalid sort fields, and invalid projection requests.
- Expanded the C ABI contract smoke with JSON projection, NIF/BIF metadata,
  invalid filter, invalid sort, and null-ring error checks.

## v0.2.5

### Fixed

- Restored the cluster read path after transaction landing-zone reads had added
  an avoidable request before ordinary `GET` / `BGET` operations.
- Kept read-your-writes behavior for accepted-but-not-yet-applied cluster
  writes by tracking only the pending IDs written through the current client.
- Fixed the benchmark stable-ring guard so full-period orbits are not
  misclassified as stable during cluster latency tests.

### Changed

- Updated PostgreSQL and Redis benchmark documentation with the 2026-07-08
  local retest results.
- Added comparison-friendly benchmark tables.
- Bumped package metadata to `0.2.5`.

## v0.2.4

### Added

- Added driver discovery and installation guidance through `roche driver
  list`, `roche driver info`, and `roche driver install`.
- Added Rust driver install targeting for manifest path, project directory, and
  environment-variable based setup.

### Changed

- Removed the Rust driver implementation from the core repository so language
  drivers can be released from separate repositories.

## v0.2.3

### Fixed

- Removed the `roched` selector `getData` path that triggered Nim's
  `ProveInit` warning during server builds.
- Bumped package metadata to `0.2.3`.

## v0.2.2

### Changed

- Updated installation documentation now that RocheDB is available through
  Nimble.
- Clarified that non-Nim language packages remain repository-local foundations
  while `nimble install rochedb` is the normal Nim install path.
- Bumped package metadata to `0.2.2`.

## v0.2.1

### Changed

- Clarified CLI installation paths and documented `~/.nimble/bin` PATH setup.
- Added system install guidance for `/usr/local/bin/roche` and
  `/usr/local/bin/roched`.
- Added a dedicated installation page and linked it from README and the docs
  index.

## v0.2.0

### Added

- Added GitHub Pages documentation structure, public API/config/CLI references,
  and topology / universe sync guides.
- Added `bin/roche` CLI workflows for CRUD, ring listing/counting, atlas, and a
  minimal interactive shell.
- Added Docker Compose demos for a single galaxy, a three-node galaxy, and a
  local/remote universe-shaped topology.
- Added remote universe sync smoke coverage for target downtime, restart
  recovery, applied-key persistence, and duplicate delivery idempotency.
- Added user-facing CLI error handling for wire/auth failures.

### Changed

- Tightened Docker demo builds with a small build context and explicit
  nimsodium/libsodium setup.
- Reworked recovery topology terminology around universes and galaxies.

## v0.1.5

### Changed

- Added README installation steps before the embedded-mode quickstart so new
  users can set up the repository before writing code.

## v0.1.4

### Changed

- Reduced public fault-tolerance roadmap details and kept detailed recovery
  strategy outside the public repository.

## v0.1.3

### Added

- Added `CONTRIBUTING.md` with a pre-1.0 contribution policy focused on
  real-world verification reports, operational evidence, benchmark results,
  recovery reports, and small documentation fixes.

## v0.1.2

### Changed

- Kept the ID-less lookup guidance inside the embedded quickstart instead of a
  separate README section.
- Added API reference documentation to the v0.2+ roadmap.

## v0.1.1

### Changed

- Documented how to look up records when the application does not already have a
  RocheDB ID: start from a ring with `listByRing`, use ring-scoped `retrieve`
  for vector/RAG lookup, and use `atlas()` / ring descriptions to choose scope.

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
