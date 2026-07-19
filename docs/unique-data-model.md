# Unique Data Model And Operating Patterns

OrbeliasDB's current direction is not only "a faster key/value path". Its more
important direction is a placement-aware data model: the application stores
records at meaningful coordinates, and those coordinates become part of the
read path, maintenance path, dump/import boundary, and recovery topology.

This document describes the OrbeliasDB-specific shapes that are emerging from the
current implementation.

## Core Idea

Most databases separate these concerns:

- where data is stored;
- how related data is found;
- how a query is tuned;
- how data is dumped, restored, synchronized, or isolated.

OrbeliasDB tries to make those concerns line up. A `ring` is not just a collection
name. It is a coordinate that can reduce the working set before filtering,
reranking, projection, or LLM/context processing.

## OrbeliasDB-Specific Shapes

| Shape | What It Expresses | Why It Matters |
|---|---|---|
| `ring` | A meaningful locality coordinate such as `users/123`, `docs/japan`, or `tenant/acme/orders` | Reads can start from a smaller candidate set instead of scanning a broad collection |
| ring hierarchy | Natural parent/child scope such as `users/123/orders` | Listing, dump, backup, and retrieval scope can follow application structure |
| `stellar` lens | A coordinate-centered visibility lens over existing rings | Related records can be read together without copying payloads or creating a hidden global join |
| `subring` | A narrowed field of view inside a ring or stellar read | The caller can ask for a nearby subset such as `orders` or `billing` |
| projection / selection | Return only requested fields | Reduced ring scope can be combined with reduced payload shape |
| cooperative coordinate lock | Opt-in lock around a ring or stellar lens | High-integrity workflows can coordinate updates without slowing ordinary reads/writes |
| galaxy | Isolation boundary for authentication, blast radius, and deployment topology | Different logical databases can use the same engine without forcing one global trust domain |
| universe sync | Delayed convergence / recovery topology | Same-name galaxies can eventually converge across topology boundaries without turning all writes into one global transaction |

## Example: User, Shop, And Order

A traditional relational design often models this with tables and joins:

```text
users.id = orders.user_id
shops.id = orders.shop_id
```

OrbeliasDB can store the same facts as separate coordinates:

```bash
orbelias put --ring=users/123 \
  --payload='{"kind":"user","name":"Alice"}' --codec=json

orbelias put --ring=shops/1123 \
  --payload='{"kind":"shop","name":"Orbit Store"}' --codec=json

orbelias put --ring=orders/A-001 \
  --payload='{"kind":"order","orderNo":"A-001","total":42}' --codec=json
```

Then it can attach those existing coordinates to a stellar lens:

```bash
orbelias stellar attach --stellar=commerce/order/A-001 --ring=users/123
orbelias stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
orbelias stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001
```

Now the order-centered read can see the nearby facts:

```bash
orbelias get --stellar=commerce/order/A-001
```

The caller can narrow the visible field:

```bash
orbelias get --stellar=commerce/order/A-001 --subring=shops
orbelias get --stellar=commerce/order/A-001 --filter='{"kind":"order"}'
orbelias get --stellar=commerce/order/A-001 --selection='{ kind name orderNo total }'
```

Attach/detach does not copy the payload. It changes the visibility metadata of
the stellar lens:

```bash
orbelias stellar detach --stellar=commerce/order/A-001 --ring=shops/1123
```

This is not the same as a relational constraint. It is also not a global
secondary index. It is a locality lens that points reads toward coordinates that
are expected to be useful together.

When an application needs stronger coordination around the same shape, it can
use opt-in locks and atomic batches:

```nim
db.withStellarLock("commerce/order/A-001", proc() =
  db.transaction(proc(tx: OrbeliasTx) =
    discard tx.put("""{"kind":"event","status":"processing"}""",
                   ring = "orders/A-001/events")
  )
)
```

Normal `put`, `get`, `list`, and `retrieve` calls do not check these locks. The
high-integrity path is explicit so the lightweight NoSQL path stays lightweight.

## Why This Can Help Data Processing

This model can help when the expensive part is not only the final operation, but
the amount of unrelated data that reaches it.

Examples:

- RAG and agent context: fewer unrelated chunks need to be scanned, reranked, or
  placed into a context window.
- Web systems: user, tenant, product, region, or lifecycle reads can avoid broad
  application-side filtering.
- Operational recovery: dump, restore, sync, and authorization can follow the
  same locality boundaries used for reads.
- Physical locality: compaction can use ring order today, and future compaction
  can use stellar lens metadata as an additional placement hint.

## Where It Is Not A Fit

OrbeliasDB should not pretend this model replaces every database shape.

It is weaker when:

- queries are mostly ad-hoc full-corpus analytics;
- every field needs independent secondary-index lookup;
- strict relational constraints are the main requirement;
- global serial transaction order is mandatory;
- the application cannot express useful placement.

The stronger claim is narrower: when the application has meaningful locality,
OrbeliasDB can make that locality part of the database model instead of rebuilding
it after every query.

## Demo

Run:

```bash
examples/stellar_data_model_demo.sh
```

The demo inserts user, shop, and order records into separate rings, attaches
them to a stellar lens, reads them together, narrows the read with `--subring`,
then detaches one coordinate to show that visibility changes without deleting
payloads.
