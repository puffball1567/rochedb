#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${KOUTEN_UNIVERSE_SYNC_BASE_PORT:-17611}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
WORK="${TMPDIR:-/tmp}/koutendb-universe-sync-remote-smoke-$$"
SOURCE="$WORK/source"
RETRY_SOURCE="$WORK/retry-source"
DELAY_SOURCE="$WORK/delay-source"
TARGET="$WORK/target"
PIDS=()

stop_target() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" 2>/dev/null || true
    wait "${PIDS[@]}" 2>/dev/null || true
    PIDS=()
  fi
}

cleanup() {
  stop_target
  rm -rf "$WORK"
}
trap cleanup EXIT

start_target() {
  for id in 0 1 2; do
    src/koutend --id="$id" --peers="$PEERS" --data="$TARGET/node$id" --slow-tick=0.05 &
    PIDS+=("$!")
  done
  for _ in $(seq 1 50); do
    if src/koutencli health --peers="$PEERS" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  src/koutencli health --peers="$PEERS" >/dev/null
}

cd "$ROOT"
mkdir -p "$WORK" "$ROOT/bin"

echo "[universe-remote] build koutend"
nim c -d:release --nimcache:/tmp/nimcache_koutend -o:src/koutend src/koutend.nim >/dev/null

echo "[universe-remote] build koutencli"
nim c -d:release --nimcache:/tmp/nimcache_koutencli -o:src/koutencli src/koutencli.nim >/dev/null

echo "[universe-remote] build demo enqueuer"
nim c -d:release --nimcache:/tmp/nimcache_kouten_universe_sync_demo \
  -o:bin/universe_sync_demo examples/universe_sync_demo.nim >/dev/null

echo "[universe-remote] enqueue source event"
bin/universe_sync_demo --source="$SOURCE" --target="$TARGET" --mode=enqueue
src/koutencli universe-status --data="$SOURCE" | grep -q "pending=1"
cp -a "$SOURCE" "$RETRY_SOURCE"

echo "[universe-remote] target down keeps source pending"
src/koutencli universe-sync --data="$SOURCE" --peers="$PEERS" --prune-acked |
  grep -q "read=1 applied=0 skipped=0 acked=0 pruned=0 errors=1"
src/koutencli universe-status --data="$SOURCE" | grep -q "pending=1"

echo "[universe-remote] start target server"
start_target
sleep 1.2

echo "[universe-remote] sync source to remote target"
src/koutencli universe-sync --data="$SOURCE" --peers="$PEERS" --prune-acked |
  grep -q "read=1 applied=1 skipped=0 acked=1 pruned=1 errors=0"
src/koutencli universe-status --data="$SOURCE" | grep -q "pending=0"
src/koutencli universe-status --peers="$PEERS" | grep -q "applied=1"
src/koutencli universe-status --peers="$PEERS" --metrics | grep -q "universeApplyApplied 1"
src/koutencli universe-status --peers="$PEERS" --metrics | grep -q "universeApplyErrors 0"

echo "[universe-remote] restart target preserves applied event keys"
stop_target
start_target
src/koutencli universe-status --peers="$PEERS" | grep -q "applied=1"

echo "[universe-remote] duplicate delivery after restart is skipped"
src/koutencli universe-sync --data="$RETRY_SOURCE" --peers="$PEERS" --prune-acked |
  grep -q "read=1 applied=0 skipped=1 acked=1 pruned=1 errors=0"
src/koutencli universe-status --peers="$PEERS" --metrics | grep -q "universeApplySkipped 1"
src/koutencli universe-status --data="$RETRY_SOURCE" | grep -q "pending=0"

echo "[universe-remote] delayed remote apply stays pending"
bin/universe_sync_demo --source="$DELAY_SOURCE" --target="$TARGET" --mode=enqueue --delay-ms=60000
src/koutencli universe-sync --data="$DELAY_SOURCE" --peers="$PEERS" --prune-acked |
  grep -q "read=1 applied=0 skipped=1 acked=0 pruned=0 errors=0"
src/koutencli universe-status --data="$DELAY_SOURCE" | grep -q "pending=1"

echo "[universe-remote] OK"
