#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/rochedb-universe-sync-demo-$$"
API_SOURCE="$WORK/api-tokyo"
API_TARGET="$WORK/api-oregon"
CLI_SOURCE="$WORK/cli-tokyo"
CLI_TARGET="$WORK/cli-oregon"

cleanup() {
  if [[ "${KEEP_UNIVERSE_SYNC_DEMO:-0}" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "kept workdir: $WORK"
  fi
}
trap cleanup EXIT

mkdir -p "$WORK" "$ROOT/bin"
cd "$ROOT"

echo "== Build universe sync demo =="
nim c -d:release --nimcache:/tmp/nimcache_roche_universe_sync_demo \
  -o:bin/universe_sync_demo examples/universe_sync_demo.nim >/dev/null
nim c -d:release --nimcache:/tmp/nimcache_roche_universe_sync_cli \
  -o:bin/rochecli src/rochecli.nim >/dev/null

echo
echo "== Run durable eventual universe sync demo =="
bin/universe_sync_demo --source="$API_SOURCE" --target="$API_TARGET"

echo
echo "== CLI one-shot sync boundary =="
bin/universe_sync_demo --source="$CLI_SOURCE" --target="$CLI_TARGET" --mode=enqueue
bin/rochecli universe-export --data="$CLI_SOURCE" --out="$WORK/pending.jsonl"
echo "exported lines: $(wc -l < "$WORK/pending.jsonl")"
bin/rochecli universe-sync --data="$CLI_SOURCE" --target-data="$CLI_TARGET" --prune-acked
bin/rochecli universe-export --data="$CLI_SOURCE" --out="$WORK/after.jsonl"
echo "remaining exported lines: $(wc -l < "$WORK/after.jsonl")"
