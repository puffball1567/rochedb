# Third-Party Notices

This file tracks known third-party dependencies and tooling used by OrbeliasDB.
It is intended as an engineering compliance checklist, not as legal advice.

## Reviewed Dependency Manifests

This notice was prepared from the dependency declarations currently present in:

- `orbeliasdb.nimble`
- `drivers/node/package.json`
- `drivers/python/pyproject.toml`
- `drivers/rust/Cargo.toml`
- `drivers/go/go.mod`
- `drivers/php/composer.json`
- `drivers/swift/Package.swift`
- `drivers/csharp/OrbeliasDB/OrbeliasDB.csproj`
- `drivers/csharp/ContractSmoke/ContractSmoke.csproj`
- `drivers/php/Dockerfile`
- `drivers/swift/Dockerfile`
- `drivers/kotlin/Dockerfile`
- `third_party/README.md`

## Runtime Dependencies

| Component | Scope | License | Source / declaration | Notes |
|---|---|---|---|---|
| Nim standard library | OrbeliasDB core | MIT | Nim toolchain | Used by the Nim implementation. Not vendored. |
| nimsodium | OrbeliasDB core auth/encryption path | MIT | `orbeliasdb.nimble`: `nimsodium >= 0.2.0`; package metadata URL: `https://github.com/puffball1567/nimsodium` | Local Nimble package metadata reports MIT. Not vendored. |
| libsodium | Native crypto library used by nimsodium / Docker smoke images | ISC | System package, commonly `libsodium23` | Linked or installed as a system package depending on deployment. Not vendored in this repository. |

## Driver Runtime Dependencies

| Component | Scope | License | Source / declaration | Notes |
|---|---|---|---|---|
| C standard library / platform dynamic loader | C ABI consumers | Platform-specific | System runtime | Required by native dynamic loading. |
| Python standard library | Python driver | PSF License | `drivers/python/pyproject.toml` has no runtime package dependency | The driver uses only Python standard library modules at runtime. |
| Node.js standard library | Node.js / TypeScript driver | MIT | `drivers/node/package.json` has no dependency section | The driver uses only Node built-in modules at runtime. |
| Bun runtime | Bun smoke path | MIT | `drivers/node/package.json` engine compatibility | Used for Bun compatibility testing; not required by Node users. |
| Rust standard library | Rust driver | Apache-2.0 / MIT | `drivers/rust/Cargo.toml` has an empty `[dependencies]` section | The Rust wrapper has no third-party crate dependencies. |
| Go standard library | Go driver | BSD-style | `drivers/go/go.mod` declares only the module and Go version | The Go wrapper has no third-party module dependencies. |
| PHP runtime and FFI extension | PHP driver | PHP License / extension-specific | `drivers/php/composer.json`: `php >= 8.2`, `ext-ffi` | The PHP driver requires FFI. No Composer package dependency is declared. |
| Swift standard library / SwiftPM | Swift driver | Apache-2.0 | `drivers/swift/Package.swift` | The Swift package wraps the C ABI and has no external package dependency. |
| .NET runtime | C# driver | MIT | `drivers/csharp/OrbeliasDB/OrbeliasDB.csproj` | The C# wrapper has no NuGet package dependencies. |
| JVM / Kotlin standard library | Kotlin driver | Apache-2.0 for Kotlin components; JVM distribution varies | `drivers/kotlin/Dockerfile` downloads the Kotlin compiler for smoke tests | The Kotlin smoke path uses JNI and the OrbeliasDB C ABI. |

## Build And Test Tooling

These tools are used to build or test OrbeliasDB and its drivers. They are not
vendored or redistributed by the OrbeliasDB source tree.

| Component | Scope | License | Source / declaration | Notes |
|---|---|---|---|---|
| Nim compiler / Nimble | Core build and tests | MIT | `orbeliasdb.nimble`, local Nim toolchain | Required to build OrbeliasDB from source. |
| setuptools | Python packaging | MIT | `drivers/python/pyproject.toml`: `setuptools>=68` | Python build-system dependency only. |
| TypeScript type declarations | Node driver authoring | Apache-2.0 as part of this repo | `drivers/node/src/index.d.ts` | No TypeScript compiler dependency is declared. |
| GCC / G++ | C ABI, C++, JNI smoke builds | GPL toolchain; runtime libraries vary | System package / Docker image package | Used as system build tooling. |
| Cargo | Rust build and tests | Apache-2.0 / MIT | Rust toolchain | No third-party crates are declared. |
| Go toolchain | Go build and tests | BSD-style | Go toolchain | No third-party modules are declared. |
| Composer metadata | PHP packaging | MIT for Composer itself | `drivers/php/composer.json` | The driver has no Composer package dependencies beyond PHP/ext-ffi. |
| Swift Docker image | Swift Linux smoke tests | Image contains multiple components | `drivers/swift/Dockerfile`: `FROM swift:6.0` | Used only for Docker-backed smoke tests. |
| PHP Docker image | PHP FFI smoke tests | Image contains multiple components | `drivers/php/Dockerfile`: `FROM php:8.3-cli` | Used only for Docker-backed smoke tests. |
| Eclipse Temurin Docker image | Kotlin/JNI smoke tests | GPLv2 with Classpath Exception for OpenJDK; image contains multiple components | `drivers/kotlin/Dockerfile`: `FROM eclipse-temurin:21-jdk-jammy` | Used only for Docker-backed smoke tests. |
| Kotlin compiler | Kotlin/JNI smoke tests | Apache-2.0 | `drivers/kotlin/Dockerfile`: `KOTLIN_VERSION=2.0.21` | Downloaded in the Kotlin Docker test image. |
| Debian / Ubuntu packages in Docker smoke images | Docker-backed smoke tests | Package-specific | `apt-get install` lines in driver Dockerfiles | Includes packages such as `ca-certificates`, `curl`, `unzip`, `g++`, `libffi-dev`, and `libsodium23`. These are not vendored in this repository. |

## Optional / Planned Dependencies

These components are referenced by design or roadmap documents. FAISS is the
intended production vector backend path, but OrbeliasDB loads it through a dynamic
bridge instead of statically linking it into the default core build.

| Component | Planned scope | License | Source / declaration | Notes |
|---|---|---|---|---|
| FAISS | Production vector backend bridge | MIT | Source checkout target: `third_party/faiss` via `scripts/fetch_faiss.sh`; bridge source: `src/orbelias/faiss_bridge.cpp`; OrbeliasDB core loads `liborbelias_faiss.so` dynamically when `vbFaiss` is selected | Default tag: `v1.14.3`; last verified commit recorded in `third_party/faiss.version`. Users can pin an exact commit with `ORBELIAS_FAISS_COMMIT`. License text is available in the fetched checkout at `third_party/faiss/LICENSE`. FAISS is not vendored, not statically linked by the default core build, and not committed to this repository. See `docs/faiss-versioning.md`. |

## Current Repository Policy

- OrbeliasDB core and the OSS drivers are released under Apache-2.0. See
  `LICENSE`.
- Third-party source code is not vendored unless explicitly documented here.
- If a future release vendors source code or redistributes binary artifacts, add
  the exact package version, source URL, license text location, and any required
  notices before publishing.
- Docker images used for smoke tests are development artifacts; they should not
  be treated as OrbeliasDB runtime redistribution packages.
- Before publishing binary artifacts, rerun a dependency/license scan for the
  target artifact itself. Source-tree notices are not a substitute for binary
  redistribution review.
