# KoutenDB v0.4.0

KoutenDB v0.4.0 adds TLS transport support and repository-level CI coverage.

Release:

https://github.com/puffball1567/koutendb/releases/tag/v0.4.0

## Main Changes

- Added optional TLS transport for `koutend`, KoutenDB Nim clients, CLI commands,
  and the C ABI.
- Added `kouten_connect_auth_tls` as an additive C ABI entry point.
- Added TLS CLI flags:
  - `--tls`
  - `--tls-ca=FILE`
  - `--tls-server-name=NAME`
  - `--tls-insecure-skip-verify`
- Added TLS server flags:
  - `--tls-cert=FILE`
  - `--tls-key=FILE`
  - `--tls-ca=FILE`
  - `--tls-server-name=NAME`
  - `--tls-insecure-skip-verify`
- Added `docs/tls-transport.md`.
- Added a TLS smoke test that verifies:
  - TLS health check;
  - authenticated JSON put/get over TLS;
  - plain clients are rejected by a TLS listener.
- Added GitHub Actions CI for:
  - Nim semantic checks;
  - SSL-enabled semantic checks;
  - C ABI contract coverage;
  - core tests;
  - CLI, cluster, recovery, and universe smoke tests;
  - TLS transport smoke tests.

## Build Note

TLS support requires building KoutenDB with Nim's SSL support:

```sh
nim c -d:ssl -d:release -o:bin/koutend src/koutend.nim
nim c -d:ssl -d:release -o:bin/kouten src/koutencli.nim
```

Without `-d:ssl`, non-TLS operation remains available.

## Verification

Before release, the following checks passed locally or in GitHub Actions:

- `nim check src/koutendb.nim`
- `nim check src/koutencli.nim`
- `nim check src/koutend.nim`
- `nim check src/koutendb_capi.nim`
- `nim check -d:ssl src/koutencli.nim`
- `nim check -d:ssl src/koutend.nim`
- `nim check -d:ssl src/koutendb_capi.nim`
- C ABI contract test
- `scripts/cluster_tls_smoke.sh`
- `scripts/test_all_smoke.sh`
- GitHub Actions CI jobs added in this release
