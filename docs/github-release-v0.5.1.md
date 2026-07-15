# RocheDB v0.5.1

RocheDB v0.5.1 is a documentation-focused patch release for the v0.5.x
technical preview.

Release:

https://github.com/puffball1567/rochedb/releases/tag/v0.5.1

## Main Changes

- Added `docs/technical-faq.md`.
- Linked the Technical FAQ from `README.md`.
- Linked the Technical FAQ from the documentation index.

## Why This Patch Exists

RocheDB has enough unusual terminology that first-time reviewers need a direct
technical entry point. The new FAQ answers the questions most likely to come
from database engineers:

- Is a ring just partitioning?
- Is stellar locality a join?
- Is this a secondary index?
- Is the orbital model just consistent hashing?
- Where do the benchmark improvements come from?
- How are records grouped on disk?
- What happens when write patterns are messy?
- Is RocheDB production-ready?

The answers are intentionally conservative. They explain RocheDB's current
strengths, but also document boundaries around production readiness, dynamic
membership, broad secondary-index planning, and real-workload validation.

## Verification

This release contains documentation and package metadata changes only.

Verified with:

- `git diff --check`
- GitHub Actions on the documentation PR into `devel`

## Known Boundaries

The v0.5.0 implementation boundaries remain unchanged:

- dynamic cluster membership with minimal remapping is still planned;
- longer mixed-version protocol compatibility is still planned;
- deeper failure-injection tests are still planned;
- broader driver parity is still in progress.
