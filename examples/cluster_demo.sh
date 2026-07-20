#!/usr/bin/env bash
# KoutenDB scale-out demo: start three koutend processes, observe orbital
# handoff between processes, and verify projection plus persistence.
# Prerequisite: nim c -d:release -o:bin/koutend src/koutend.nim
#         nim c -d:release -o:bin/koutencli src/koutencli.nim
set -eu
cd "$(dirname "$0")/.."

PEERS="127.0.0.1:7301,127.0.0.1:7302,127.0.0.1:7303"
DATA="${TMPDIR:-/tmp}/koutendb-demo-$$"
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; }
trap cleanup EXIT

for i in 0 1 2; do
  bin/koutend --id=$i --peers="$PEERS" --data="$DATA/node$i" &
  PIDS+=($!)
done
sleep 0.5

bin/koutencli demo --peers="$PEERS"

echo ""
echo "== Persistence check: data remains after restarting all nodes =="
kill "${PIDS[@]}"; wait 2>/dev/null || true; PIDS=()
for i in 0 1 2; do
  bin/koutend --id=$i --peers="$PEERS" --data="$DATA/node$i" &
  PIDS+=($!)
done
sleep 0.5
bin/koutencli bench --peers="$PEERS" --n=2000
