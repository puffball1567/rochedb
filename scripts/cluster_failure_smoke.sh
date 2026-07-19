#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[cluster-failure] build orbeliasd"
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:src/orbeliasd src/orbeliasd.nim

echo "[cluster-failure] run tcluster_failure"
nim c --nimcache:/tmp/nimcache_orbelias_tcluster_failure -r tests/tcluster_failure.nim

echo "[cluster-failure] OK"

