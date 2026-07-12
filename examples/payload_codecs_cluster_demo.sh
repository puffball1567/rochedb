#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ROCHE_PAYLOAD_CODECS_BASE_PORT:-18011}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1))"
WORK="${TMPDIR:-/tmp}/rochedb-payload-codecs-cluster-demo-$$"
PIDS=()

cleanup() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" >/dev/null 2>&1 || true
    wait "${PIDS[@]}" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$WORK" bin
nim c -d:release --nimcache:/tmp/nimcache_roched_payload_codecs_demo \
  -o:src/roched src/roched.nim
nim c -d:release --nimcache:/tmp/nimcache_roche_payload_codecs_cluster_demo \
  -o:bin/payload_codecs_cluster_demo examples/payload_codecs_cluster_demo.nim

for id in 0 1; do
  src/roched --id="$id" --peers="$PEERS" --data="$WORK/node$id" --slow-tick=0.05 &
  PIDS+=("$!")
done

for _ in $(seq 1 50); do
  if bin/payload_codecs_cluster_demo --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

bin/payload_codecs_cluster_demo --peers="$PEERS"
