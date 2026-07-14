#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${TMPDIR:-/tmp}/rochedb-stellar-demo-$$"

cleanup() {
  rm -rf "$DATA"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p bin "$DATA"

nim c -d:release --nimcache:/tmp/nimcache_roche_stellar_demo \
  -o:bin/roche src/rochecli.nim >/dev/null

ROCHE=(bin/roche --data="$DATA")

echo "== Insert separate coordinates =="
"${ROCHE[@]}" put --ring=users/123 \
  --payload='{"kind":"user","name":"Alice","country":"JP"}' --codec=json
"${ROCHE[@]}" put --ring=shops/1123 \
  --payload='{"kind":"shop","name":"Orbit Store","market":"JP"}' --codec=json
"${ROCHE[@]}" put --ring=orders/A-001 \
  --payload='{"kind":"order","orderNo":"A-001","total":42}' --codec=json

echo
echo "== Attach existing coordinates to a stellar lens =="
"${ROCHE[@]}" stellar attach --stellar=commerce/order/A-001 --ring=users/123
"${ROCHE[@]}" stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
"${ROCHE[@]}" stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001

echo
echo "== Read the order-centered stellar lens =="
"${ROCHE[@]}" get --stellar=commerce/order/A-001 \
  --selection='{ kind name orderNo total }'

echo
echo "== Narrow the field of view to shops =="
"${ROCHE[@]}" get --stellar=commerce/order/A-001 --subring=shops \
  --selection='{ kind name }'

echo
echo "== Detach the shop coordinate without deleting its payload =="
"${ROCHE[@]}" stellar detach --stellar=commerce/order/A-001 --ring=shops/1123

echo
echo "== The stellar lens no longer sees the shop =="
"${ROCHE[@]}" get --stellar=commerce/order/A-001 --filter='{"kind":"shop"}'

echo
echo "== The original shop ring still exists =="
"${ROCHE[@]}" get --ring=shops/1123 --selection='{ kind name }'
