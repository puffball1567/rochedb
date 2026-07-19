#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${SWIFT_IMAGE:-orbeliasdb-swift:6.0}"

if [[ "${SWIFT_IMAGE:-}" == "" ]]; then
  docker build -t "$IMAGE" "$ROOT/drivers/swift"
fi

docker run --rm \
  -v "$ROOT":/work \
  -w /work/drivers/swift \
  -e LD_LIBRARY_PATH=/work/lib \
  "$IMAGE" \
  swift test
