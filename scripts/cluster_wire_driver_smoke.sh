#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${ORBELIAS_WIRE_DRIVER_BASE_PORT:-17631}"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1))"

cd "$ROOT"

echo "[cluster-wire-driver] build orbeliasd"
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd_wire_driver -o:src/orbeliasd src/orbeliasd.nim

echo "[cluster-wire-driver] run twire_driver"
ORBELIAS_TEST_PEERS="$PEERS" nim c --nimcache:/tmp/nimcache_orbelias_twire_driver -r tests/twire_driver.nim

echo "[cluster-wire-driver] OK"
