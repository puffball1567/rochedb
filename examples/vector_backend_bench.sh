#!/usr/bin/env bash
set -euo pipefail

DOCS="${DOCS:-20000}"
RINGS="${RINGS:-100}"
DIM="${DIM:-64}"
QUERIES="${QUERIES:-200}"
BUDGET="${BUDGET:-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p bin
nim c -d:release --nimcache:/tmp/nimcache_kouten_vector_backend_bench \
  -o:bin/vector_backend_bench examples/vector_backend_bench.nim

bin/vector_backend_bench \
  --docs="$DOCS" \
  --rings="$RINGS" \
  --dim="$DIM" \
  --queries="$QUERIES" \
  --budget="$BUDGET"
