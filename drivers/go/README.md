# RocheDB Go Driver

Minimal Go wrapper over the RocheDB C ABI.

```go
db, err := rochedb.Open(8)
if err != nil {
    panic(err)
}
defer db.Close()

_ = db.SetGalaxyDescription("Product and support knowledge")
_ = db.SetRingDescription("docs", "Documentation ring")

id, err := db.PutVec("docs", []byte("hello"), []float32{1, 0})
if err != nil {
    panic(err)
}

value, ok, err := db.Get(id)
atlas, err := db.Atlas([]float32{1, 0}, 8)
_, _ = value, atlas
_ = ok
```

Build the RocheDB shared library first:

```bash
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
cd drivers/go
go test ./...
```

This package starts as a C ABI wrapper. A native TCP driver can be added later without changing the embedded API shape.

Current API:

- `Open`, `OpenDir`, `Connect`, `ConnectAuth`
- `Close`, `Now`, `Advance`
- `ConfigureRing`
- `SetGalaxyDescription`, `SetRingDescription`
- `Put`, `PutVec`, `Get`, `BatchGet`, `Query`
- `Retrieve`, `Atlas`
- `Locate`, `NextVisit`, `NextJoin`
