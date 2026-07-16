# Use Case Recipes

This page shows practical RocheDB layouts for ordinary applications. The goal
is not to replace every database pattern. It is to show where RocheDB's
coordinate-first model removes broad scans, avoids manual join plumbing, or
keeps high-integrity workflows explicit.

The examples use the CLI because it is easy to reproduce, but the same shapes
map to the Nim API and external drivers:

- write into meaningful `ring` coordinates;
- use `--near` when a new record should live close to an existing coordinate;
- use `--stellar` when several existing coordinates should be visible through
  one lens without copying payloads;
- use `--filter`, `--selection`, `--limit`, and pagination to keep responses
  small;
- use cooperative locks and atomic batches only around workflows that need
  integrity guards.

## List To Detail

Many web screens have a broad list view and a focused detail view. In RocheDB,
the list can live at a broader coordinate while the detail view reads the
specific coordinate and nearby subrings.

```sh
roche put --ring=users --payload='{"id":"u123","name":"Ada","status":"active"}' --codec=json
roche put --near=users/123 --ring=profile --payload='{"kind":"profile","name":"Ada","tier":"pro"}' --codec=json
roche put --near=users/123 --ring=orders --payload='{"kind":"order","orderNo":"A-001","total":120}' --codec=json
roche put --near=users/123 --ring=billing --payload='{"kind":"billing","plan":"annual"}' --codec=json

roche get --ring=users --limit=20 --selection='{ id name status }'
roche get --ring=users/123 --subring=profile,orders,billing --selection='{ kind name tier orderNo total plan }'
```

The detail read starts from `users/123`. It does not need to scan every order or
billing record globally.

Nim API shape:

```nim
var listOpts = defaultReadOptions()
listOpts.selection = "{ id name status }"
let page = db.readRing("users", listOpts)

var detailOpts = defaultStellarOptions()
detailOpts.subrings = @["profile", "orders", "billing"]
let detail = db.readStellar("users/123", detailOpts)
```

## Membership / Account Management

Account data often has a natural owner coordinate. Put account-scoped records
near the account, then narrow by subring or filter.

```sh
roche put --ring=accounts/acme --payload='{"kind":"account","name":"Acme"}' --codec=json
roche put --near=accounts/acme --ring=members --payload='{"kind":"member","user":"u1","role":"owner"}' --codec=json
roche put --near=accounts/acme --ring=members --payload='{"kind":"member","user":"u2","role":"viewer"}' --codec=json
roche put --near=accounts/acme --ring=audit --payload='{"kind":"audit","event":"member.invited","user":"u2"}' --codec=json

roche get --ring=accounts/acme --subring=members --filter='{"role":"owner"}'
roche get --ring=accounts/acme --subring=audit --limit=10
```

This is a good fit for SaaS systems where most screens are scoped by tenant,
account, workspace, project, or user.

## Inventory With A Cooperative Lock

RocheDB should not be positioned as a financial ledger. But ordinary inventory
or status updates can use an opt-in coordinate lock plus an atomic batch so that
application code does not accidentally perform partial writes.

CLI sketch:

```sh
roche put --ring=shops/1123/products/sku-9 --payload='{"kind":"stock","sku":"sku-9","available":12}' --codec=json
roche get --ring=shops/1123/products/sku-9 --limit=1
```

Nim API shape:

```nim
db.withRingLock("shops/1123/products/sku-9", proc() =
  db.transaction(proc(tx: var RocheTx) =
    tx.update(stockId, %*{
      "kind": "stock",
      "sku": "sku-9",
      "available": 11
    })
    tx.put(%*{
      "kind": "reservation",
      "orderNo": "A-001",
      "sku": "sku-9"
    }, ring = "shops/1123/products/sku-9/reservations")
  )
)
```

Use this for workflows where a ring coordinate is the natural contention point.
Keep the lightweight path for normal reads and writes.

## Webhook Idempotency

Webhook handlers often need to accept retries without duplicating effects. A
simple RocheDB pattern is to keep the idempotency key in a dedicated ring and
wrap the handler in a ring lock.

```nim
let keyRing = "webhooks/stripe/events/evt_123"

db.withRingLock(keyRing, proc() =
  if db.countByRing(keyRing) > 0:
    return

  db.transaction(proc(tx: var RocheTx) =
    tx.put(%*{"kind": "webhook-seen", "event": "evt_123"}, ring = keyRing)
    tx.put(%*{"kind": "order-event", "event": "paid"}, ring = "orders/A-001/events")
  )
)
```

This keeps duplicate prevention explicit and local to the coordinate that owns
the external event.

## Tenant / SaaS Isolation

For SaaS systems, encode the tenant into the ring path. That makes reads,
dumps, imports, backup scopes, and operational reasoning line up with the same
boundary.

```sh
roche put --ring=tenant/acme/users --payload='{"id":"u1","name":"Ada"}' --codec=json
roche put --ring=tenant/acme/orders/2026 --payload='{"orderNo":"A-001","total":120}' --codec=json
roche put --ring=tenant/globex/users --payload='{"id":"u9","name":"Grace"}' --codec=json

roche get --ring=tenant/acme/users --limit=50
roche get --ring=tenant/acme --subring=users,orders
```

When stronger isolation is needed, use separate galaxies with separate
credentials. Use ring paths for locality inside a galaxy, and galaxies for
authentication and blast-radius boundaries.

## Product / Shop / User Neighborhoods

Some screens need a relationship lens rather than a single hierarchy. For
example, an order may be related to a user, a shop, and a product. Store each
coordinate naturally, then attach them to one stellar lens.

```sh
roche put --ring=users/123 --payload='{"kind":"user","name":"Ada"}' --codec=json
roche put --ring=shops/1123 --payload='{"kind":"shop","name":"North Shop"}' --codec=json
roche put --ring=products/sku-9 --payload='{"kind":"product","name":"Keyboard"}' --codec=json
roche put --ring=orders/A-001 --payload='{"kind":"order","orderNo":"A-001"}' --codec=json

roche stellar attach --stellar=commerce/order/A-001 --ring=users/123
roche stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
roche stellar attach --stellar=commerce/order/A-001 --ring=products/sku-9
roche stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001

roche get --stellar=commerce/order/A-001
roche get --stellar=commerce/order/A-001 --filter='{"kind":"shop"}'
```

This is the "telescope" model: the stellar coordinate defines the field of
view. Payloads are not copied. Attach/detach changes visibility.

## RAG Corpus Layout

For RAG or AI document storage, put chunks into rings that match the natural
retrieval scope. This can reduce candidates before reranking, prompting, or
token construction.

```sh
roche put --ring=docs/security/passwords --payload='{"title":"Password reset","text":"..."}' --codec=json
roche put --ring=docs/security/oauth --payload='{"title":"OAuth setup","text":"..."}' --codec=json
roche put --ring=docs/billing/invoices --payload='{"title":"Invoice download","text":"..."}' --codec=json

roche get --ring=docs/security --subring=passwords,oauth --selection='{ title text }'
roche retrieve --ring=docs/security --budget=8
```

The point is not that RocheDB magically understands documents. The application,
import rule, or pipeline gives RocheDB useful coordinates, and RocheDB makes
those coordinates part of the read path.

## When Not To Use These Patterns

Avoid forcing RocheDB into workflows that need:

- globally strict serializable transactions across unrelated coordinates;
- large analytical scans where a columnar engine is the correct tool;
- secondary indexes over arbitrary fields as the primary access model;
- payment-ledger semantics where an external proven ledger/payment system is
  the right boundary.

RocheDB works best when the application already has meaningful locality:
tenant, account, user, product, region, topic, time, corpus section, or workflow
coordinate.
