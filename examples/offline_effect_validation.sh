#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/koutendb-offline-effect-$$"
BIN="$ROOT/bin/effect_validation_demo"

CORPUS="${KOUTEN_REAL_JSONL:-}"
QUERY_RING="${QUERY_RING:-docs/japan}"
QUESTION="${QUESTION:-How should a Japanese customer request a refund?}"
GLOBAL_BUDGET="${GLOBAL_BUDGET:-40}"
ROUTED_BUDGET="${ROUTED_BUDGET:-10}"

cleanup() {
  if [[ "${KEEP_OFFLINE_EFFECT:-0}" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "kept workdir: $WORK"
  fi
}
trap cleanup EXIT

if [[ -z "$CORPUS" ]]; then
  echo "usage: KOUTEN_REAL_JSONL=/path/to/corpus.jsonl QUERY_RING=docs/japan examples/offline_effect_validation.sh"
  echo
  echo "Expected JSONL shape:"
  echo '  {"ring":"docs/japan","body":{"id":"doc-1","title":"...","text":"..."},"embedding":[1.0,0.0,0.0,0.0]}'
  echo
  echo "This script is for offline validation against copied or exported data."
  exit 2
fi

if [[ ! -f "$CORPUS" ]]; then
  echo "JSONL file not found: $CORPUS" >&2
  exit 2
fi

mkdir -p "$WORK" "$ROOT/bin"
cd "$ROOT"

echo "== Build effect validation runner =="
nim c -d:release --nimcache:/tmp/nimcache_kouten_offline_effect \
  -o:"$BIN" examples/effect_validation_demo.nim >/dev/null

echo
echo "== Offline KoutenDB effect validation =="
echo "jsonl: $CORPUS"
echo "ring:  $QUERY_RING"
echo "docs:  $(wc -l < "$CORPUS")"
echo

"$BIN" \
  --corpus="$CORPUS" \
  --data="$WORK/data" \
  --prompt-out="$WORK/prompt.txt" \
  --ring="$QUERY_RING" \
  --question="$QUESTION" \
  --global-budget="$GLOBAL_BUDGET" \
  --routed-budget="$ROUTED_BUDGET"
