#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/rochedb-universe-sync-failure-smoke-$$"
SOURCE="$WORK/source"
TARGET="$WORK/target"
EVENTS="$WORK/events.jsonl"
MIXED="$WORK/mixed.jsonl"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$WORK" "$ROOT/bin"

echo "[universe-failure] build roche"
nim c -d:release --nimcache:/tmp/nimcache_roche_universe_failure \
  -o:bin/roche src/rochecli.nim >/dev/null

echo "[universe-failure] build demo enqueuer"
nim c -d:release --nimcache:/tmp/nimcache_roche_universe_failure_demo \
  -o:bin/universe_sync_demo examples/universe_sync_demo.nim >/dev/null

echo "[universe-failure] enqueue and export"
bin/universe_sync_demo --source="$SOURCE" --target="$TARGET" --mode=enqueue
bin/roche universe-status --data="$SOURCE" | grep -q "pending=1"
bin/roche universe-export --data="$SOURCE" --out="$EVENTS" >/dev/null
test "$(wc -l < "$EVENTS")" -eq 1

echo "[universe-failure] malformed JSONL is counted and valid events still apply"
{
  echo '{"bad":'
  cat "$EVENTS"
} > "$MIXED"
bin/roche universe-apply --data="$TARGET" --in="$MIXED" |
  grep -q "read=2 applied=1 skipped=0 errors=1"
bin/roche count-ring --data="$TARGET" --ring=posts/u1 |
  grep -q "count=1"

echo "[universe-failure] replay is idempotent"
bin/roche universe-apply --data="$TARGET" --in="$EVENTS" |
  grep -q "read=1 applied=0 skipped=1 errors=0"
bin/roche count-ring --data="$TARGET" --ring=posts/u1 |
  grep -q "count=1"

echo "[universe-failure] source ack/prune remains explicit"
bin/roche universe-status --data="$SOURCE" | grep -q "pending=1"
bin/roche universe-sync --data="$SOURCE" --target-data="$TARGET" --prune-acked |
  grep -q "read=1 applied=0 skipped=1 acked=1 pruned=1 errors=0"
bin/roche universe-status --data="$SOURCE" | grep -q "pending=0"

echo "[universe-failure] OK"
