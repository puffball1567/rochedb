# RocheDB Driver / FFI Roadmap

RocheDB drivers are developed on two tracks.

1. **Native wire driver**
   - Production cluster driver that talks to `roched` over TCP.
   - Uses `PUTR/GETID/QRYID`, so language drivers do not reimplement
     `ringKey` / `period` / `head` internals.

2. **C ABI / FFI**
   - Foundation for embedded mode, high-speed local use, and language bindings.
   - Based on `include/rochedb.h` and `src/rochedb_capi.nim`.

## Priority

| Priority | Target | Reason | Status |
|---:|---|---|---|
| 1 | Python native wire driver | AI/RAG/research/data-processing entry point | Minimal done |
| 2 | Node.js / TypeScript / Bun native wire driver | Web API / SaaS / Studio / GUI / local AI client entry point | Minimal done; Bun smoke added |
| 3 | C ABI / FFI | Embedded / extension / language binding foundation | ABI version / last error / vector put / auth connect / retrieve / batch get / atlas added |
| 4 | Rust driver | High-performance infrastructure / proxy / gateway | Minimal C ABI wrapper done. Native wire comes later |
| 5 | Go driver | Cloud backend / ops tooling | Minimal C ABI wrapper done. Native wire comes later |
| 6 | PHP driver | Laravel / existing business web systems | Minimal FFI / C ABI wrapper done. Docker smoke added |
| 7 | Swift driver | Apple local AI client / browser companion / app state | Minimal C ABI wrapper done. Docker smoke added |
| 8 | C# driver | Generic .NET / backend entry point. Unity asset stays separate | Minimal C ABI wrapper done |
| 9 | C++ driver | Generic native / engine integration base. Unreal plugin stays separate | Minimal C ABI wrapper done |
| 10 | Kotlin-first JVM driver | JVM backend and Android path, Java-compatible | Minimal JNI / C ABI wrapper done |
| 11 | DB trust work | Crash recovery, compatibility suite, failure benchmarks, operational docs | Next |
| 12 | React Native / WASM local state | Browser and React Native local/global state boundary | Post-v0.1 candidate; handled with WASM line |

## Minimum Common API

Each native driver first aligns on the following API:

- `connect(peers, timeout)`
- `close`
- `put(ring, payload, vector?) -> RocheId`
- `get(id) -> bytes | nil`
- `query(id, selection) -> bytes | nil`
- `health(node?)`
- typed `RocheId`
- one reconnect retry

The next layer adds auth / secret-key transport, connection pooling, package
publishing, and protocol compatibility tests.

The C ABI uses `examples/cabi_contract.c` as its contract smoke test.
Rust, Go, PHP, Swift, C#, and C++ first wrap the C ABI safely. Native TCP drivers can
be added later without changing their ownership and error contracts.

PHP can be verified with `drivers/php/docker-test.sh` when local PHP does not
provide FFI. Swift can be verified with `drivers/swift/docker-test.sh` on Linux.
The shared compatibility suite verifies the C ABI contract, embedded FFI
wrappers, and native wire drivers:

```sh
scripts/driver_compat.sh
```

By default it does not run Docker-backed drivers. Enable those with:

```sh
ROCHE_COMPAT_DOCKER=1 scripts/driver_compat.sh
```

Cluster transaction smoke can be run separately:

```sh
scripts/cluster_tx_smoke.sh
```

Individual C#, C++, and Kotlin checks can be run with:

```sh
dotnet run --project drivers/csharp/ContractSmoke/ContractSmoke.csproj
g++ -std=c++17 -Iinclude -Idrivers/cpp/include drivers/cpp/examples/contract_smoke.cpp -Llib -lrochedb -o /tmp/roche_cpp_smoke
LD_LIBRARY_PATH=lib /tmp/roche_cpp_smoke
drivers/kotlin/docker-test.sh
```

## Guardrail

Drivers do not reimplement RocheDB placement rules. They pass a ring name and
let RocheDB issue the ID. This keeps language drivers stable as long as the wire
protocol / C ABI contract remains compatible.
