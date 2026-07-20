#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kouten-demo-smoke.XXXXXX")"
LOCALITY_BIN="$WORK/locality_layout_demo"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p bin

echo "[demo-smoke] stellar data model demo"
examples/stellar_data_model_demo.sh >"$WORK/stellar.out"
grep -q "The original shop ring still exists" "$WORK/stellar.out"

echo "[demo-smoke] payload codec embedded demo"
examples/payload_codecs_demo.sh >"$WORK/payload-codecs.out"
grep -q "stored codec=json" "$WORK/payload-codecs.out"
grep -q "stored codec=nif" "$WORK/payload-codecs.out"
grep -q "stored codec=bif" "$WORK/payload-codecs.out"
grep -q "reopen codec=bif" "$WORK/payload-codecs.out"

echo "[demo-smoke] build locality layout demo once"
nim c -d:release --nimcache:"$WORK/nimcache" \
  -o:"$LOCALITY_BIN" examples/locality_layout_demo.nim >/dev/null

for workload in interleaved random delete-heavy backfill-heavy hot-cold; do
  echo "[demo-smoke] locality workload=${workload}"
  out="$WORK/locality-${workload}.out"
  "$LOCALITY_BIN" \
    --workload="$workload" \
    --rings=4 \
    --per-ring=40 \
    --backfill=16 \
    --read-iters=10 >"$out"
  grep -q "invariant .* sameSet=true" "$out"
done

echo "[demo-smoke] OK"
