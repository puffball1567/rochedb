# How RocheDB Differs From Typical NoSQL

RocheDB is a NoSQL/document database prototype, but it is not trying to be a
MongoDB-compatible document store, an aggregation engine, or a generic
secondary-index database.

The important distinction is placement. In RocheDB, the `ring` is not merely a
collection label. It is a coordinate used by the read path, the retrieval
planner, dump/import boundaries, authorization boundaries, and future sync /
recovery workflows.

## Expected Mental Model

In many document databases, the common model is:

```text
insert flexible documents first
add filters, indexes, and aggregation later
```

RocheDB's model is different:

```text
place documents into meaningful rings first
use ring locality to avoid reading unrelated data later
```

Documents remain flexible. Different records in the same ring may have different
JSON shapes. The stricter part is not schema; it is placement.

## What RocheDB Does Not Try To Replace

RocheDB is not currently a replacement for:

- MongoDB aggregation pipelines;
- SQL joins and relational constraints;
- arbitrary secondary-index planning over many fields;
- global strongly consistent OLTP ledgers;
- columnar analytics engines;
- streaming log engines.

Those systems are strong when the application needs broad ad-hoc analysis,
strict relational constraints, or large cross-corpus scans.

## What RocheDB Optimizes Instead

RocheDB is designed for systems where most reads can start from a meaningful
scope:

- tenant, user, account, or organization;
- region, language, or market;
- product, category, or content type;
- date or lifecycle bucket;
- application state scope;
- AI/RAG corpus partition;
- imported field mapped into a ring.

When this scope is explicit, RocheDB can reduce:

- records scanned;
- vectors considered;
- bytes transferred;
- payloads projected into application code;
- chunks passed to rerankers or LLM prompts;
- memory pressure from unrelated candidates.

## Collection Versus Ring

| Topic | Typical document collection | RocheDB ring |
|---|---|---|
| Main role | Store documents of a broad type | Place documents in a meaningful locality |
| Query path | Filter/index after choosing a collection | Choose a ring or hierarchy before scanning |
| Schema | Flexible documents | Flexible documents |
| Performance tuning | Indexes, query shapes, aggregation design | Ring design, hierarchy, retrieval profile, projection |
| Isolation | Database/collection/user policy | Galaxy, ring prefix, auth policy, recovery/sync boundary |
| AI/RAG fit | Often needs extra vector/index layer | Ring placement is part of retrieval reduction |

## Insert Philosophy

RocheDB does not need a heavy classifier on every insert.

Good ring placement can come from:

- application routing, such as `tenant/acme/orders`;
- user or operator choice, such as `docs/japan`;
- import rules, such as `--ring-field=tenant --ring-prefix=tenant/`;
- simple domain conventions, such as `products/electronics/2026`;
- later offline cleanup through halo capture or warp jobs.

This keeps writes light. The database stores enough coordinate information to
make later reads cheaper.

## Query Philosophy

RocheDB is strongest when the caller can say where to look.

Examples:

```nim
discard db.put("""{"title":"Refund guide"}""", ring = "docs/japan")

for item in db.listByRing("docs/japan"):
  echo item.payload

let hits = db.retrieve(@[1.0'f32, 0.0'f32], ring = "docs/japan", budget = 8)
```

If the caller does not know the right ring, it should inspect the atlas or ring
descriptions first:

```nim
echo db.atlas()
```

This is closer to reading schema and table statistics before writing a SQL
query than to scanning every collection and filtering afterward.

## Tradeoffs

RocheDB is a poor fit when:

- the application cannot express meaningful rings;
- most queries require arbitrary cross-ring aggregation;
- every field needs independent secondary-index lookup;
- strict global transaction order is mandatory;
- the main workload is full-corpus analytics.

RocheDB is a good fit when:

- records naturally belong to tenants, users, topics, regions, dates, or state
  scopes;
- overfetching and application-side filtering are expensive;
- AI/RAG retrieval should avoid unrelated chunks before reranking or prompting;
- flexible documents are useful, but read scope is predictable;
- recovery, sync, dump, import, and authorization boundaries should follow the
  same data placement model.

## Short Positioning

Use this wording when describing RocheDB:

```text
RocheDB is a placement-aware NoSQL/document/vector store. It keeps NoSQL-style
document flexibility, but expects meaningful ring placement so reads can avoid
unrelated working sets.
```

Avoid this wording:

```text
RocheDB is a MongoDB-compatible replacement.
```

That is not the design goal.
