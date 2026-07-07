# FAISS Versioning Policy

RocheDB does not vendor the FAISS source tree. The repository keeps only:

- `scripts/fetch_faiss.sh`
- `scripts/build_faiss_bridge.sh`
- `third_party/faiss.version`
- the RocheDB bridge source in `src/roche/faiss_bridge.cpp`

The FAISS checkout itself lives at `third_party/faiss/` and is ignored by Git.
The built bridge `lib/libroche_faiss.so` is also ignored.

For when to use FAISS instead of the built-in exact backend, see
[vector-backends.md](./vector-backends.md).

## Default Behavior

By default, RocheDB fetches the configured FAISS tag without enforcing a commit
pin:

```sh
scripts/fetch_faiss.sh
```

The default tag for v0.1.0 is:

```text
v1.14.3
```

After fetch, the actual commit is recorded in:

```text
third_party/faiss.version
```

This default is intentionally flexible. If FAISS needs a security or packaging
update, users can move to another tag without waiting for RocheDB to publish a
new default.

## Installing a Specific Tag

Use `ROCHE_FAISS_VERSION`:

```sh
ROCHE_FAISS_VERSION=v1.14.2 scripts/fetch_faiss.sh
scripts/build_faiss_bridge.sh
roche doctor
```

## Installing an Exact Commit

Use both `ROCHE_FAISS_VERSION` and `ROCHE_FAISS_COMMIT`.

```sh
ROCHE_FAISS_VERSION=v1.14.3 \
ROCHE_FAISS_COMMIT=0ca9df4792b173d573044ee14ca0704780176e82 \
scripts/fetch_faiss.sh
```

When `ROCHE_FAISS_COMMIT` is set, `scripts/fetch_faiss.sh` fails if the fetched
checkout does not match that exact commit.

This is the right mode for:

- reproducible production builds;
- release verification;
- CI pipelines that need strict dependency identity;
- rollback to a previously verified FAISS commit.

## Upgrading or Downgrading FAISS

1. Pick the target FAISS tag.
2. Fetch it:

   ```sh
   ROCHE_FAISS_VERSION=vX.Y.Z scripts/fetch_faiss.sh
   ```

3. Build and verify:

   ```sh
   scripts/build_faiss_bridge.sh
   roche doctor
   scripts/test_core.sh
   ```

4. If the build is accepted, record the resulting `third_party/faiss.version`
   commit in your deployment notes or CI configuration.
5. For reproducible builds, rerun with `ROCHE_FAISS_COMMIT=<that commit>`.

Downgrades use the same process with an older tag.

## RocheDB Maintainer Pin Updates

When RocheDB maintainers update the recommended default:

1. Choose the new default FAISS tag.
2. Test it with `scripts/fetch_faiss.sh`, `scripts/build_faiss_bridge.sh`,
   `roche doctor`, and the release smoke suite.
3. Update the default `VERSION` in `scripts/fetch_faiss.sh`.
4. Commit the updated `third_party/faiss.version`.
5. Update this document and third-party notices if license or build
   requirements changed.

## Security Updates

If FAISS publishes a security fix, users can immediately choose a patched tag:

```sh
ROCHE_FAISS_VERSION=vX.Y.Z scripts/fetch_faiss.sh
scripts/build_faiss_bridge.sh
roche doctor
```

RocheDB maintainers should then test the patched version and update the
recommended default when appropriate. This keeps the default simple while still
allowing strict pinning for deployments that need it.
