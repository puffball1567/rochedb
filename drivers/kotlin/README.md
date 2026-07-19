# OrbeliasDB Kotlin Driver

Minimal Kotlin-first JVM binding for OrbeliasDB through a small JNI bridge over the
stable C ABI.

The public API is Kotlin-first while remaining Java-compatible at the bytecode
level. Android-specific packaging is intentionally deferred; this driver first
targets JVM servers and desktop tooling.

## Requirements

- JDK 21
- Kotlin compiler
- C++17 compiler
- `lib/liborbeliasdb.so` built from `src/orbeliasdb_capi.nim`

Build the native library from the repository root:

```sh
scripts/build_capi.sh
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

