#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${KOUTEN_JMETER_PORT:-17301}"
THREADS="${KOUTEN_JMETER_THREADS:-16}"
LOOPS="${KOUTEN_JMETER_LOOPS:-100}"
WORK="${TMPDIR:-/tmp}/koutendb-jmeter-load-$$"
DATA="$WORK/data"
JTL="$WORK/health-load.jtl"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ "${KEEP_JMETER_LOAD:-0}" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "kept workdir: $WORK"
  fi
}
trap cleanup EXIT

if ! command -v jmeter >/dev/null 2>&1; then
  echo "jmeter SKIP: Apache JMeter is not installed or not on PATH."
  echo "Install JMeter, then rerun:"
  echo "  KOUTEN_JMETER_THREADS=$THREADS KOUTEN_JMETER_LOOPS=$LOOPS examples/jmeter_load_smoke.sh"
  exit 0
fi

mkdir -p "$WORK" "$ROOT/bin"
cd "$ROOT"

echo "== Build koutend =="
nim c -d:release -d:ssl --nimcache:/tmp/nimcache_kouten_jmeter \
  -o:bin/koutend src/koutend.nim >/dev/null

echo "== Start koutend =="
bin/koutend --host=127.0.0.1 --port="$PORT" --data="$DATA" >"$WORK/koutend.log" 2>&1 &
SERVER_PID="$!"

for _ in {1..80}; do
  if grep -q "listening" "$WORK/koutend.log"; then
    break
  fi
  sleep 0.1
done

echo "== Run JMeter TCP HEALTH load =="
jmeter -n \
  -t examples/jmeter/koutendb-health-load.jmx \
  -Jkouten_host=127.0.0.1 \
  -Jkouten_port="$PORT" \
  -Jkouten_threads="$THREADS" \
  -Jkouten_loops="$LOOPS" \
  -Jkouten_jtl="$JTL"

echo
echo "JTL: $JTL"
tail -n 5 "$JTL" || true
