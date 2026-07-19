# OrbeliasDB Driver Installation Guide

This document shows the current technical-preview setup for each language. The
English README and this file are the canonical driver installation references.

OrbeliasDB drivers currently use two paths:

- Native TCP wire drivers for cluster-oriented use.
- C ABI wrappers for embedded/local use and language binding stability.

The CLI provides a small driver discovery surface:

```sh
orbelias driver list
orbelias driver info rust
orbelias driver install rust
orbelias driver install rust --manifest-path=/path/to/Cargo.toml
```

`driver install` prints the official package/repository path and setup command.
For Rust, target selection is shell-friendly: use `--manifest-path=FILE`,
`--project-dir=DIR`, `ORBELIAS_DRIVER_MANIFEST`, or `ORBELIAS_DRIVER_PROJECT`.
It does not execute package-manager commands unless `--execute` is passed.

The Nim package is available through Nimble. Rust, JavaScript / TypeScript, PHP,
and Python drivers are also published as language-native packages. Other
non-Nim drivers are still repository-local foundations, so those examples
assume a local clone of this repository.

## Optional FAISS Setup

The exact vector backend works without FAISS. For the FAISS bridge path, fetch
and build FAISS after cloning:

```sh
scripts/fetch_faiss.sh
scripts/setup_faiss_toolchain.sh   # only needed when system CMake is too old
scripts/build_faiss_bridge.sh
orbelias doctor
```

By default, `scripts/fetch_faiss.sh` fetches the configured FAISS tag and records
the actual commit in `third_party/faiss.version`. To pin an exact commit for a
reproducible build, set `ORBELIAS_FAISS_COMMIT`. See
[faiss-versioning.md](./faiss-versioning.md).

## Build the Native Library

Most C ABI wrappers need `lib/liborbeliasdb.so`:

```sh
scripts/build_capi.sh
```

This is the canonical C ABI build. It compiles `lib/liborbeliasdb.so` with
`-d:ssl`, so `orbelias_connect_auth_tls` is available to Rust, Node native addons,
PHP FFI, C++, C#, Swift, Kotlin, Go, and other wrappers without each driver
duplicating Nim flags.

For native wire driver tests, build `orbeliasd`:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:src/orbeliasd src/orbeliasd.nim
```

## Nim

Install from Nimble:

```sh
nimble install orbeliasdb
orbelias --help
```

Then import the public API:

```nim
import orbeliasdb

var db = orbeliasdb.open(dataDir = "data")
let id = db.put("hello", ring = "docs")
echo db.get(id)
```

From a source checkout, run:

```sh
scripts/test_core.sh
```

## C ABI

Include `include/orbeliasdb.h` and link `lib/liborbeliasdb.so`:

```sh
scripts/build_capi.sh
gcc examples/cabi_contract.c -Iinclude -Llib -lorbeliasdb -Wl,-rpath,'$ORIGIN/../lib' -o bin/cabi_contract
LD_LIBRARY_PATH=lib bin/cabi_contract
```

Thread-safety contract:

- `orbelias_init()` is idempotent.
- `orbelias_last_error()` returns text owned by OrbeliasDB. Copy it before the next
  OrbeliasDB C ABI call on the same thread.
- Do not call `orbelias_close()` concurrently with any other operation on the same
  handle.
- If a driver shares one handle across threads, serialize calls around that
  handle. Separate handles may be used independently.

## Python

The Python driver is released as a separate native TCP wire driver:

- repository: [`puffball1567/orbeliasdb-python` v0.1.3](https://github.com/puffball1567/orbeliasdb-python)
- mode: pure Python TCP driver for `orbeliasd`
- PyPI: [`orbeliasdb` v0.1.3](https://pypi.org/project/orbeliasdb/)

```sh
python3 -m pip install orbeliasdb
ORBELIASDB_CORE_DIR=/path/to/orbeliasdb python3 -m unittest discover -s tests
```

Example:

```python
from orbeliasdb import OrbeliasClient

db = OrbeliasClient.connect("127.0.0.1:17301")
doc_id = db.put("docs", b'{"title":"hello"}')
print(db.get(doc_id))
db.close()
```

## JavaScript / TypeScript

The published JavaScript / TypeScript driver is a Node-API wrapper over the
OrbeliasDB C ABI:

- npm: [`orbeliasdb` v0.1.3](https://www.npmjs.com/package/orbeliasdb)
- repository: [`puffball1567/orbeliasdb-js`](https://github.com/puffball1567/orbeliasdb-js)

Install it in an application:

```sh
npm install orbeliasdb
```

Build the OrbeliasDB core shared library first and set `ORBELIASDB_CORE_DIR` during
install/rebuild. See the driver repository README for the full setup flow.

The core repository also keeps a repository-local native TCP wire driver used
for protocol smoke tests:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:src/orbeliasd src/orbeliasd.nim
node --test drivers/node/test/*.test.js
bun test drivers/node/test-bun/*.test.ts
```

Repository-local wire-driver example:

```js
import { OrbeliasClient } from "./drivers/node/src/index.js";

const db = OrbeliasClient.connect("127.0.0.1:17301");
const id = await db.put("docs", Buffer.from('{"title":"hello"}'));
console.log((await db.get(id)).toString("utf8"));
await db.close();
```

## Rust

The Rust driver is published as a C ABI wrapper:

- crates.io: [`orbeliasdb` v0.1.3](https://crates.io/crates/orbeliasdb)
- repository: [`puffball1567/orbeliasdb-rust`](https://github.com/puffball1567/orbeliasdb-rust)

Install it in a Rust project:

```sh
cargo add orbeliasdb
```

Or ask the OrbeliasDB CLI to print the official setup command:

```sh
orbelias driver install rust --manifest-path=/path/to/Cargo.toml
```

Build the OrbeliasDB core shared library first and set `ORBELIASDB_CORE_DIR` or
`ORBELIASDB_LIB_DIR` when building/testing the Rust project. See the Rust driver
repository README for the full setup flow.

## Go

The Go driver is a C ABI wrapper.

```sh
scripts/build_capi.sh
cd drivers/go
GOCACHE="${GOCACHE:-/tmp/orbelias-go-cache}" go test ./...
```

Use a local module replace until publication:

```text
replace github.com/orbeliasdb/orbeliasdb-go => ../drivers/go
```

## PHP

The PHP driver uses FFI over the C ABI. Local PHP must have `ext-ffi` enabled.
It is published on Packagist:

- Packagist: [`orbeliasdb/orbeliasdb` v0.1.2](https://packagist.org/packages/orbeliasdb/orbeliasdb)
- repository: [`puffball1567/orbeliasdb-php`](https://github.com/puffball1567/orbeliasdb-php)
- package name: `orbeliasdb/orbeliasdb`

Install it in a Composer project:

```sh
composer require orbeliasdb/orbeliasdb:^0.1
```

Build the OrbeliasDB core shared library first and point the PHP driver at it:

```sh
scripts/build_capi.sh
export ORBELIASDB_CORE_DIR=/path/to/orbeliasdb
```

For local driver development from a checkout of `orbeliasdb-php`, use the Docker
smoke test:

```sh
ORBELIASDB_CORE_DIR=/path/to/orbeliasdb ./docker-test.sh
```

For Composer path development against a local `orbeliasdb-php` checkout:

```json
{
  "repositories": [
    { "type": "path", "url": "../orbeliasdb-php" }
  ],
  "require": {
    "orbeliasdb/orbeliasdb": "*"
  }
}
```

## Swift

The Swift driver is a SwiftPM wrapper over the C ABI. Linux smoke is Docker
backed.

```sh
scripts/build_capi.sh
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
scripts/build_capi.sh
dotnet run --project drivers/csharp/ContractSmoke/ContractSmoke.csproj
```

Use a project reference until NuGet publication:

```xml
<ProjectReference Include="../drivers/csharp/OrbeliasDB/OrbeliasDB.csproj" />
```

Unity-specific lifecycle, editor tooling, and asset packaging are intentionally
separate from this generic OSS driver.

## C++

The C++ driver is released as a separate C++17 wrapper over the C ABI:

- repository: [`puffball1567/orbeliasdb-cpp` v0.1.1](https://github.com/puffball1567/orbeliasdb-cpp)
- mode: C++17 RAII wrapper over `liborbeliasdb.so`

```sh
git clone https://github.com/puffball1567/orbeliasdb-cpp.git
cd orbeliasdb-cpp
cmake -S . -B build -DORBELIASDB_CORE_DIR=/path/to/orbeliasdb
cmake --build build
./build/orbeliasdb_cpp_contract_smoke
```

Unreal-specific module packaging, Blueprint bindings, editor tooling, and
engine lifecycle integration are intentionally separate from this generic OSS
driver.

## Kotlin / JVM

The Kotlin driver is Kotlin-first and Java-compatible at the bytecode level. It
uses a small JNI bridge over the C ABI.

```sh
scripts/build_capi.sh
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
ORBELIAS_COMPAT_DOCKER=1 scripts/driver_compat.sh
```

Skip wire checks when only C ABI and Docker wrapper checks are needed:

```sh
ORBELIAS_COMPAT_DOCKER=1 ORBELIAS_COMPAT_WIRE=0 scripts/driver_compat.sh
```
