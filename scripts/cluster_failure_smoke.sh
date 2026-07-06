#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[cluster-failure] build roched"
nim c -d:release --nimcache:/tmp/nimcache_roched -o:src/roched src/roched.nim

echo "[cluster-failure] run tcluster_failure"
nim c --nimcache:/tmp/nimcache_roche_tcluster_failure -r tests/tcluster_failure.nim

echo "[cluster-failure] OK"

