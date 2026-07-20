# Development Workflow

KoutenDB uses a stable-main workflow.

## Branch Roles

| Branch | Role |
| --- | --- |
| `main` | Released, tagged, public-stable state. Documentation and package metadata on `main` should describe what users can install or evaluate now. |
| `devel` | Integration branch for the next release. Feature work targets `devel` first, not `main`. |
| `feature/...` | Focused implementation branches created from `devel`. |
| `docs/...` | Documentation-only branches created from `devel` unless they are patching released docs. |
| `test/...` | Test and CI changes created from `devel` unless they are release hotfixes. |
| `release/vX.Y.Z` | Short-lived release preparation branch cut from `devel` after the next release scope is ready. |
| `hotfix/...` | Urgent fix branch cut from `main` when the released state needs a direct patch. |

## Normal Feature Flow

1. Update local `devel`.
2. Create a focused branch from `devel`.
3. Implement and test the change.
4. Open a PR into `devel`.
5. Merge only after CI passes.

Feature branches should not target `main` directly. This keeps `main` aligned
with released tags and avoids exposing half-integrated work as the public
default state.

## Release Flow

1. Decide the next release scope on `devel`.
2. Cut `release/vX.Y.Z` from `devel`.
3. Update package metadata, release notes, and release checklist state.
4. Open a PR from `release/vX.Y.Z` into `main`.
5. Merge after CI passes.
6. Tag the merge commit on `main`.
7. Create the GitHub Release from the release notes.

Tags are created only from `main`.

## Hotfix Flow

Use a hotfix only when the currently released state needs a direct correction.

1. Create `hotfix/...` from `main`.
2. Apply the smallest safe fix.
3. PR into `main`.
4. Tag a patch release after merge.
5. Merge or cherry-pick the fix back into `devel`.

## Work In Progress

Large work should stay on a feature branch until it is coherent enough to enter
`devel`. If work must pause while a release is prepared, stash or commit it on
the feature branch. Do not apply unfinished feature work directly to `devel`.

## CI Expectations

The repository CI is the release gate for merged branches. Core checks include:

- Nim semantic checks;
- SSL-enabled checks;
- C ABI contract checks;
- core tests;
- CLI, cluster, recovery, universe, and TLS smoke tests.

Driver compatibility tests may remain optional when the relevant driver
repositories are developed separately.
