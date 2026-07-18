#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${ROCHEDB_CAPI_OUT:-lib/librochedb.so}"
NIMCACHE="${ROCHEDB_CAPI_NIMCACHE:-/tmp/nimcache_roche_capi}"

mkdir -p "$(dirname "$OUT")"

NIM_FLAGS=(--app:lib -d:ssl -d:release)

if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
  for formula in libsodium openssl@3 openssl; do
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -n "$prefix" ]]; then
      NIM_FLAGS+=(--passC:"-I$prefix/include" --passL:"-L$prefix/lib")
    fi
  done
fi

nim c "${NIM_FLAGS[@]}" \
  --nimcache:"$NIMCACHE" \
  -o:"$OUT" \
  src/rochedb_capi.nim

echo "built $OUT with -d:ssl"
