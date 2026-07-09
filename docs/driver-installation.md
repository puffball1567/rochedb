# RocheDB Driver Installation Guide

This document shows the current technical-preview setup for each language. The
English README and this file are the canonical driver installation references.

RocheDB drivers currently use two paths:

- Native TCP wire drivers for cluster-oriented use.
- C ABI wrappers for embedded/local use and language binding stability.

The CLI provides a small driver discovery surface:

```sh
roche driver list
roche driver info rust
roche driver install rust
roche driver install rust --manifest-path=/path/to/Cargo.toml
```

`driver install` prints the official package/repository path and setup command.
For Rust, target selection is shell-friendly: use `--manifest-path=FILE`,
`--project-dir=DIR`, `ROCHE_DRIVER_MANIFEST`, or `ROCHE_DRIVER_PROJECT`.
It does not execute package-manager commands unless `--execute` is passed.

The Nim package is available through Nimble. Rust and JavaScript / TypeScript
drivers are also published as language-native packages. Other non-Nim drivers
are still repository-local foundations, so those examples assume a local clone
of this repository.

## Optional FAISS Setup

The exact vector backend works without FAISS. For the FAISS bridge path, fetch
and build FAISS after cloning:

```sh
scripts/fetch_faiss.sh
scripts/setup_faiss_toolchain.sh   # only needed when system CMake is too old
scripts/build_faiss_bridge.sh
roche doctor
```

By default, `scripts/fetch_faiss.sh` fetches the configured FAISS tag and records
the actual commit in `third_party/faiss.version`. To pin an exact commit for a
reproducible build, set `ROCHE_FAISS_COMMIT`. See
[faiss-versioning.md](./faiss-versioning.md).

## Build the Native Library

Most C ABI wrappers need `lib/librochedb.so`:

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
```

For native wire driver tests, build `roched`:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roched -o:src/roched src/roched.nim
```

## Nim

Install from Nimble:

```sh
nimble install rochedb
roche --help
```

Then import the public API:

```nim
import rochedb

var db = rochedb.open(dataDir = "data")
let id = db.put("hello", ring = "docs")
echo db.get(id)
```

From a source checkout, run:

```sh
scripts/test_core.sh
```

## C ABI

Include `include/rochedb.h` and link `lib/librochedb.so`:

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
gcc examples/cabi_contract.c -Iinclude -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../lib' -o bin/cabi_contract
LD_LIBRARY_PATH=lib bin/cabi_contract
```

## Python

The Python driver is a native TCP wire driver.

```sh
nim c -d:release --nimcache:/tmp/nimcache_roched -o:src/roched src/roched.nim
python3 drivers/python/tests/test_driver.py
```

From an application in this repository:

```python
from drivers.python.rochedb import RocheClient

db = RocheClient.connect("127.0.0.1:17301")
doc_id = db.put("docs", b'{"title":"hello"}')
print(db.get(doc_id))
db.close()
```

For package-style local development, add `drivers/python` to `PYTHONPATH`.

## JavaScript / TypeScript

The published JavaScript / TypeScript driver is a Node-API wrapper over the
RocheDB C ABI:

- npm: [`rochedb` v0.1.2](https://www.npmjs.com/package/rochedb)
- repository: [`puffball1567/rochedb-js`](https://github.com/puffball1567/rochedb-js)

Install it in an application:

```sh
npm install rochedb
```

Build the RocheDB core shared library first and set `ROCHEDB_CORE_DIR` during
install/rebuild. See the driver repository README for the full setup flow.

The core repository also keeps a repository-local native TCP wire driver used
for protocol smoke tests:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roched -o:src/roched src/roched.nim
node --test drivers/node/test/*.test.js
bun test drivers/node/test-bun/*.test.ts
```

Repository-local wire-driver example:

```js
import { RocheClient } from "./drivers/node/src/index.js";

const db = RocheClient.connect("127.0.0.1:17301");
const id = await db.put("docs", Buffer.from('{"title":"hello"}'));
console.log((await db.get(id)).toString("utf8"));
await db.close();
```

## Rust

The Rust driver is published as a C ABI wrapper:

- crates.io: [`rochedb` v0.1.3](https://crates.io/crates/rochedb)
- repository: [`puffball1567/rochedb-rust`](https://github.com/puffball1567/rochedb-rust)

Install it in a Rust project:

```sh
cargo add rochedb
```

Or ask the RocheDB CLI to print the official setup command:

```sh
roche driver install rust --manifest-path=/path/to/Cargo.toml
```

Build the RocheDB core shared library first and set `ROCHEDB_CORE_DIR` or
`ROCHEDB_LIB_DIR` when building/testing the Rust project. See the Rust driver
repository README for the full setup flow.

## Go

The Go driver is a C ABI wrapper.

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
cd drivers/go
GOCACHE="${GOCACHE:-/tmp/roche-go-cache}" go test ./...
```

Use a local module replace until publication:

```text
replace github.com/rochedb/rochedb-go => ../drivers/go
```

## PHP

The PHP driver uses FFI over the C ABI. Local PHP must have `ext-ffi` enabled.

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
drivers/php/docker-test.sh
```

For Composer path development:

```json
{
  "repositories": [
    { "type": "path", "url": "../drivers/php" }
  ],
  "require": {
    "rochedb/rochedb": "*"
  }
}
```

## Swift

The Swift driver is a SwiftPM wrapper over the C ABI. Linux smoke is Docker
backed.

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
drivers/swift/docker-test.sh
```

Use a local package dependency:

```swift
.package(path: "../drivers/swift")
```

iOS/macOS packaging, sandbox paths, XCFramework packaging, and SwiftUI/UIKit
integration are still future validation work.

## C#

The C# driver is a generic .NET C ABI wrapper.

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
dotnet run --project drivers/csharp/ContractSmoke/ContractSmoke.csproj
```

Use a project reference until NuGet publication:

```xml
<ProjectReference Include="../drivers/csharp/RocheDB/RocheDB.csproj" />
```

Unity-specific lifecycle, editor tooling, and asset packaging are intentionally
separate from this generic OSS driver.

## C++

The C++ driver is a C++17 wrapper over the C ABI.

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
g++ -std=c++17 -Iinclude -Idrivers/cpp/include drivers/cpp/examples/contract_smoke.cpp -Llib -lrochedb -o /tmp/roche_cpp_smoke
LD_LIBRARY_PATH=lib /tmp/roche_cpp_smoke
```

Unreal-specific module packaging, Blueprint bindings, editor tooling, and
engine lifecycle integration are intentionally separate from this generic OSS
driver.

## Kotlin / JVM

The Kotlin driver is Kotlin-first and Java-compatible at the bytecode level. It
uses a small JNI bridge over the C ABI.

```sh
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim
drivers/kotlin/docker-test.sh
```

Maven Central publishing and Android packaging are future work.

## Compatibility Suite

Run non-Docker checks:

```sh
scripts/driver_compat.sh
```

Run Docker-backed PHP / Swift / Kotlin checks:

```sh
ROCHE_COMPAT_DOCKER=1 scripts/driver_compat.sh
```

Skip wire checks when only C ABI and Docker wrapper checks are needed:

```sh
ROCHE_COMPAT_DOCKER=1 ROCHE_COMPAT_WIRE=0 scripts/driver_compat.sh
```
