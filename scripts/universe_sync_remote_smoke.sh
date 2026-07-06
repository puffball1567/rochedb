#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ROCHE_UNIVERSE_SYNC_BASE_PORT:-17611}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
WORK="${TMPDIR:-/tmp}/rochedb-universe-sync-remote-smoke-$$"
SOURCE="$WORK/source"
TARGET="$WORK/target"
PIDS=()

cleanup() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" 2>/dev/null || true
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$WORK" "$ROOT/bin"

echo "[universe-remote] build roched"
nim c -d:release --nimcache:/tmp/nimcache_roched -o:src/roched src/roched.nim >/dev/null

echo "[universe-remote] build rochecli"
nim c -d:release --nimcache:/tmp/nimcache_rochecli -o:src/rochecli src/rochecli.nim >/dev/null

echo "[universe-remote] build demo enqueuer"
nim c -d:release --nimcache:/tmp/nimcache_roche_universe_sync_demo \
  -o:bin/universe_sync_demo examples/universe_sync_demo.nim >/dev/null

echo "[universe-remote] enqueue source event"
bin/universe_sync_demo --source="$SOURCE" --target="$TARGET" --mode=enqueue
src/rochecli universe-status --data="$SOURCE" | grep -q "pending=1"

echo "[universe-remote] target down keeps source pending"
src/rochecli universe-sync --data="$SOURCE" --peers="$PEERS" --prune-acked |
  grep -q "read=1 applied=0 skipped=0 acked=0 pruned=0 errors=1"
src/rochecli universe-status --data="$SOURCE" | grep -q "pending=1"

echo "[universe-remote] start target server"
for id in 0 1 2; do
  src/roched --id="$id" --peers="$PEERS" --data="$TARGET/node$id" --slow-tick=0.05 &
  PIDS+=("$!")
done
for _ in $(seq 1 50); do
  if src/rochecli health --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
src/rochecli health --peers="$PEERS" >/dev/null

echo "[universe-remote] sync source to remote target"
src/rochecli universe-sync --data="$SOURCE" --peers="$PEERS" --prune-acked |
  grep -q "read=1 applied=1 skipped=0 acked=1 pruned=1 errors=0"
src/rochecli universe-status --data="$SOURCE" | grep -q "pending=0"
src/rochecli universe-status --peers="$PEERS" | grep -q "applied=1"
src/rochecli universe-status --peers="$PEERS" --metrics | grep -q "universeApplyApplied 1"
src/rochecli universe-status --peers="$PEERS" --metrics | grep -q "universeApplyErrors 0"

echo "[universe-remote] OK"
