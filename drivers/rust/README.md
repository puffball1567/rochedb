# RocheDB Rust Driver

Minimal Rust wrapper over the RocheDB C ABI.

```rust
use rochedb::RocheDb;

let db = RocheDb::open(8)?;
db.set_galaxy_description("Product and support knowledge")?;
db.set_ring_description("docs", "Documentation ring")?;
let id = db.put_vec("docs", b"hello", &[1.0, 0.0])?;
let value = db.get(id)?.unwrap();
let atlas = db.atlas(Some(&[1.0, 0.0]), 8)?;
# Ok::<(), rochedb::Error>(())
```

Build the RocheDB shared library first:

```bash
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
cargo test --manifest-path drivers/rust/Cargo.toml
```

This package intentionally starts as a thin C ABI wrapper. A native TCP driver can be added later without changing the safe embedded API.
