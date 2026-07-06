# Third-Party Source Checkouts

This directory is reserved for pinned third-party source checkouts that RocheDB
can build against.

Current pinned source:

| Component | Version | Source |
|---|---:|---|
| FAISS | v1.14.3 / `0ca9df4792b173d573044ee14ca0704780176e82` | `https://github.com/facebookresearch/faiss` |

Use `scripts/fetch_faiss.sh` to create or update `third_party/faiss`.
Use `scripts/setup_faiss_toolchain.sh` if the system CMake is too old for the
pinned FAISS version. Generated build directories under third-party checkouts
should not be committed.
