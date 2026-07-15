# Technical FAQ

This document answers the questions RocheDB is most likely to receive from
database engineers who are seeing the project for the first time.

RocheDB is still a technical preview. The goal of this FAQ is not to overstate
the current implementation. It is to make the design boundaries clear enough
that the project can be evaluated on the right terms.

## Is a ring just partitioning?

Partly, but not only.

A RocheDB `ring` has a partition-like effect because it narrows the candidate
working set before a read. If an application writes records into
`docs/japan/support`, a later read can start there instead of scanning a broad
collection.

The difference is that RocheDB treats the ring as a first-class coordinate used
by several parts of the system:

- read scope;
- vector/RAG candidate reduction;
- projection and filter scope;
- dump/import boundary;
- authorization and galaxy topology boundary;
- physical locality reporting;
- future sync, recovery, and compaction planning.

Traditional partitioning is usually an implementation detail behind a table or
collection. In RocheDB, placement is part of the public data model. The
application, import rule, or operator intentionally chooses a coordinate that
later reads can use directly.

That does not make ring design free. If the application chooses poor rings,
RocheDB cannot magically recover good locality. The benefit appears when ring
placement matches a real access pattern.

## Is stellar locality a join?

No.

A `stellar` lens is a visibility lens over related ring coordinates. It lets a
read start from a meaningful neighborhood without copying payloads into one
large document and without scanning unrelated rings.

Example:

```bash
roche stellar attach --stellar=commerce/order/A-001 --ring=users/123
roche stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
roche stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001

roche get --stellar=commerce/order/A-001
roche get --stellar=commerce/order/A-001 --subring=shops
```

This is weaker than a relational join because it does not enforce relational
constraints or global referential integrity. It is also lighter than a join for
workloads where the application already knows which coordinates are useful
neighbors.

The intended use is "read nearby related coordinates", not "run arbitrary
cross-corpus relational algebra".

## Is this a secondary index?

Not in the usual sense.

RocheDB's current secondary access direction is deliberately conservative:
secondary mechanisms should guide a read back toward ring-local data instead of
becoming a competing primary layout.

Filters and projections narrow the result after the local scope is chosen.
Stellar lenses expose related local coordinates. Neither one is currently a
general-purpose global secondary-index engine.

This is an intentional tradeoff. RocheDB is trying to make locality the primary
optimization primitive. A broad secondary-index engine may be useful later, but
it must not destroy the main layout advantage by forcing scattered record
fetches for every common query.

## Is the orbital model just consistent hashing?

The simplest owner calculation has a ring-like shape and should be understood
conservatively. It maps an angle to an owner segment. That part is not the main
reason RocheDB reduces scanned records in the current benchmarks.

The current working-set reduction mostly comes from explicit ring placement:
the read starts from a smaller semantic coordinate instead of the whole corpus.

The orbital part matters for a different reason. RocheDB stores compact
coordinate metadata and can compute ownership and future placement locally. The
model is inspired by orbital mechanics because time, position, proximity, and
movement are useful concepts for cluster routing, scheduling, and recovery.

Current limitation:

- simple owner segmentation can remap too much data when the number of nodes
  changes;
- this must be improved before making stronger distributed-database claims.

The planned direction is to keep the deterministic coordinate model, but replace
the naive node-count mapping with persisted arcs, node weights, virtual arcs, or
a topology epoch. That would preserve the coordinate idea while reducing
unnecessary remapping during membership changes.

## Where do the benchmark improvements come from?

The current large reductions come from avoiding unrelated candidates before
later work begins.

For example, if a corpus has 100 meaningful rings and a query can start from one
ring, then RocheDB can avoid scanning most records before filtering, ranking,
projection, or LLM/RAG context construction.

That is not the same claim as "RocheDB is always faster than every database."
It is a narrower claim:

> When the application has meaningful locality, RocheDB can make that locality
> part of the retrieval path and reduce the working set.

The benchmark scripts are included so the numbers can be reproduced and
challenged:

- [Benchmark notes](rochedb-bench.md)
- [Benchmark comparison tables](benchmark-comparison.md)

## How are records grouped on disk?

Persistent embedded stores use an append-only WAL.

Before compaction, physical order mostly follows write order. If writes are
interleaved across rings, the WAL is also interleaved. RocheDB exposes locality
metrics so this can be measured instead of guessed:

```bash
roche locality --data=/var/lib/rochedb
roche locality --data=/var/lib/rochedb --metrics
```

Compaction currently writes live particle records in stable `(ringKey, seq)`
order. This groups live records by ring in the compact snapshot.

This is not yet a full layout optimizer. It is the first physical measurement
surface and a simple compaction behavior that aligns with the primary ring
layout.

See [Data Locality](data-locality.md).

## What happens when write patterns are messy?

Messy writes are expected.

Backfills, imports, deletes, and interleaved writes can fragment physical
locality. RocheDB's current answer is:

1. keep normal writes append-only and simple;
2. expose locality metrics;
3. compact live records into ring order;
4. use stellar attach/detach to adjust visibility without copying payloads.

Future work should add heavier tests for random writes, delete-heavy workloads,
backfills, hot/cold ring skew, and read latency before/after compaction.

## Is RocheDB production-ready?

Not as a drop-in production replacement for PostgreSQL, Redis, MongoDB, Apache
Arrow, or a mature vector database.

It is closer to a research OSS / technical preview with real implementation,
tests, demos, drivers, and benchmarks.

Implemented areas include:

- embedded Nim API;
- CLI;
- server mode;
- C ABI;
- Rust, JavaScript/TypeScript, PHP, and Python package foundations;
- auth;
- TLS transport;
- WAL persistence and recovery tests;
- cluster and universe smoke tests;
- payload codec metadata;
- NIF/BIF adapter path;
- atomic embedded batch helpers;
- cooperative ring/stellar locks;
- locality demos and benchmark helpers.

Important areas that still need hardening:

- dynamic cluster membership with minimal remapping;
- longer mixed-version protocol compatibility;
- deeper failure-injection tests;
- larger real-workload benchmarks;
- production operations documentation;
- broader driver parity.

## What is RocheDB best suited for today?

RocheDB is most interesting when the application already has meaningful locality:

- RAG and AI document corpora;
- prompt/context stores;
- tenant- or user-scoped web data;
- product/category/topic knowledge;
- regional content;
- local application state;
- game or simulation data where nearby entities are commonly read together.

It is a poor fit when the main workload is arbitrary full-corpus analytics,
global OLTP ledgers, broad ad-hoc secondary-index queries, or strict relational
constraint enforcement.

## One-sentence positioning

Use this when describing RocheDB:

```text
RocheDB is a placement-aware NoSQL document/vector store that makes
application-level locality part of the storage and retrieval model.
```

Avoid this:

```text
RocheDB is a universal replacement for PostgreSQL, Redis, MongoDB, or vector
databases.
```
