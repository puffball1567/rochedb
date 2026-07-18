#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ROCHE_CLUSTER_TEST_BASE_PORT:-17611}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
DATA="${TMPDIR:-/tmp}/rochedb-cluster-authz-smoke-$$"
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

echo "[cluster-authz] build roched"
nim c -d:release --nimcache:/tmp/nimcache_roched_authz -o:src/roched src/roched.nim

echo "[cluster-authz] build rochecli"
nim c -d:release --nimcache:/tmp/nimcache_rochecli_authz -o:src/rochecli src/rochecli.nim

echo "[cluster-authz] unusable auth config fails closed"
if src/roched --id=0 --peers="127.0.0.1:1" --data="$DATA/bad-secret" \
    --secret-key=secret >/dev/null 2>&1; then
  echo "roched accepted --secret-key without --user/--password" >&2
  exit 1
fi
if src/roched --id=0 --peers="127.0.0.1:1" --data="$DATA/bad-password" \
    --user=alice >/dev/null 2>&1; then
  echo "roched accepted --user without --password" >&2
  exit 1
fi

echo "[cluster-authz] start 3 nodes on $PEERS"
mkdir -p "$DATA"
printf 'secret\n' > "$DATA/password"
for id in 0 1 2; do
  src/roched --id="$id" --peers="$PEERS" --data="$DATA/node$id" \
    --slow-tick=0.05 --user=alice --password-file="$DATA/password" \
    --allow-ring=allowed &
  PIDS+=("$!")
done

echo "[cluster-authz] wait for health"
for _ in $(seq 1 50); do
  if ROCHE_PASSWORD=secret src/rochecli health --peers="$PEERS" --user=alice >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
ROCHE_PASSWORD=secret src/rochecli health --peers="$PEERS" --user=alice

echo "[cluster-authz] run tcluster_authz"
ROCHE_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_roche_tcluster_authz -r tests/tcluster_authz.nim

echo "[cluster-authz] OK"
