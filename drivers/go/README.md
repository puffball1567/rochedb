# OrbeliasDB Go Driver

Minimal Go wrapper over the OrbeliasDB C ABI.

```go
db, err := orbeliasdb.Open(8)
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

Build the OrbeliasDB shared library first:

```bash
scripts/build_capi.sh
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
