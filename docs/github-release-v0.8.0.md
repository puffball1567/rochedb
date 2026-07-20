# KoutenDB v0.8.0

KoutenDB v0.8.0 is a naming and migration release.

Release:

https://github.com/puffball1567/koutendb/releases/tag/v0.8.0

The project was previously published under older names. The active project name
is now KoutenDB. The package name, CLI name, daemon name, C ABI names, repository
links, documentation, examples, and driver-facing references have been moved to
the KoutenDB naming scheme.

## Why KoutenDB

`Kouten` comes from the Japanese word "kouten" (公転), meaning orbital
revolution: one body moving around another.

That meaning fits the database model. KoutenDB uses ring and orbit-inspired
placement as part of the retrieval path. A record is not only stored somewhere;
its placement is meant to help decide what should be read together later. The
goal is to reduce unrelated reads, transferred bytes, candidate memory, and
downstream AI/RAG or application work when the application has meaningful
locality.

The name therefore describes the technical direction more directly:

- rings and orbit-inspired coordinates are part of the data model
- locality is exposed to the database instead of reconstructed after each query
- retrieval starts from meaningful placement rather than from a global scan
- the project remains focused on smaller working sets, not on scanning the
  entire corpus faster

## What Changed

- Public project name: KoutenDB
- Nim package: `koutendb`
- CLI: `kouten`
- Daemon: `koutend`
- C ABI library: `libkoutendb.so`
- C header: `include/koutendb.h`
- C ABI symbol prefix: `kouten_*`
- C ABI constants and environment variables: `KOUTEN_*` / `KOUTENDB_*`
- Main repository URL: `https://github.com/puffball1567/koutendb`

The technical direction is unchanged. KoutenDB remains a ring-oriented
NoSQL/document/vector store for locality-aware retrieval and smaller working
sets.

## Migration Notes

New installations should use:

```sh
nimble install koutendb
kouten --help
```

From source:

```sh
git clone https://github.com/puffball1567/koutendb.git
cd koutendb
nimble check
scripts/test_all_smoke.sh
```

C ABI users should build through the canonical script:

```sh
scripts/build_capi.sh
```

and link against:

```text
include/koutendb.h
lib/libkoutendb.so
```

External drivers should move to the KoutenDB package and repository names. Older
names may still appear in historical posts or archived package entries, but the
active project name is KoutenDB.

## Verification

The rename branch was verified with:

- `nim check src/koutendb.nim`
- `nim check src/koutencli.nim`
- `nim check src/koutend.nim`
- `nim check src/koutendb_capi.nim`
- `nimble check`
- `scripts/build_capi.sh`
- `scripts/test_core.sh`
- `scripts/cli_crud_smoke.sh`
- `scripts/cabi_tls_smoke.sh`
- `scripts/driver_compat.sh`
- `scripts/test_all_smoke.sh`

GitHub Actions for the rename PR also passed, including the Linux and macOS C
ABI checks.

## Known Boundaries

- KoutenDB remains a technical preview / research OSS.
- This release is primarily a naming and migration release, not a new storage
  engine feature release.
- External driver packages may need their own coordinated KoutenDB-name
  releases.
- Historical articles, forum posts, and package names may still mention older
  names during the transition.
