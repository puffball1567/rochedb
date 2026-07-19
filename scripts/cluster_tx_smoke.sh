#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ORBELIAS_CLUSTER_TEST_BASE_PORT:-17411}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
DATA="${TMPDIR:-/tmp}/orbeliasdb-cluster-tx-smoke-$$"
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

echo "[cluster-tx] build orbeliasd"
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:src/orbeliasd src/orbeliasd.nim

echo "[cluster-tx] build orbeliascli"
nim c -d:release --nimcache:/tmp/nimcache_orbeliascli -o:src/orbeliascli src/orbeliascli.nim

echo "[cluster-tx] start 3 nodes on $PEERS"
mkdir -p "$DATA"
for id in 0 1 2; do
  src/orbeliasd --id="$id" --peers="$PEERS" --data="$DATA/node$id" --slow-tick=0.05 &
  PIDS+=("$!")
done

echo "[cluster-tx] wait for health"
for _ in $(seq 1 50); do
  if src/orbeliascli health --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
src/orbeliascli health --peers="$PEERS"

echo "[cluster-tx] run tcluster_tx"
ORBELIAS_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_orbelias_tcluster_tx -r tests/tcluster_tx.nim

echo "[cluster-tx] OK"

