#!/usr/bin/env bash
# OrbeliasDB scale-out demo: start three orbeliasd processes, observe orbital
# handoff between processes, and verify projection plus persistence.
# Prerequisite: nim c -d:release -o:bin/orbeliasd src/orbeliasd.nim
#         nim c -d:release -o:bin/orbeliascli src/orbeliascli.nim
set -eu
cd "$(dirname "$0")/.."

PEERS="127.0.0.1:7301,127.0.0.1:7302,127.0.0.1:7303"
DATA="${TMPDIR:-/tmp}/orbeliasdb-demo-$$"
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT

for i in 0 1 2; do
  bin/orbeliasd --id=$i --peers="$PEERS" --data="$DATA/node$i" &
  PIDS+=($!)
done
sleep 0.5

bin/orbeliascli demo --peers="$PEERS"

echo ""
echo "== Persistence check: data remains after restarting all nodes =="
kill "${PIDS[@]}"; wait 2>/dev/null || true; PIDS=()
for i in 0 1 2; do
  bin/orbeliasd --id=$i --peers="$PEERS" --data="$DATA/node$i" &
  PIDS+=($!)
done
sleep 0.5
bin/orbeliascli bench --peers="$PEERS" --n=2000
