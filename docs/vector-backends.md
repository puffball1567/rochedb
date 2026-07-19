# Vector Backend Selection

OrbeliasDB has two vector search backends in v0.1.0:

- `vbExact`: the built-in dependency-free backend.
- `vbFaiss`: the optional FAISS bridge backend using `liborbelias_faiss.so`.

The backend choice is a performance and deployment decision. It does not change
OrbeliasDB's data model: rings still reduce the working set before vector search.

## Why Use FAISS?

FAISS gives OrbeliasDB a production-grade vector execution path maintained by a
widely used upstream project. In v0.1.0 the bridge uses FAISS `IndexFlatIP`,
which is an exact flat inner-product index, not an approximate ANN index.

The practical benefits are:

- faster execution over large candidate sets;
- a standard path for future FAISS index types;
- less OrbeliasDB-specific vector code to maintain;
- a familiar dependency for AI and retrieval teams that already use FAISS.

OrbeliasDB stores normalized vectors before indexing. With normalized vectors,
FAISS inner product and cosine-based exact search produce comparable ordering
for the current bridge.

## Which Backend Is Faster?

There is no single answer. Candidate count matters.

| Workload shape | Usually faster | Reason |
| --- | --- | --- |
| Small scoped ring reads | `vbExact` | No dynamic bridge or FAISS call overhead. |
| Large global or broad reads | `vbFaiss` | FAISS' C++ flat search is much faster over large vector sets. |
| RAG/LLM retrieval after strong ring routing | `vbFaiss` for production, `vbExact` for fallback | OrbeliasDB may reduce candidates enough that exact scoped reads are cheap, but the absolute FAISS overhead is small. |
| Production vector-heavy workloads | `vbFaiss` | It is the intended scalable backend path. |

The recommended production policy is simple: use FAISS when the bridge is
available, and keep exact search as a dependency-free fallback for tests, small
embedded deployments, and environments where FAISS cannot be installed.

The key OrbeliasDB point is that ring routing and FAISS are complementary. Rings
reduce how much must be searched. FAISS makes the remaining vector search path
fast enough that using it as the normal production backend is reasonable even
when scoped rings are already small.

## Local Smoke Result

On the local development machine, with `docs=20000`, `rings=100`, `dim=64`,
`queries=200`, and `budget=8`:

| Backend | Global read | Scoped ring read |
| --- | ---: | ---: |
| `vbExact` | 3042.43 us/query, scanned/query 20000 | 43.57 us/query, scanned/query 200 |
| `vbFaiss` | 293.80 us/query, scanned/query 20000 | 67.02 us/query, scanned/query 200 |

This smoke test shows the current behavior clearly:

- FAISS was about `10.36x` faster for the broad/global vector read.
- Exact was about `1.54x` faster for the small scoped-ring read, but the
  absolute difference was only about `23.45 us/query`.

Do not read this as a universal benchmark. It is a release sanity check that
explains backend selection. Real deployments should benchmark with their own
vector dimensions, ring sizes, budgets, payloads, and hardware.

Run it locally with:

```sh
examples/vector_backend_bench.sh
```

Optional parameters:

```sh
DOCS=100000 RINGS=100 DIM=128 QUERIES=500 BUDGET=8 examples/vector_backend_bench.sh
```

If FAISS is not installed, the benchmark still reports the exact backend and
skips FAISS with a setup message. See [faiss-versioning.md](./faiss-versioning.md)
for FAISS setup and version control.
