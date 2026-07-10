# RocheDB

**v0.2.0 Technical Preview / research OSS.** RocheDB is not yet presented as a
production replacement for Redis, PostgreSQL, MongoDB, Apache Arrow, or a
dedicated vector database. The current release target is a measurable prototype
of ring/galaxy-oriented storage, retrieval, persistence, drivers, and cluster
smoke behavior.

RocheDB's practical goal is simple: reduce the amount of data a system has to
read, transfer, hold in memory, and pass to downstream AI/RAG or application
logic. In one sentence:

> RocheDB stores data with a coordinate-like `ring`, then uses that placement at
> read time to reduce the amount of data that must be searched, transferred, and
> passed to downstream systems.

The celestial mechanics vocabulary, especially orbits, encounters, rings, and
accretion, is an algorithmic design source rather than the value proposition.
The value proposition is smaller working sets, fewer transferred bytes, fewer
retrieval tokens, and lower infrastructure pressure when data can be placed by
meaningful locality.

It is not an AI-only database. The same model is intended to work as a general
NoSQL/document store for web systems: users, tenants, regions, products,
categories, dates, and application state can all become rings or ring
hierarchies. The core idea is that locality, authorization boundaries, dump
units, migration units, and retrieval scope should be visible to the database
instead of being reconstructed after every query.

Writes are intentionally light. A human, application, or import rule places data
into a ring. Reads use the ring, hierarchy, centroid, coherence, mass, retrieval
profile, and projection to keep the candidate set small.

RocheDB is NoSQL, but it is not a MongoDB-compatible or ad-hoc aggregation
database. The main difference is that a `ring` is not just a collection name; it
is part of the read path. RocheDB expects applications, routes, tenants, import
rules, or operators to place data into meaningful rings so later reads can avoid
unrelated working sets. See [How RocheDB Differs From Typical NoSQL](docs/nosql-positioning.md).

RocheDB's main bet is not "scan the entire corpus faster." It is "avoid reading
unneeded data in the first place." Training data, document corpora, and
application histories tend to grow. Systems that keep scanning wider datasets
eventually run into physical limits: memory bandwidth, semiconductor supply,
energy, cooling, cloud cost, and latency. RocheDB tries to move cost from total
corpus size toward semantic working-set size.

## Documents

- Documentation site entry point: [docs/index.md](docs/index.md)
- Installation: [docs/installation.md](docs/installation.md)
- Public API reference: [docs/public-api.md](docs/public-api.md)
- Configuration reference: [docs/config-reference.md](docs/config-reference.md)
- CLI reference: [docs/cli-reference.md](docs/cli-reference.md)
- How RocheDB differs from typical NoSQL: [docs/nosql-positioning.md](docs/nosql-positioning.md)
- Concept: [docs/rochedb-concept.md](docs/rochedb-concept.md)
- Detailed design: [docs/rochedb-design.md](docs/rochedb-design.md)
- Feature status / roadmap: [docs/rochedb-status.md](docs/rochedb-status.md)
- Release checklist: [docs/release-checklist.md](docs/release-checklist.md)
- GitHub release draft: [docs/github-release-v0.2.0.md](docs/github-release-v0.2.0.md)
- Driver / FFI roadmap: [docs/rochedb-driver-roadmap.md](docs/rochedb-driver-roadmap.md)
- Driver installation guide: [docs/driver-installation.md](docs/driver-installation.md)
- FAISS versioning policy: [docs/faiss-versioning.md](docs/faiss-versioning.md)
- Vector backend selection: [docs/vector-backends.md](docs/vector-backends.md)
- Protocol compatibility: [docs/protocol-compatibility.md](docs/protocol-compatibility.md)
- Universe sync: [docs/universe-sync.md](docs/universe-sync.md)
- Threat model: [docs/threat-model.md](docs/threat-model.md)
- Benchmark notes: [docs/rochedb-bench.md](docs/rochedb-bench.md)
- Cloud operations metrics: [docs/cloud-operations.md](docs/cloud-operations.md)
- Topology configuration reference: [docs/topology-config.md](docs/topology-config.md)
- Topology pattern catalog: [docs/topology-examples.md](docs/topology-examples.md)
- Shelfer integration boundary: [docs/rochedb-shelfer-integration.md](docs/rochedb-shelfer-integration.md)
- Halo capture design: [docs/rochedb-halo-capture.md](docs/rochedb-halo-capture.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- Contribution policy: [CONTRIBUTING.md](CONTRIBUTING.md)

## Installation

RocheDB v0.2.x is a technical preview. The Nim package is available through
Nimble. Rust, JavaScript / TypeScript, and PHP drivers are published as
language packages, while the remaining non-Nim language drivers are still
repository-local foundations.

Prerequisites:

- Nim `2.0.0` or newer
- `git`
- `gcc` or another C compiler supported by Nim

Install the CLI and Nim library:

```sh
nimble install rochedb
roche --help
```

Clone the repository when you want to run the full source test suite, examples,
or driver smoke tests:

```sh
git clone https://github.com/puffball1567/rochedb.git
cd rochedb
scripts/test_core.sh
nimble install -y
```

Nimble installs binaries into `~/.nimble/bin` by default. If `roche` is not
found, add it to your shell PATH:

```sh
export PATH="$HOME/.nimble/bin:$PATH"
```

For server-style installs, build locally and install the binaries into
`/usr/local/bin`, the usual source-install location for database tools:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roche -o:bin/roche src/rochecli.nim
nim c -d:release --nimcache:/tmp/nimcache_roched -o:bin/roched src/roched.nim
sudo install -m 0755 bin/roche /usr/local/bin/roche
sudo install -m 0755 bin/roched /usr/local/bin/roched
```

See [docs/installation.md](docs/installation.md) for PATH and system install
details.

Use RocheDB from a Nim program in this repository by importing the public module:

```nim
import rochedb
```

For command-line tools and demos that need repo-local binaries, build them under
`bin/`:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roche -o:bin/roche src/rochecli.nim
nim c -d:release --nimcache:/tmp/nimcache_roched -o:bin/roched src/roched.nim
```

Basic CLI document workflow:

```sh
roche put --data=data --ring=docs/japan --payload='{"title":"Hello"}'
roche list-ring --data=data --ring=docs/japan
roche get --data=data --id=RAW_ID
```

Optional FAISS vector backend:

```sh
scripts/fetch_faiss.sh
scripts/setup_faiss_toolchain.sh   # only needed when system CMake is too old
scripts/build_faiss_bridge.sh
roche doctor
```

The built-in exact vector backend works without FAISS. FAISS is recommended for
production-style broad vector reads when the bridge is available. See
[docs/driver-installation.md](docs/driver-installation.md) for language drivers
and [docs/faiss-versioning.md](docs/faiss-versioning.md) for FAISS version
control.

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

Published external drivers:

| Language / runtime | Package | Version | Repository | Mode |
|---|---|---:|---|---|
| Rust | [`rochedb`](https://crates.io/crates/rochedb) | `0.1.3` | [`puffball1567/rochedb-rust`](https://github.com/puffball1567/rochedb-rust) | C ABI wrapper |
| JavaScript / TypeScript | [`rochedb`](https://www.npmjs.com/package/rochedb) | `0.1.2` | [`puffball1567/rochedb-js`](https://github.com/puffball1567/rochedb-js) | Node-API C ABI wrapper |
| PHP | [`rochedb/rochedb`](https://packagist.org/packages/rochedb/rochedb) | `0.1.1` | [`puffball1567/rochedb-php`](https://github.com/puffball1567/rochedb-php) | FFI / C ABI wrapper |
| C++ | GitHub / CMake source package | `0.1.0` | [`puffball1567/rochedb-cpp`](https://github.com/puffball1567/rochedb-cpp) | C++17 C ABI wrapper |

The table below lists current core-repository driver foundations. Publication
priority for remaining language packages is tracked in
[docs/rochedb-driver-roadmap.md](docs/rochedb-driver-roadmap.md).

| Language / runtime | Driver path | Current mode | Smoke status |
|---|---|---|---|
| Nim | `src/rochedb.nim` | Native embedded and cluster API | core tests |
| C ABI | `include/rochedb.h` | Embedded / cluster foundation for bindings | contract smoke |
| Python | `drivers/python` | Native TCP wire driver | unittest wire smoke |
| Node.js / TypeScript | `drivers/node` | Native TCP wire driver, ESM | `node --test` |
| Bun | `drivers/node` | Node-compatible TCP wire driver | `bun test` |
| Go | `drivers/go` | C ABI wrapper | `go test` |
| Swift | `drivers/swift` | SwiftPM C ABI wrapper | Linux Docker smoke |
| C# | `drivers/csharp` | Generic .NET C ABI wrapper | contract smoke |
| Kotlin/JVM | `drivers/kotlin` | JNI / C ABI wrapper | Docker smoke |

Detailed setup notes are in
[docs/driver-installation.md](docs/driver-installation.md). Nimble package
registration is complete. Rust, JavaScript / TypeScript, and PHP driver
packages are published; PyPI, NuGet, Maven, Go, SwiftPM, and other registry
packages remain roadmap items.

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
[docs/rochedb-bench.md](docs/rochedb-bench.md), with compact comparison tables
in [docs/benchmark-comparison.md](docs/benchmark-comparison.md). The short
version is:

- RocheDB 3-node TCP with persistence enabled measured `45.9 us` per
  single-key read and `47.7 us` per single-key write in the PostgreSQL
  comparison helper run.
- PostgreSQL 14.23 on the same machine measured `67 us` for primary-key read
  and `79 us` for `synchronous_commit=off` single-row write over local TCP.
- The PostgreSQL comparison also has a Docker-Docker reproduction helper; in
  the included run RocheDB measured `53.5 us` read / `56.4 us` write, while
  PostgreSQL measured `92 us` primary-key read / `130 us`
  `synchronous_commit=off` write.
- Local Redis 6.0.16 measured `41.23 us/op` for single GET and `3.68 us/op`
  for pipeline GET. RocheDB TCP GET measured `44.87 us/op`; RocheDB TCP BGET
  measured `1.47 us/op` in the same local single-client benchmark shape.

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

### Core Test Suite

```sh
scripts/test_core.sh
scripts/test_all_smoke.sh
```

Include driver compatibility checks when local toolchains are available:

```sh
ROCHE_TEST_DRIVERS=1 scripts/test_all_smoke.sh
```

### Simulation And Mechanism Benchmarks

```sh
nim c -d:danger -o:bin/rochesim src/rochesim.nim
bin/rochesim all

nim c -d:danger -o:bin/rochebench src/rochebench.nim
bin/rochebench
```

### Working-Set, Memory, And RAG Benchmarks

```sh
nim c -d:release -o:bin/roche src/rochecli.nim
roche working-set-bench --n=100000 --rings=100 --queries=50 --budget=20
roche memory-pressure-bench --n=100000 --rings=100 --queries=50 --budget=20 --payload-bytes=512
RUN_REDIS=0 examples/memory_pressure_case_study.sh
examples/ai_rag_case_study.sh
```

### Redis Comparison

Use an existing local Redis server:

```sh
N=1000 examples/redis_local_bench.sh
```

Or compare Redis and RocheDB inside the same Docker network:

```sh
N=1000 examples/redis_docker_bench.sh
```

### Server Options

```sh
nim c -d:release -o:bin/roched src/roched.nim
nim c -d:release -o:bin/roche src/rochecli.nim
```

Strong durability mode:

```sh
bin/roched --id=0 --peers=127.0.0.1:7301 --data=/var/lib/roche --durability=strong
```

Ring-prefix authorization:

```sh
bin/roched --id=0 --peers=127.0.0.1:7301 --user=alice --password=secret --allow-ring=allowed
```

Minimal RBAC plus ring-prefix authorization:

```sh
bin/roched --id=0 --peers=127.0.0.1:7301 \
  --role=reader:read:reader:allowed \
  --role=writer:write:writer:allowed \
  --role=admin:admin:admin:allowed
```

Encrypted backup / restore:

```sh
roche backup-encrypted --data=data --backup=backup.enc --passphrase=change-me
roche restore-encrypted --backup=backup.enc --data=restored --passphrase=change-me
```

### Driver Checks

```sh
python3 -m unittest discover -s drivers/python/tests
node --test drivers/node/test/*.test.js
```

Cluster demo:

```sh
./examples/cluster_demo.sh
```

Universe sync demo:

```sh
./examples/universe_sync_demo.sh
./scripts/universe_sync_remote_smoke.sh
```

This shows a WAL-backed eventual sync outbox, idempotent apply, ack/prune, and
the CLI handoff boundary between two local data directories or a remote RocheDB
server. See [docs/topology-examples.md](docs/topology-examples.md) for topology
patterns.

### C ABI

```sh
nim c --app:lib -d:release -o:lib/librochedb.so src/rochedb_capi.nim
gcc examples/demo.c -Iinclude -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../lib' -o bin/demo
bin/demo
```

### FAISS Vector Backend

```sh
scripts/fetch_faiss.sh
scripts/setup_faiss_toolchain.sh
scripts/build_faiss_bridge.sh
roche doctor
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
examples/compose/      Docker Compose topology demos
tests/                 unit and smoke tests
```

## License

RocheDB core and the OSS drivers are released under Apache-2.0; see
[LICENSE](LICENSE).

Third-party dependency and tooling notices are tracked in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Security assumptions and known
gaps are tracked in [docs/threat-model.md](docs/threat-model.md).
