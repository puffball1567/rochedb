#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${PHP_IMAGE:-orbeliasdb-php-ffi:8.3}"

if [[ "${PHP_IMAGE:-}" == "" ]]; then
  docker build -t "$IMAGE" "$ROOT/drivers/php"
fi

docker run --rm \
  -v "$ROOT":/work \
  -w /work \
  -e LD_LIBRARY_PATH=/work/lib \
  "$IMAGE" \
  php -d ffi.enable=1 drivers/php/tests/driver_test.php
