#!/usr/bin/env bash
set -euo pipefail

RINGS="${RINGS:-8}"
PER_RING="${PER_RING:-200}"
BACKFILL="${BACKFILL:-64}"
WORKLOAD="${WORKLOAD:-interleaved}"
READ_ITERS="${READ_ITERS:-100}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/roche-locality-layout-demo.XXXXXX")"
BIN="$WORK/locality_layout_demo"
NIMCACHE="$WORK/nimcache"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

nim c -d:release --nimcache:"$NIMCACHE" \
  -o:"$BIN" examples/locality_layout_demo.nim

"$BIN" \
  --workload="$WORKLOAD" \
  --rings="$RINGS" \
  --per-ring="$PER_RING" \
  --backfill="$BACKFILL" \
  --read-iters="$READ_ITERS"
