#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_PORT="${KOUTEN_LR_DEMO_BASE_PORT:-18411}"
TRAIN_LOCAL="127.0.0.1:${BASE_PORT}"
TRAIN_REMOTE="127.0.0.1:$((BASE_PORT + 1))"
CACHE_LOCAL="127.0.0.1:$((BASE_PORT + 10))"
CACHE_REMOTE="127.0.0.1:$((BASE_PORT + 11))"
DATA="${TMPDIR:-/tmp}/koutendb-local-remote-galaxy-demo-$$"
PIDS=()

cleanup() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" >/dev/null 2>&1 || true
    wait "${PIDS[@]}" >/dev/null 2>&1 || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

mkdir -p bin "$DATA"

echo "[local-remote-galaxy-demo] build koutend"
nim c -d:release --nimcache:/tmp/nimcache_koutend_local_remote_demo \
  -o:bin/koutend src/koutend.nim >/dev/null

echo "[local-remote-galaxy-demo] build koutencli"
nim c -d:release --nimcache:/tmp/nimcache_koutencli_local_remote_demo \
  -o:bin/koutencli src/koutencli.nim >/dev/null

echo "[local-remote-galaxy-demo] build demo"
nim c -d:release --nimcache:/tmp/nimcache_kouten_local_remote_demo \
  -o:bin/local_remote_galaxy_demo examples/local_remote_galaxy_demo.nim >/dev/null

start_node() {
  local label="$1"
  local peer="$2"
  local galaxy="$3"
  local user="$4"
  local password="$5"
  local secret_key="$6"
  local data_dir="$7"

  echo "[local-remote-galaxy-demo] start ${label}: ${peer} galaxy=${galaxy}"
  bin/koutend --id=0 --peers="$peer" --data="$data_dir" --galaxy="$galaxy" \
    --user="$user" --password="$password" --secret-key="$secret_key" \
    --slow-tick=0.05 &
  PIDS+=("$!")
}

wait_health() {
  local label="$1"
  local peer="$2"
  local galaxy="$3"
  local user="$4"
  local password="$5"
  local secret_key="$6"

  for _ in $(seq 1 50); do
    if bin/koutencli health --peers="$peer" --galaxy="$galaxy" \
      --user="$user" --password="$password" --secret-key="$secret_key" \
      >/dev/null 2>&1; then
      echo "[local-remote-galaxy-demo] healthy ${label}"
      return
    fi
    sleep 0.1
  done

  bin/koutencli health --peers="$peer" --galaxy="$galaxy" \
    --user="$user" --password="$password" --secret-key="$secret_key"
}

start_node "training local" "$TRAIN_LOCAL" "training-data" \
  "train" "train-pass" "train-secret-key" "$DATA/training-local"
start_node "training remote" "$TRAIN_REMOTE" "training-data" \
  "train" "train-pass" "train-secret-key" "$DATA/training-remote"
start_node "prompt-cache local" "$CACHE_LOCAL" "prompt-cache" \
  "cache" "cache-pass" "cache-secret-key" "$DATA/cache-local"
start_node "prompt-cache remote" "$CACHE_REMOTE" "prompt-cache" \
  "cache" "cache-pass" "cache-secret-key" "$DATA/cache-remote"

wait_health "training local" "$TRAIN_LOCAL" "training-data" \
  "train" "train-pass" "train-secret-key"
wait_health "training remote" "$TRAIN_REMOTE" "training-data" \
  "train" "train-pass" "train-secret-key"
wait_health "prompt-cache local" "$CACHE_LOCAL" "prompt-cache" \
  "cache" "cache-pass" "cache-secret-key"
wait_health "prompt-cache remote" "$CACHE_REMOTE" "prompt-cache" \
  "cache" "cache-pass" "cache-secret-key"

echo ""
echo "== KoutenDB local/remote galaxy switch demo =="
echo "training-data local  -> $TRAIN_LOCAL"
echo "training-data remote -> $TRAIN_REMOTE"
echo "prompt-cache local   -> $CACHE_LOCAL"
echo "prompt-cache remote  -> $CACHE_REMOTE"
echo ""

KOUTEN_TRAINING_LOCAL="$TRAIN_LOCAL" \
KOUTEN_TRAINING_REMOTE="$TRAIN_REMOTE" \
KOUTEN_CACHE_LOCAL="$CACHE_LOCAL" \
KOUTEN_CACHE_REMOTE="$CACHE_REMOTE" \
bin/local_remote_galaxy_demo
