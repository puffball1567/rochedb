#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/koutendb-payload-codecs-demo-$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT"
nim c -d:release --nimcache:/tmp/nimcache_kouten_payload_codecs_demo \
  -o:bin/payload_codecs_demo examples/payload_codecs_demo.nim
bin/payload_codecs_demo --data="$WORK/data"
