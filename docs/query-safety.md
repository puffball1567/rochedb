# Query Safety

RocheDB does not execute SQL, so its query-safety surface is different from a
SQL database.

The two important pieces are:

- prepared selections for projection;
- typed filter builders for read filters.

Both are designed to avoid string-concatenated query text while keeping
RocheDB's read path centered on a `ring` or `stellar` coordinate.

## Prepared Selections

Selections are GraphQL-style projections over JSON payloads:

```nim
let fields = prepareSelection("{ title author { name } }")
let first = db.query(firstId, fields)
let second = db.query(secondId, fields)
```

`prepareSelection` validates and parses the selection once. Embedded reads reuse
the parsed tree directly. Cluster nodes also keep a bounded cache of validated
selection trees.

The selection grammar contains field names only. Payload values are not
interpolated into it.

## Typed Filter Builders

Filters are still represented as JSON objects internally and on the wire. That
keeps the CLI, C ABI, and existing drivers compatible.

For application code, RocheDB also provides a builder so callers do not need to
construct filter JSON by string concatenation:

```nim
let filter = rocheFilter().eq("status", "draft").eq("kind", "order")

let page = db.readRing("docs/japan", defaultReadOptions().withFilter(filter))
```

The same filter can be used with stellar reads:

```nim
let page = db.readStellar("commerce/order/A-001",
  defaultStellarOptions().withFilter(rocheFilter().eq("kind", "shop")))
```

ID reads can also be built without manually stringifying the ID:

```nim
let page = db.readRing("users", defaultReadOptions().withFilter(
  rocheFilter().id(userId)))
```

Supported builder values:

- strings;
- integers;
- floats;
- booleans;
- explicit `JsonNode` values;
- RocheDB IDs through `id(id)`.

## Scope Comes First

The filter builder is not intended to turn RocheDB into an ad-hoc global query
engine.

RocheDB's read model remains:

1. choose a `ring` or `stellar` coordinate;
2. optionally narrow with `subring`;
3. apply typed filters inside that local scope;
4. project only the requested fields.

This keeps query safety aligned with the main RocheDB idea: avoid unrelated
working sets before downstream work begins.

## Compatibility

These two forms are equivalent:

```nim
let a = db.readRing("docs", RocheReadOptions(
  filter: %*{"status": "draft"},
  selection: "{ title }"))

let b = db.readRing("docs", defaultReadOptions()
  .withFilter(rocheFilter().eq("status", "draft")))
```

The builder-produced filter is a defensive JSON object copy. It can be passed
through the same API paths that already accept `JsonNode` filters.
