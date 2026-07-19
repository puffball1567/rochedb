#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ORBELIAS_CLUSTER_TEST_BASE_PORT:-17811}"
PEERS="127.0.0.1:${BASE_PORT}"
DATA="${TMPDIR:-/tmp}/orbeliasdb-cluster-rbac-smoke-$$"
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

echo "[cluster-rbac] build orbeliasd"
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd_rbac -o:src/orbeliasd src/orbeliasd.nim

echo "[cluster-rbac] build orbeliascli"
nim c -d:release --nimcache:/tmp/nimcache_orbeliascli_rbac -o:src/orbeliascli src/orbeliascli.nim

echo "[cluster-rbac] start node on $PEERS"
src/orbeliasd --id=0 --peers="$PEERS" --data="$DATA/node0" \
  --slow-tick=0.05 \
  --role=reader:read:reader:allowed \
  --role=writer:write:writer:allowed \
  --role=admin:admin:admin:allowed &
PID="$!"

echo "[cluster-rbac] wait for health"
for _ in $(seq 1 50); do
  if src/orbeliascli health --peers="$PEERS" --user=admin --password=admin >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "[cluster-rbac] run tcluster_rbac"
ORBELIAS_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_orbelias_tcluster_rbac -r tests/tcluster_rbac.nim

echo "[cluster-rbac] OK"
