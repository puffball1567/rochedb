#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${ROCHEDB_CAPI_OUT:-lib/librochedb.so}"
NIMCACHE="${ROCHEDB_CAPI_NIMCACHE:-/tmp/nimcache_roche_capi}"

mkdir -p "$(dirname "$OUT")"

nim c --app:lib -d:ssl -d:release \
  --nimcache:"$NIMCACHE" \
  -o:"$OUT" \
  src/rochedb_capi.nim

echo "built $OUT with -d:ssl"
