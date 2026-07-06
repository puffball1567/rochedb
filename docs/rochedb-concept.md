# RocheDB Concept Notes

RocheDB is an experimental distributed document/vector store that uses
celestial-mechanics ideas as design constraints. The names are not the point.
The useful part is that orbital systems separate fast deterministic motion from
slow structural change.

The current implementation is a technical preview. It is intended to prove that
ring/galaxy placement can reduce read scope and downstream work while still
leaving a normal database-shaped API.

## 1. Scope

RocheDB targets read-heavy stock data:

- AI training and retrieval corpora
- documentation and literature collections
- application documents with natural tenant/category/time locality
- embedded or local stores that benefit from structured retrieval

It is not currently positioned as:

- a bank-ledger OLTP system
- a global strongly consistent SQL engine
- a streaming log engine
- a full analytics columnar engine
- a model optimizer or LLM runtime

The design goal is to be narrow where the database needs to be narrow, while
remaining useful as a general NoSQL/document store.

## 2. Core Bet: Ephemeris, Not Magical Gravity

The strongest database idea from celestial mechanics is not "things attract."
The stronger idea is:

> location can be a deterministic function of identity and time.

In RocheDB terms:

```text
E(id, t) -> node
```

Every node can compute current and future placement without asking a directory
server. This creates three useful properties:

- location discovery can be local computation;
- future handoffs can be predicted;
- cluster movement can be scheduled without a central rebalance table.

Gravity remains useful as a design metaphor for ranking, mass, and semantic
locality, but the fast path must stay deterministic and cheap.

## 3. Two Time Scales

RocheDB separates:

- fast layer: orbit/location evaluation, ID routing, read/write hot paths;
- slow layer: hierarchy maintenance, halo capture, compaction, warp jobs,
  backup, import, metrics, and future tuning.

This is a structural constraint. Expensive adaptation must not enter the
`locate` or basic read path.

## 4. Rings and Galaxies

A `ring` is the primary coordinate for data locality. Applications can use it
for tenants, topics, users, regions, products, dates, or state scopes.

Examples:

```text
tenant/acme/orders/2026
docs/japan
papers/medicine
app/global/preferences
app/local/editor/session
```

A `galaxy` is an isolation boundary. Different galaxies can have separate data
directories, clusters, credentials, secret keys, and operational policy. A
deployment can use the same RocheDB mechanism for unrelated datasets without
making them interfere.

Canonical data should normally be stored once in one galaxy/ring. Multiple
views should be modeled with hierarchy, naming, import rules, retrieval
profiles, projection, or asynchronous warp jobs rather than by pretending that
many duplicate copies are always one object.

## 5. Read Strategy

RocheDB is strongest when the application can route a read to a meaningful
working set before expensive processing.

The read plan can use:

- explicit ring scope;
- parent/child ring hierarchy;
- sibling expansion;
- centroid similarity;
- ring count and utility signals;
- result amount;
- search scope;
- hierarchy depth;
- payload projection.

This makes the database useful for both AI and ordinary web systems. AI systems
can reduce vectors, chunks, reranker work, and prompt tokens. Web systems can
reduce overfetching, cross-tenant scans, and application-side filtering.

## 6. Write Strategy

RocheDB does not need a heavy classifier on every insert. Writes should be
cheap:

- a human chooses a ring;
- an application uses its route or domain model;
- an import rule maps fields into rings;
- a future adapter may recommend better placement offline.

The database then stores the record with enough coordinate information to make
later reads cheaper.

## 7. Mass, Centroids, and Utility

RocheDB uses mass-like signals to describe how important or dense a ring is.
The implementation should keep this practical:

- count and payload size describe physical cost;
- centroid describes semantic center;
- coherence describes whether a ring is internally consistent;
- utility can be learned from retrieval outcomes;
- mass should improve planning without turning inserts into model inference.

The rule of thumb is simple: use statistics that help the database avoid work,
but keep model optimization outside the core read path.

## 8. Halo Data

Some data arrives without a clear ring. RocheDB calls this a halo. Halo data is
not supposed to dominate the system. It can be:

- stored with a default or temporary ring;
- clustered slowly;
- adopted into a stronger ring when enough evidence accumulates;
- allowed to expire or remain low priority.

The halo mechanism exists to avoid forcing perfect classification at write time.

## 9. Warp Jobs

RocheDB intentionally avoids hard synchronous multi-ring object coupling. When
the user wants a patch to be applied across rings, RocheDB uses an asynchronous
warp queue:

- enqueue a job with target rings, match field, expected value, and patch;
- process it incrementally with `warpStep` or `warpDrain`;
- persist status in the WAL;
- retry later if needed;
- acknowledge and prune when complete.

This gives the system a replication-delay-like maintenance model without making
cross-galaxy writes part of the core transaction path.

## 10. Ring-Local History

RocheDB treats the ring as meaningful placement, not just a lookup bucket. For
many records, strict global order is unnecessary: comments, document chunks,
embeddings, profile snapshots, and AI context can live in the same ring with
write-time metadata and be sorted when read.

The default future synchronization policy should be order-relaxed. A record is
placed in the right galaxy/ring with its write time and origin. If the reader
needs chronological display, it sorts by time. If the reader needs relevance, it
sorts by retrieval score. This keeps the common path light.

Only rings whose final state depends on operation order should opt into delayed
or strict apply. Undo/redo style data can be handled with a bounded ring-local
history window, such as the latest N versions or recent undo/redo pairs. When
history is not useful, RocheDB can prune older versions and keep only the latest
state.

## 11. What Makes RocheDB Different

The distinctive idea is not that RocheDB has indexes. Many databases do. The
distinctive idea is that routing, locality, authorization scope, import layout,
retrieval scope, and data identity can be expressed through the same ring/galaxy
structure.

For a well-modeled application, the route can become the data coordinate:

```text
/tenant/acme/orders/2026
```

That route can simultaneously mean:

- where the data belongs;
- what should be searched;
- what can be dumped;
- what can be backed up;
- what authorization boundary applies;
- what a model or agent should inspect first.

This is why RocheDB can combine NoSQL flexibility with RDB-like locality for
some workloads.

## 12. Honest Boundaries

RocheDB is not automatically better for every query. It is weak or incomplete
when:

- the application cannot express meaningful rings;
- the workload requires large global analytics scans;
- exact global transactions across unrelated galaxies are required;
- write throughput dominates and read locality does not matter;
- schema-level constraints are better handled by a relational engine;
- the corpus needs a mature production-grade vector index and operational
  ecosystem today.

RocheDB can still coexist with these systems. A common shape is RocheDB for
localized document/vector reads and another database for global analytics,
billing ledgers, or reporting.

## 13. Validation Direction

The project should be judged by measured behavior, not by the metaphor. The
important validation points are:

- location evaluation below 100 ns/call;
- local read latency in a competitive class;
- persistence and WAL recovery;
- cluster smoke behavior;
- authorization and protocol robustness;
- ring-scoped candidate reduction;
- memory-pressure reduction;
- quality-fixed RAG/token reduction;
- driver availability;
- reproducible benchmark scripts.

The benchmark document records current measurements and the limits of each
measurement.
