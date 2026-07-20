#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${KOUTEN_CLUSTER_TEST_BASE_PORT:-17411}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
DATA="${TMPDIR:-/tmp}/koutendb-cluster-tx-smoke-$$"
PIDS=()

cleanup() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" 2>/dev/null || true
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

cd "$ROOT"

echo "[cluster-tx] build koutend"
nim c -d:release --nimcache:/tmp/nimcache_koutend -o:src/koutend src/koutend.nim

echo "[cluster-tx] build koutencli"
nim c -d:release --nimcache:/tmp/nimcache_koutencli -o:src/koutencli src/koutencli.nim

echo "[cluster-tx] start 3 nodes on $PEERS"
mkdir -p "$DATA"
for id in 0 1 2; do
  src/koutend --id="$id" --peers="$PEERS" --data="$DATA/node$id" --slow-tick=0.05 &
  PIDS+=("$!")
done

echo "[cluster-tx] wait for health"
for _ in $(seq 1 50); do
  if src/koutencli health --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
src/koutencli health --peers="$PEERS"

echo "[cluster-tx] run tcluster_tx"
KOUTEN_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_kouten_tcluster_tx -r tests/tcluster_tx.nim

echo "[cluster-tx] OK"

