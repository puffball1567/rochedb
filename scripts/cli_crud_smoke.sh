#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="${TMPDIR:-/tmp}/roche-cli-crud-smoke-$$"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK" "$ROOT/bin"

echo "[cli-crud] build roche"
nim c -d:release --nimcache:/tmp/nimcache_roche_cli_crud \
  -o:bin/roche src/rochecli.nim >/dev/null

echo "[cli-crud] help"
bin/roche --help | grep -q "roche put"

echo "[cli-crud] put"
put_out="$(bin/roche put --data="$WORK/data" --ring=docs/japan \
  --payload='{"title":"Hello","status":"draft"}')"
grep -q "put OK" <<<"$put_out"
raw_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$put_out")"
if [[ -z "$raw_id" ]]; then
  echo "put did not print rawId" >&2
  exit 1
fi

echo "[cli-crud] count/list/get/query"
bin/roche count-ring --data="$WORK/data" --ring=docs/japan |
  grep -q "count=1"
bin/roche list-ring --data="$WORK/data" --ring=docs/japan |
  grep -q '"rawId"'
bin/roche get --data="$WORK/data" --id="$raw_id" |
  grep -q '"status":"draft"'
bin/roche query --data="$WORK/data" --id="$raw_id" --selection='{ title }' |
  grep -q '"title": "Hello"'

echo "[cli-crud] shell"
shell_out="$(bin/roche shell --data="$WORK/shell" <<'SHELL'
put docs/japan {"title":"Shell","status":"ok"}
count docs/japan
list docs/japan
atlas
exit
SHELL
)"
grep -q "RocheDB shell" <<<"$shell_out"
grep -q "put OK" <<<"$shell_out"
grep -q "count=1" <<<"$shell_out"
grep -q '"title":"Shell"' <<<"$shell_out"
grep -q '"schema": "rochedb.atlas.v1"' <<<"$shell_out"

echo "[cli-crud] OK"
