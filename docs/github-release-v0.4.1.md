# OrbeliasDB v0.4.1

OrbeliasDB v0.4.1 is a documentation and process patch release.

Release:

https://github.com/puffball1567/orbeliasdb/releases/tag/v0.4.1

## Main Changes

- Added `docs/development-workflow.md`.
- Documented the stable-main / `devel` integration workflow.
- Clarified branch roles for:
  - `main`
  - `devel`
  - `feature/...`
  - `docs/...`
  - `test/...`
  - `release/vX.Y.Z`
  - `hotfix/...`
- Linked the workflow from `CONTRIBUTING.md`.
- Linked the workflow from the documentation index.

## Branch Policy Summary

- `main` is the released, tagged, public-stable branch.
- `devel` is the integration branch for the next release.
- Normal feature, test, and documentation work targets `devel`.
- Release branches are cut from `devel` and merged into `main`.
- Tags are created only from `main`.

## Verification

The documentation workflow PR passed the repository CI before merge into
`devel`:

- Nim checks and C ABI
- Core test suite
- CLI, cluster, recovery, and universe smoke
- TLS transport smoke
