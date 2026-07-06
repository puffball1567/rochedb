#!/usr/bin/env bash
# RocheDB scale-out demo: start three roched processes, observe orbital
# handoff between processes, and verify projection plus persistence.
# Prerequisite: nim c -d:release -o:bin/roched src/roched.nim
#         nim c -d:release -o:bin/rochecli src/rochecli.nim
set -eu
cd "$(dirname "$0")/.."

PEERS="127.0.0.1:7301,127.0.0.1:7302,127.0.0.1:7303"
DATA="${TMPDIR:-/tmp}/rochedb-demo-$$"
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT

for i in 0 1 2; do
  bin/roched --id=$i --peers="$PEERS" --data="$DATA/node$i" &
  PIDS+=($!)
done
sleep 0.5

bin/rochecli demo --peers="$PEERS"

echo ""
echo "== Persistence check: data remains after restarting all nodes =="
kill "${PIDS[@]}"; wait 2>/dev/null || true; PIDS=()
for i in 0 1 2; do
  bin/roched --id=$i --peers="$PEERS" --data="$DATA/node$i" &
  PIDS+=($!)
done
sleep 0.5
bin/rochecli bench --peers="$PEERS" --n=2000
