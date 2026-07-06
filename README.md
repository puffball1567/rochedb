# RocheDB

**v0.1.0 Technical Preview / research OSS.** RocheDB is not yet presented as a
production replacement for Redis, PostgreSQL, MongoDB, Apache Arrow, or a
dedicated vector database. The current release target is a measurable prototype
of ring/galaxy-oriented storage, retrieval, persistence, drivers, and cluster
smoke behavior.

RocheDB uses celestial mechanics, especially orbits, encounters, rings, and
accretion, as an algorithmic design source rather than as a naming theme. In one
sentence:

> RocheDB stores data with a coordinate-like `ring`, then uses that placement at
> read time to reduce the amount of data that must be searched, transferred, and
> passed to downstream systems.

It is not an AI-only database. The same model is intended to work as a general
NoSQL/document store for web systems: users, tenants, regions, products,
categories, dates, and application state can all become rings or ring
hierarchies. The core idea is that locality, authorization boundaries, dump
units, migration units, and retrieval scope should be visible to the database
instead of being reconstructed after every query.

Writes are intentionally light. A human, application, or import rule places data
into a ring. Reads use the ring, hierarchy, centroid, coherence, mass, retrieval
profile, and projection to keep the candidate set small.

RocheDB's main bet is not "scan the entire corpus faster." It is "avoid reading
unneeded data in the first place." Training data, document corpora, and
application histories tend to grow. Systems that keep scanning wider datasets
eventually run into physical limits: memory bandwidth, semiconductor supply,
energy, cooling, cloud cost, and latency. RocheDB tries to move cost from total
corpus size toward semantic working-set size.

## Documents

- Concept: [docs/rochedb-concept.md](docs/rochedb-concept.md)
- Detailed design: [docs/rochedb-design.md](docs/rochedb-design.md)
- Feature status / roadmap: [docs/rochedb-status.md](docs/rochedb-status.md)
- Release checklist: [docs/release-checklist.md](docs/release-checklist.md)
- GitHub release draft: [docs/github-release-v0.1.0.md](docs/github-release-v0.1.0.md)
- Driver / FFI roadmap: [docs/rochedb-driver-roadmap.md](docs/rochedb-driver-roadmap.md)
- Driver installation guide: [docs/driver-installation.md](docs/driver-installation.md)
- FAISS versioning policy: [docs/faiss-versioning.md](docs/faiss-versioning.md)
- Vector backend selection: [docs/vector-backends.md](docs/vector-backends.md)
- Threat model: [docs/threat-model.md](docs/threat-model.md)
- Benchmark notes: [docs/rochedb-bench.md](docs/rochedb-bench.md)
- Cloud operations metrics: [docs/cloud-operations.md](docs/cloud-operations.md)
- Shelfer integration boundary: [docs/rochedb-shelfer-integration.md](docs/rochedb-shelfer-integration.md)
- Halo capture design: [docs/rochedb-halo-capture.md](docs/rochedb-halo-capture.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## Quickstart: Embedded Mode

```nim
import rochedb

var db = rochedb.open(dataDir = "data")   # persistent; omit dataDir for memory-only
db.setGalaxyDescription("Product and support knowledge")
db.setRingDescription("docs/japan", "Japanese product documentation and support articles")

let id = db.put("hello", ring = "docs/japan")
echo db.get(id)
echo db.atlas()                           # galaxy/ring map for agents and tools

echo db.locate(id)                        # current owner, computed locally
echo db.locate(id, at = 120.0)            # future owner, also computed locally
```

`get(id)` is the fastest path when the application already has a RocheDB ID. If
the ID is not known, start from a ring.

```nim
import rochedb

var db = rochedb.open(dataDir = "data")

discard db.put("""{"slug":"hello","title":"Hello"}""", ring = "docs/japan")
discard db.put("""{"slug":"refund","title":"Refund guide"}""", ring = "docs/japan")

for item in db.listByRing("docs/japan"):
  echo item.payload
```

For vector/RAG-style lookup, search the ring directly:

```nim
let hits = db.retrieve(@[1.0'f32, 0.0'f32], ring = "docs/japan", budget = 3)

for hit in hits:
  echo hit.payload
```

If the right ring is not obvious, use `atlas()` and ring descriptions to choose
the search scope first. RocheDB is designed to avoid ID-less global scans when a
ring coordinate is available.

## Why It Helps Web Systems

RocheDB is useful outside AI workflows when the application naturally has
locality boundaries.

- Tenant locality: `ring = "tenant/acme/orders"` keeps query scope, dump scope,
  backup scope, and future authorization scope aligned.
- Smaller responses: `query(id, "{ title status }")` returns only requested
  fields, so large JSON documents do not need to cross the process or network
  boundary on every read.
- Import routing: JSONL exports from MongoDB-like stores can be imported and
  routed by fields such as `tenant`, `category`, `region`, or `date`.
- Galaxy isolation: separate services can use separate galaxies, data
  directories, credentials, and clusters while using the same implementation.
- Explainable location: `locate(id)` and `locate(id, at=...)` make placement
  observable without a directory service.
- Incremental adoption: start with embedded `open(dataDir=...)`, then move to
  cluster `connect(...)` when the service needs separate nodes.

## Drivers

The public driver surface is intentionally small. External drivers can use
high-level wire frames such as `PUTR`, `GETID`, `QRYID`, `BGET`, and
`RETRIEVE`; they do not need to reimplement RocheDB's ring-key, orbit, or ID
rules.

| Language / runtime | Driver path | Current mode | Smoke status |
|---|---|---|---|
| Nim | `src/rochedb.nim` | Native embedded and cluster API | core tests |
| C ABI | `include/rochedb.h` | Embedded / cluster foundation for bindings | contract smoke |
| Python | `drivers/python` | Native TCP wire driver | unittest wire smoke |
| Node.js / TypeScript | `drivers/node` | Native TCP wire driver, ESM | `node --test` |
| Bun | `drivers/node` | Node-compatible TCP wire driver | `bun test` |
| Rust | `drivers/rust` | C ABI wrapper | `cargo test` |
| Go | `drivers/go` | C ABI wrapper | `go test` |
| PHP | `drivers/php` | FFI / C ABI wrapper | Docker smoke |
| Swift | `drivers/swift` | SwiftPM C ABI wrapper | Linux Docker smoke |
| C# | `drivers/csharp` | Generic .NET C ABI wrapper | contract smoke |
| C++ | `drivers/cpp` | C++17 C ABI wrapper | contract smoke |
| Kotlin/JVM | `drivers/kotlin` | JNI / C ABI wrapper | Docker smoke |

Detailed setup notes are in
[docs/driver-installation.md](docs/driver-installation.md). Package publishing
to npm, PyPI, Cargo, Composer, NuGet, Maven, and other registries is a post-v0.1
roadmap item and is not part of the current technical-preview claim.

## Cluster Mode

Run `roched` nodes with the same peer list:

```sh
roched --id=0 --peers=h1:7301,h2:7301,h3:7301 --data=/var/lib/roche
```

Then connect with the same API shape:

```nim
var db = connect("h1:7301,h2:7301,h3:7301")
let id = db.put(%*{"title": "RocheDB", "author": {"name": "Ada"}}, ring = "docs")
echo db.query(id, "{ title author { name } }")
echo db.locate(id, at = epochTime() + 60)
```

The core placement rule is deterministic:

> data location = deterministic function `E(id, t) -> node`

Every node can compute where a record is now, and where it will be later,
without a directory lookup. Handoffs are scheduled from ephemeris state rather
than from a central rebalance service.

Canonical data should normally live in one galaxy/ring. Multiple views should be
modeled with hierarchy, naming conventions, import rules, retrieval profiles, or
projection. RocheDB core does not try to keep duplicate logical records in
multiple galaxies perfectly synchronized.

For asynchronous maintenance across rings, RocheDB has a minimal `warp` queue.
A warp job scans specified rings over time and drops a patch into matching
documents. It is closer to a maintenance asteroid belt than a relational join:
jobs have attempts, retry timing, acknowledgements, and dead-letter state, and
their state is persisted in the WAL. Rich scheduling, backoff policy, audit
history, and flow orchestration are intended to live in adapters such as the
future `rochedb-flow` integration.

## Retrieval, Memory, and Token Reduction

RocheDB's strongest benchmark story is working-set reduction. Local reads are
also in the same broad latency class as existing databases, but the larger claim
is that RocheDB can reduce how much data is touched before ANN, rerank, LLM, or
application processing.

| Benchmark | Setup | Result |
|---|---|---|
| Working-set | 100 rings / 10k docs | scanned/query `10000 -> 100` (99% reduction) |
| Memory-pressure | 100 rings / 100k docs / 512B payload | candidate memory/query `93.079 MiB -> 0.931 MiB` (99% reduction) |
| Synthetic RAG | fixed recall | recall `1.000`, scanned/query `8000 -> 1000`, tokens/query `3960 -> 657.8` |
| AI/RAG case study | generated JSONL, 400 docs / 6 rings | recall `1.000`, scanned/query `400 -> 40`, tokens/query `615.2 -> 231.6` |
| API minimum test | 2 rings / 4 vectors | `skippedVectors` and `candidateReduction` confirm pre-filtered search scope |

Reference latency results are tracked in
[docs/rochedb-bench.md](docs/rochedb-bench.md). The short version is:

- RocheDB 3-node TCP with persistence enabled measured `45.6 us` per single-key
  read and `49.2 us` per single-key write in the local smoke benchmark.
- PostgreSQL 14 on the same machine measured `84 us` for primary-key read and
  `77 us` for `synchronous_commit=off` single-row write in the referenced
  comparison.
- A Docker Redis smoke test measured RocheDB TCP `BGET` at `1.56 us/op` and
  Redis pipeline GET at `3.56 us/op` under the documented local conditions.

These are not universal performance claims. They show that the local read path
is already competitive enough for the working-set reduction story to matter.

## C ABI

`include/rochedb.h` plus `lib/librochedb.so` is the foundation for non-Nim
bindings.

```c
roche_init();
if (roche_abi_version() != ROCHE_ABI_VERSION) return 1;

void *db = roche_connect("h1:7301,h2:7301,h3:7301");
roche_id id;

roche_set_galaxy_description(db, "Product and support knowledge");
roche_set_ring_description(db, "docs", "Documentation ring");
roche_put(db, "docs", "hello", 5, &id);

float v[2] = {1.0f, 0.0f};
roche_put_vec(db, "docs", "hello", 5, v, 2, &id);

roche_batch_result *b = roche_batch_get(db, &id, 1);
roche_batch_get_free(b);

roche_retrieve_result *r = roche_retrieve(db, v, 2, "docs", 8, 0, 0);
roche_retrieve_free(r);

size_t n;
char *j = roche_query(db, id, "{ title }", &n);
roche_free(j);

char *a = roche_atlas(db, v, 2, 8, &n);
roche_free(a);

int node = roche_locate(db, id, -1.0);
```

## Build and Verification

```sh
# Core tests
scripts/test_core.sh

# Cluster, authz, RBAC, wire fuzz, and smoke checks
scripts/test_all_smoke.sh

# Include driver compatibility checks where local toolchains are available
ROCHE_TEST_DRIVERS=1 scripts/test_all_smoke.sh

# PoC simulation and mechanism benchmark
nim c -d:danger -o:bin/rochesim src/rochesim.nim
bin/rochesim all
nim c -d:danger -o:bin/rochebench src/rochebench.nim
bin/rochebench

# Working-set and memory-pressure benchmarks
nim c -d:release -o:bin/rochecli src/rochecli.nim
bin/rochecli working-set-bench --n=100000 --rings=100 --queries=50 --budget=20
bin/rochecli memory-pressure-bench --n=100000 --rings=100 --queries=50 --budget=20 --payload-bytes=512
RUN_REDIS=0 examples/memory_pressure_case_study.sh

# AI/RAG case study with generated JSONL corpus
examples/ai_rag_case_study.sh

# Local Redis comparison, when Redis is already running
bin/rochecli redis-bench --n=100000 --payload-bytes=100 --redis=127.0.0.1:6379

# Docker Redis comparison
examples/redis_bench.sh

# Redis TCP / Redis pipeline / RocheDB TCP comparison
ROCHED=1 examples/redis_bench.sh

# Server and client binaries
nim c -d:release -o:bin/roched src/roched.nim
nim c -d:release -o:bin/rochecli src/rochecli.nim

# Strong durability mode
bin/roched --id=0 --peers=127.0.0.1:7301 --data=/var/lib/roche --durability=strong

# Ring-prefix authorization
bin/roched --id=0 --peers=127.0.0.1:7301 --user=alice --password=secret --allow-ring=allowed

# Minimal RBAC plus ring-prefix authorization
bin/roched --id=0 --peers=127.0.0.1:7301 \
  --role=reader:read:reader:allowed \
  --role=writer:write:writer:allowed \
  --role=admin:admin:admin:allowed

# Encrypted backup / restore
bin/rochecli backup-encrypted --data=data --backup=backup.enc --passphrase=change-me
bin/rochecli restore-encrypted --backup=backup.enc --data=restored --passphrase=change-me

# Python native wire driver
python3 -m unittest discover -s drivers/python/tests

# Node.js native wire driver
node --test drivers/node/test/*.test.js

# Cluster demo
./examples/cluster_demo.sh

# C ABI
nim c --app:lib -d:release -o:lib/librochedb.so src/rochedb_capi.nim
gcc examples/demo.c -Iinclude -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../lib' -o bin/demo
bin/demo

# FAISS vector backend bridge setup
scripts/fetch_faiss.sh
scripts/setup_faiss_toolchain.sh
scripts/build_faiss_bridge.sh
bin/rochecli doctor
# optional Exact vs FAISS smoke comparison
examples/vector_backend_bench.sh
```

By default this fetches the configured FAISS tag, currently `v1.14.3`, and
records the actual commit in `third_party/faiss.version`. It does not enforce an
exact commit unless `ROCHE_FAISS_COMMIT` is set. See
[docs/faiss-versioning.md](docs/faiss-versioning.md) for tag overrides, exact
commit pinning, upgrades, downgrades, and security update handling.

FAISS is the recommended production vector backend when the bridge is available.
RocheDB's built-in exact backend remains useful as a dependency-free fallback
for tests, small embedded deployments, and environments where FAISS cannot be
installed. See [docs/vector-backends.md](docs/vector-backends.md) for the backend
selection rule and local smoke benchmark.

RocheDB forces Nim ARC through `config.nims`. Avoiding reference cycles is a
structural constraint of the codebase, not just a style preference.

## Project Layout

```text
src/rochedb.nim        public API for embedded and cluster modes
src/roched.nim         node server: scale-out, persistence, handoff
src/rochecli.nim       CLI, demos, benchmarks, maintenance commands
src/rochedb_capi.nim   C ABI
src/roche/core.nim     ephemeris fast layer: Orbit, ArcTable, encounters
src/roche/select.nim   GraphQL-like projection
src/roche/store.nim    particle store plus append-only WAL
src/roche/wire.nim     wire protocol and persistent client
src/rochesim.nim       PoC verification CLI
drivers/               language drivers and wrappers
include/rochedb.h      C header
examples/              C demo, cluster demo, benchmark scripts
tests/                 unit and smoke tests
```

## License

RocheDB core and the OSS drivers are released under Apache-2.0; see
[LICENSE](LICENSE).

Third-party dependency and tooling notices are tracked in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Security assumptions and known
gaps are tracked in [docs/threat-model.md](docs/threat-model.md).
