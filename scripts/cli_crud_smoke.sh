#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK="${TMPDIR:-/tmp}/roche-cli-crud-smoke-$$"
BASE_PORT="${ROCHE_CLI_CRUD_BASE_PORT:-17991}"
PIDS=()
cleanup() {
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" 2>/dev/null || true
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK" "$ROOT/bin"

echo "[cli-crud] build roche"
nim c -d:release --nimcache:/tmp/nimcache_roche_cli_crud \
  -o:bin/roche src/rochecli.nim >/dev/null
nim c -d:release --nimcache:/tmp/nimcache_roched_cli_crud \
  -o:src/roched src/roched.nim >/dev/null

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

echo "[cli-crud] auth error is user-facing"
src/roched --id=0 --peers="127.0.0.1:${BASE_PORT}" \
  --data="$WORK/auth-server" --user=app --password=right \
  --secret-key=secret --slow-tick=0.05 >"$WORK/auth-server.log" 2>&1 &
PIDS+=("$!")
for _ in $(seq 1 50); do
  if bin/roche health --peers="127.0.0.1:${BASE_PORT}" \
      --user=app --password=right --secret-key=secret >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
auth_out="$(bin/roche health --peers="127.0.0.1:${BASE_PORT}" \
  --user=app --password=wrong --secret-key=secret 2>&1 >/dev/null || true)"
grep -q '^error: AUTHRESP failed: ERR auth-required$' <<<"$auth_out"

echo "[cli-crud] OK"
