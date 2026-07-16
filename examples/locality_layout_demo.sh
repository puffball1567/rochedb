#!/usr/bin/env bash
set -euo pipefail

RINGS="${RINGS:-8}"
PER_RING="${PER_RING:-200}"
BACKFILL="${BACKFILL:-64}"
WORKLOAD="${WORKLOAD:-interleaved}"
READ_ITERS="${READ_ITERS:-100}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p bin
nim c -d:release --nimcache:/tmp/nimcache_roche_locality_layout_demo \
  -o:bin/locality_layout_demo examples/locality_layout_demo.nim

bin/locality_layout_demo \
  --workload="$WORKLOAD" \
  --rings="$RINGS" \
  --per-ring="$PER_RING" \
  --backfill="$BACKFILL" \
  --read-iters="$READ_ITERS"
