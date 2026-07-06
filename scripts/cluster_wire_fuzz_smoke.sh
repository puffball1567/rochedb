#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ROCHE_CLUSTER_TEST_BASE_PORT:-17711}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
DATA="${TMPDIR:-/tmp}/rochedb-cluster-wire-fuzz-smoke-$$"
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

echo "[cluster-wire-fuzz] build roched"
nim c -d:release --nimcache:/tmp/nimcache_roched_wire_fuzz -o:src/roched src/roched.nim

echo "[cluster-wire-fuzz] build rochecli"
nim c -d:release --nimcache:/tmp/nimcache_rochecli_wire_fuzz -o:src/rochecli src/rochecli.nim

echo "[cluster-wire-fuzz] start 3 nodes on $PEERS"
for id in 0 1 2; do
  src/roched --id="$id" --peers="$PEERS" --data="$DATA/node$id" \
    --slow-tick=0.05 --user=alice --password=secret --allow-ring=allowed &
  PIDS+=("$!")
done

echo "[cluster-wire-fuzz] wait for health"
for _ in $(seq 1 50); do
  if src/rochecli health --peers="$PEERS" --user=alice --password=secret >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
src/rochecli health --peers="$PEERS" --user=alice --password=secret

echo "[cluster-wire-fuzz] run tcluster_wire_fuzz"
ROCHE_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_roche_tcluster_wire_fuzz -r tests/tcluster_wire_fuzz.nim

echo "[cluster-wire-fuzz] OK"
