# RocheDB Kotlin Driver

Minimal Kotlin-first JVM binding for RocheDB through a small JNI bridge over the
stable C ABI.

The public API is Kotlin-first while remaining Java-compatible at the bytecode
level. Android-specific packaging is intentionally deferred; this driver first
targets JVM servers and desktop tooling.

## Requirements

- JDK 21
- Kotlin compiler
- C++17 compiler
- `lib/librochedb.so` built from `src/rochedb_capi.nim`

Build the native library from the repository root:

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
```

Run the Docker smoke test:

```sh
drivers/kotlin/docker-test.sh
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
- Maven Central publishing workflow
- Android packaging evaluation
- expanded compatibility suite shared with the other language drivers

