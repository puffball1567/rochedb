# OrbeliasDB v0.4.0

OrbeliasDB v0.4.0 adds TLS transport support and repository-level CI coverage.

Release:

https://github.com/puffball1567/orbeliasdb/releases/tag/v0.4.0

## Main Changes

- Added optional TLS transport for `orbeliasd`, OrbeliasDB Nim clients, CLI commands,
  and the C ABI.
- Added `orbelias_connect_auth_tls` as an additive C ABI entry point.
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

TLS support requires building OrbeliasDB with Nim's SSL support:

```sh
nim c -d:ssl -d:release -o:bin/orbeliasd src/orbeliasd.nim
nim c -d:ssl -d:release -o:bin/orbelias src/orbeliascli.nim
```

Without `-d:ssl`, non-TLS operation remains available.

## Verification

Before release, the following checks passed locally or in GitHub Actions:

- `nim check src/orbeliasdb.nim`
- `nim check src/orbeliascli.nim`
- `nim check src/orbeliasd.nim`
- `nim check src/orbeliasdb_capi.nim`
- `nim check -d:ssl src/orbeliascli.nim`
- `nim check -d:ssl src/orbeliasd.nim`
- `nim check -d:ssl src/orbeliasdb_capi.nim`
- C ABI contract test
- `scripts/cluster_tls_smoke.sh`
- `scripts/test_all_smoke.sh`
- GitHub Actions CI jobs added in this release
