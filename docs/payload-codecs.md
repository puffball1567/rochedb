---
layout: default
title: Payload Codecs
---

# Payload Codecs

KoutenDB stores payloads as binary-safe byte strings and records a format
identifier with each document. The supported identifiers are:

| Codec | Intended use | Core behavior |
|---|---|---|
| `raw` | Text or arbitrary application bytes | Stored without interpretation |
| `json` | JSON documents and projections | Stored as bytes; eligible for JSON projection and patch APIs |
| `nif` | Pre-encoded NIF text/token data | Stored without conversion |
| `bif` | Pre-encoded BIF binary data | Stored without conversion |

NIF/BIF support in the core means format-aware storage, WAL persistence,
cluster transport, handoff, transaction apply, Universe sync, list, get, and
retrieval. KoutenDB does not bundle a NIF/BIF encoder or decoder into the core.
Applications can provide already encoded bytes directly, or use the optional
[`koutendb-nif`](https://github.com/puffball1567/koutendb-nif) adapter backed by
[`nifkit`](https://github.com/puffball1567/nifkit). This keeps the database
independent of one codec implementation while still providing an official OSS
adapter path.

## Ring payload profiles

A ring can declare the payload format normally used within it. This declaration
is persisted separately from records and is available to applications, CLI
tools, and optional format adapters:

```bash
kouten ring-profile --data=/var/lib/kouten --ring=artifacts \
  --codec=bif --format-version=1
kouten ring-profile --data=/var/lib/kouten --ring=documents \
  --codec=nif --charset=UTF-8 --format-version=1
```

The profile contains `defaultCodec`, `charset`, and `formatVersion`. `charset`
describes text encodings such as NIF text; it does not apply to BIF binary
payloads. A record's explicit codec always wins over the ring default, so a
profile change never reinterprets bytes already stored. `kouten put` defaults to
`--codec=auto` and uses the ring default; pass an explicit codec to override it.

## Embedded API

```nim
import koutendb
import std/json

var db = open()

let jsonId = db.put(%*{"title": "KoutenDB"}, ring = "docs")
let bifId = db.put(encodedPayload(bifBytes, pcBif), ring = "docs")

let stored = db.getEncoded(bifId)
doAssert stored.codec == pcBif
doAssert stored.data == bifBytes

db.close()
```

The string overload of `put` remains backward compatible and uses `raw`. The
`JsonNode` overload uses `json` automatically.

## Runnable Demos

From a KoutenDB source checkout:

```sh
examples/payload_codecs_demo.sh
examples/payload_codecs_cluster_demo.sh
```

The embedded demo writes JSON, NIF-tagged bytes, and BIF-tagged bytes, reopens
the persistent store, reuses a prepared selection, and shows that JSON
projection is rejected for NIF/BIF records. The cluster demo shows negotiated
codec metadata and verifies that a connection which does not opt in still sees
the legacy three-field `VAL` header.

## CLI

```sh
kouten put --ring=docs --in=document.bif --codec=bif
kouten put --ring=docs --payload='{"title":"KoutenDB"}' --codec=json
kouten get --ring=docs --filter='{"id":"RAW_ID"}'
```

These examples use the default embedded data directory. Set `KOUTEN_DATA` or
pass `--data=DIR` when you want a specific local store, or pass
`--peers=host:port,...` when talking to a `koutend` cluster.

### Put and get examples

Use an explicit codec when writing payloads whose type matters. Without an
explicit codec, `put` stores the payload as `raw` unless `--codec=auto` resolves
to the ring's payload profile.

```sh
# JSON: filter and projection work because the record is tagged as json.
kouten put --ring=docs/japan \
  --payload='{"title":"Hello","status":"draft"}' \
  --codec=json
kouten get --ring=docs/japan \
  --filter='{"status":"draft"}' \
  --selection='{ title }'

# NIF text: KoutenDB stores the bytes and keeps codec=nif metadata.
kouten put --ring=docs/nif --in=sample.nif --codec=nif
kouten get --ring=docs/nif --limit=1

# BIF binary: KoutenDB stores the bytes and keeps codec=bif metadata.
kouten put --ring=docs/bif --in=sample.bif --codec=bif
kouten get --ring=docs/bif --limit=1

# Debug or transport-safe BIF views.
kouten get --ring=docs/bif --limit=1 --view=base64
kouten get --ring=docs/bif --limit=1 --view=hex

# Raw: plain bytes/text with no format interpretation.
kouten put --ring=logs/raw --payload='plain text payload' --codec=raw
kouten get --ring=logs/raw --limit=1
```

`get` always returns the same page shape. Use `--limit=1` when you only want one
record:

```json
{
  "ring": "docs/bif",
  "count": 1,
  "items": [
    {
      "codec": "bif",
      "encoding": "base64",
      "payload": "AQIDBA=="
    }
  ]
}
```

The stored codec metadata drives display. NIF text is returned as text. BIF
uses the optional adapter when available and falls back to base64 when it is
not.

The default view is `auto`, which prints text/NIF with codec metadata. For BIF,
it first tries to use an optional adapter and prints decoded NIF text when one
is available. The lookup order is `KOUTENDB_NIF_TOOL`, `koutendb-nif`, then
`nif_file_tool`. The adapter command must support
`decode --in=input.bif --out=output.nif`. If no adapter is available, `auto`
falls back to base64. Use `--view=hex` for byte-level inspection or
`--view=raw` for the original raw payload bytes. Decoding BIF back into NIF text
is intentionally adapter-side; the published `koutendb-nif` adapter provides
that path without making NIF/BIF parsing a KoutenDB core dependency.

### Ring profile and auto codec

Ring profiles are useful when one ring is intended to contain one payload
format. The profile does not rewrite existing records; it only supplies a
default for future `--codec=auto` writes.

```sh
kouten ring-profile --data=./data \
  --ring=docs/nif \
  --codec=nif \
  --charset=UTF-8 \
  --format-version=1

kouten put --data=./data --ring=docs/nif --in=sample.nif --codec=auto
kouten get --data=./data --ring=docs/nif --limit=1
```

## C ABI

The additive C ABI functions preserve the existing `kouten_put` and `kouten_get`
contract while exposing format metadata to C/C++ and FFI consumers:

```c
kouten_id id;
kouten_put_codec(db, "artifacts/bif", bytes, byte_len, KOUTEN_CODEC_BIF, &id);

size_t len;
int codec;
void *stored = kouten_get_codec(db, id, &len, &codec);
/* codec == KOUTEN_CODEC_BIF; release stored with kouten_free(stored). */
```

`kouten_put_vec_codec` is the equivalent vector-bearing write call. The C ABI
contract smoke verifies this path in `examples/cabi_contract.c`.

## Projection Boundary

`query`, `patch`, and prepared selections are JSON operations. KoutenDB rejects
their use on explicitly tagged `nif` and `bif` records instead of attempting to
interpret those bytes as JSON. `raw` remains projection-compatible for legacy
records and older drivers that stored JSON before codec metadata existed.

## Prepared Selections

KoutenDB does not execute SQL, so its prepared-statement-like API compiles the
GraphQL-style projection rather than preparing an SQL string:

```nim
let fields = prepareSelection("{ title author { name } }")
let first = db.query(firstId, fields)
let second = db.query(secondId, fields)
```

`prepareSelection` validates and parses the selection once. Embedded queries
reuse that parsed tree directly. Cluster nodes also keep a bounded cache of
validated selection trees. The selection grammar contains field names only;
payload values are never interpolated into it.

## Compatibility And Byte Order

The codec name is optional on the wire and in older WAL records. Missing codec
metadata is interpreted as `raw`, so existing data and drivers remain readable.
Clients can call the additive `CODECS` wire command to discover the identifiers
accepted by a node. `CODECMETA ON` opts the connection into codec fields on
response headers; clients that do not negotiate keep the original header shape.

KoutenDB treats NIF/BIF payload bytes as opaque. Their byte order is therefore a
property of the selected format specification, not the host CPU. This is
separate from KoutenDB vector bytes, which are always canonical little-endian
IEEE-754 `float32` on the TCP wire.
