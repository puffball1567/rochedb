#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ORBELIAS_CLUSTER_TEST_BASE_PORT:-17711}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
DATA="${TMPDIR:-/tmp}/orbeliasdb-cluster-wire-fuzz-smoke-$$"
PIDS=()

cleanup() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" >/dev/null 2>&1 || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$DATA"

echo "[cluster-wire-fuzz] build orbeliasd"
nim c -d:release -d:orbeliasTestSmallLimits --nimcache:/tmp/nimcache_orbeliasd_wire_fuzz -o:src/orbeliasd src/orbeliasd.nim

echo "[cluster-wire-fuzz] build orbeliascli"
nim c -d:release --nimcache:/tmp/nimcache_orbeliascli_wire_fuzz -o:src/orbeliascli src/orbeliascli.nim

echo "[cluster-wire-fuzz] start 3 nodes on $PEERS"
for id in 0 1 2; do
  src/orbeliasd --id="$id" --peers="$PEERS" --data="$DATA/node$id" \
    --slow-tick=0.05 --user=alice --password=secret --allow-ring=allowed &
  PIDS+=("$!")
done

echo "[cluster-wire-fuzz] wait for health"
for _ in $(seq 1 50); do
  if src/orbeliascli health --peers="$PEERS" --user=alice --password=secret >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
src/orbeliascli health --peers="$PEERS" --user=alice --password=secret

echo "[cluster-wire-fuzz] run tcluster_wire_fuzz"
ORBELIAS_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_orbelias_tcluster_wire_fuzz -r tests/tcluster_wire_fuzz.nim

echo "[cluster-wire-fuzz] OK"
