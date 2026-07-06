# RocheDB C++ Driver

Minimal C++17 wrapper for RocheDB through the stable C ABI.

This package is intentionally generic. Unreal-specific module packaging,
Blueprint bindings, editor tooling, and engine lifecycle integration should live
in a separate commercial Unreal plugin.

## Requirements

- C++17 compiler
- `lib/librochedb.so` built from `src/rochedb_capi.nim`

Build the native library from the repository root:

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
```

Build and run the smoke test:

```sh
g++ -std=c++17 -Iinclude -Idrivers/cpp/include drivers/cpp/examples/contract_smoke.cpp -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../../../lib' -o /tmp/roche_cpp_smoke
LD_LIBRARY_PATH=lib /tmp/roche_cpp_smoke
```

## Status

Implemented:

- embedded open / openDir
- authenticated cluster connect
- put / putVec
- get / batchGet
- query / retrieve / atlas
- locate / nextVisit / nextJoin
- ring and galaxy descriptions

Planned:

- native TCP driver
- package publishing workflow
- expanded compatibility suite shared with the other language drivers

