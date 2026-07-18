#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ROCHE_WIRE_DRIVER_BASE_PORT:-17631}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1))"

cd "$ROOT"

echo "[cluster-wire-driver] build roched"
nim c -d:release --nimcache:/tmp/nimcache_roched_wire_driver -o:src/roched src/roched.nim

echo "[cluster-wire-driver] run twire_driver"
ROCHE_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_roche_twire_driver -r tests/twire_driver.nim

echo "[cluster-wire-driver] OK"
