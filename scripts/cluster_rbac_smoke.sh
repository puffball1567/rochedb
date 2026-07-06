#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ROCHE_CLUSTER_TEST_BASE_PORT:-17811}"
PEERS="127.0.0.1:${BASE_PORT}"
DATA="${TMPDIR:-/tmp}/rochedb-cluster-rbac-smoke-$$"
PID=""

cleanup() {
  if [[ -n "$PID" ]]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$DATA"

echo "[cluster-rbac] build roched"
nim c -d:release --nimcache:/tmp/nimcache_roched_rbac -o:src/roched src/roched.nim

echo "[cluster-rbac] build rochecli"
nim c -d:release --nimcache:/tmp/nimcache_rochecli_rbac -o:src/rochecli src/rochecli.nim

echo "[cluster-rbac] start node on $PEERS"
src/roched --id=0 --peers="$PEERS" --data="$DATA/node0" \
  --slow-tick=0.05 \
  --role=reader:read:reader:allowed \
  --role=writer:write:writer:allowed \
  --role=admin:admin:admin:allowed &
PID="$!"

echo "[cluster-rbac] wait for health"
for _ in $(seq 1 50); do
  if src/rochecli health --peers="$PEERS" --user=admin --password=admin >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "[cluster-rbac] run tcluster_rbac"
ROCHE_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_roche_tcluster_rbac -r tests/tcluster_rbac.nim

echo "[cluster-rbac] OK"
