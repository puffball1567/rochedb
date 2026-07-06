# RocheDB Python Driver

Pure Python TCP driver for RocheDB `roched`.

This driver intentionally talks to the high-level wire frames:

- `PUTR`: write by human-readable `ring`
- `GETID`: read by returned ID
- `QRYID`: GraphQL-style projection by returned ID

It does not reimplement RocheDB's `ringKey` / `period` / `head` derivation.

## Example

```python
from rochedb import RocheClient

db = RocheClient.connect("127.0.0.1:17301")
doc_id = db.put("japan/tokyo", b'{"title":"Tokyo","country":"JP"}',
                vector=[1.0, 0.0])

print(db.get(doc_id))
print(db.query(doc_id, "{ title }"))

db.close()
```

## Status

This is a minimal native wire driver. It currently supports:

- persistent TCP connections
- `put`
- `get`
- `query`
- typed `RocheId`
- one reconnect retry
- optional timeout

Not implemented yet:

- auth / secret-key encrypted transport
- connection pool
- batch get
- package publishing metadata
