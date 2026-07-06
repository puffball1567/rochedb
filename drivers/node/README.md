# RocheDB Node.js / Bun Driver

Dependency-free Node.js and Bun TCP driver for RocheDB `roched`.

The driver uses RocheDB's high-level wire frames:

- `PUTR`: write by human-readable `ring`
- `GETID`: read by returned ID
- `QRYID`: GraphQL-style projection by returned ID

It does not reimplement RocheDB's `ringKey` / `period` / `head` derivation.

## Example

```js
import { RocheClient } from "rochedb";

async function main() {
  const db = RocheClient.connect("127.0.0.1:17301");
  const id = await db.put("japan/tokyo", Buffer.from('{"title":"Tokyo"}'), {
    vector: [1.0, 0.0],
  });

  console.log((await db.get(id)).toString("utf8"));
  console.log((await db.query(id, "{ title }")).toString("utf8"));
  await db.close();
}

main().catch(console.error);
```

## Status

This is a minimal native wire driver. The same package is intended to run on
Node.js and Bun. It currently supports:

- persistent TCP connections
- `put`
- `get`
- `query`
- `health`
- typed `RocheId` declaration
- one reconnect retry
- optional timeout
- Bun smoke test via `bun test`

Not implemented yet:

- auth / secret-key encrypted transport
- connection pool
- batch get
- package publishing workflow

## Test

```bash
node --test test/*.test.js
bun test test-bun/*.test.ts
```
