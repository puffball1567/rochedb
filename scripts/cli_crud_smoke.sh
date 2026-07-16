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
export ROCHE_DATA="$WORK/data"

echo "[cli-crud] build roche"
nim c -d:release --nimcache:/tmp/nimcache_roche_cli_crud \
  -o:bin/roche src/rochecli.nim >/dev/null
nim c -d:release --nimcache:/tmp/nimcache_roched_cli_crud \
  -o:src/roched src/roched.nim >/dev/null

echo "[cli-crud] help"
bin/roche --help | grep -q "roche put"

echo "[cli-crud] put"
put_out="$(bin/roche put --ring=docs/japan \
  --payload='{"title":"Hello","status":"draft"}' --codec=json)"
grep -q "put OK" <<<"$put_out"
raw_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$put_out")"
if [[ -z "$raw_id" ]]; then
  echo "put did not print rawId" >&2
  exit 1
fi

echo "[cli-crud] count/list/get/query"
bin/roche count-ring --ring=docs/japan |
  grep -q "count=1"
bin/roche get --ring=docs/japan |
  grep -q '"status": "draft"'
bin/roche get --ring=docs/japan --limit=1 --rsort=time |
  grep -q '"items"'
bin/roche get --ring=docs/japan --limit=1 --sort=id |
  grep -q '"sort": "id"'
bin/roche get --ring=docs/japan --limit=1 --sort=id |
  grep -q '"sortDirection": "asc"'
bin/roche list-ring --ring=docs/japan |
  grep -q '"rawId"'
bin/roche get --ring=docs/japan --filter="{\"id\":\"$raw_id\"}" |
  grep -q '"status": "draft"'
bin/roche get --ring=docs/japan --filter='{"status":"draft"}' --selection='{ title }' |
  grep -q '"title": "Hello"'
bin/roche query --ring=docs/japan --filter="{\"id\":\"$raw_id\"}" --selection='{ title }' |
  grep -q '"title": "Hello"'

echo "[cli-crud] stellar-near ring reads"
bin/roche put --ring=users/123 \
  --payload='{"kind":"user","name":"Alice"}' --codec=json >/dev/null
bin/roche put --ring=orders --near=users/123 \
  --payload='{"kind":"order","orderNo":"A-001"}' --codec=json >/dev/null
bin/roche put --ring=billing --near=users/123 \
  --payload='{"kind":"billing","plan":"pro"}' --codec=json >/dev/null
bin/roche put --ring=users/999/orders \
  --payload='{"kind":"order","orderNo":"B-999"}' --codec=json >/dev/null
stellar_user="$(bin/roche get --ring=users/123 --limit=10)"
grep -q '"ring": "users/123/orders"' <<<"$stellar_user"
grep -q '"ring": "users/123/billing"' <<<"$stellar_user"
if grep -q 'B-999' <<<"$stellar_user"; then
  echo "stellar user read included a distant ring" >&2
  exit 1
fi
stellar_order="$(bin/roche get --ring=users/123/orders --limit=10)"
grep -q '"ring": "users/123"' <<<"$stellar_order"
grep -q '"orderNo": "A-001"' <<<"$stellar_order"
stellar_subring="$(bin/roche get --ring=users/123 --subring=orders --limit=10)"
grep -q '"ring": "users/123/orders"' <<<"$stellar_subring"
if grep -q '"ring": "users/123/billing"' <<<"$stellar_subring"; then
  echo "subring read included billing" >&2
  exit 1
fi
stellar_named="$(bin/roche get --stellar=users/123 --filter='{"kind":"order"}' --subring=orders --limit=10)"
grep -q '"ring": "users/123/orders"' <<<"$stellar_named"
grep -q '"orderNo": "A-001"' <<<"$stellar_named"
if grep -q '"ring": "users/123/billing"' <<<"$stellar_named"; then
  echo "stellar read included billing" >&2
  exit 1
fi
bin/roche put --ring=shops/1123 \
  --payload='{"kind":"shop","name":"Shop 1123"}' --codec=json >/dev/null
bin/roche put --ring=orders/A-002 \
  --payload='{"kind":"order","orderNo":"A-002","userId":"123","shopId":"1123"}' --codec=json >/dev/null
bin/roche stellar attach --stellar=commerce/order/A-002 --ring=users/123 |
  grep -q '"status": "attached"'
bin/roche stellar attach --stellar=commerce/order/A-002 --ring=shops/1123 |
  grep -q '"status": "attached"'
bin/roche stellar attach --stellar=commerce/order/A-002 --ring=orders/A-002 |
  grep -q '"status": "attached"'
stellar_attached="$(bin/roche get --stellar=commerce/order/A-002 --filter='{"kind":"shop"}' --limit=10)"
grep -q '"ring": "shops/1123"' <<<"$stellar_attached"
bin/roche stellar detach --stellar=commerce/order/A-002 --ring=shops/1123 |
  grep -q '"status": "detached"'
stellar_detached="$(bin/roche get --stellar=commerce/order/A-002 --filter='{"kind":"shop"}' --limit=10)"
if grep -q '"ring": "shops/1123"' <<<"$stellar_detached"; then
  echo "detached stellar member remained visible" >&2
  exit 1
fi

echo "[cli-crud] explicit and profile-driven codecs"
printf '(object (title "NIF text"))' >"$WORK/payload.nif"
nif_out="$(bin/roche put --ring=artifacts/nif \
  --in="$WORK/payload.nif" --codec=nif)"
nif_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$nif_out")"
bin/roche get --ring=artifacts/nif --filter="{\"id\":\"$nif_id\"}" |
  grep -q '"codec": "nif"'
bin/roche get --ring=artifacts/nif --filter="{\"id\":\"$nif_id\"}" |
  grep -q '"encoding": "text"'

bin/roche ring-profile --ring=artifacts/auto-nif \
  --codec=nif --charset=UTF-8 --format-version=1 |
  grep -q '"defaultCodec": "nif"'
auto_nif_out="$(bin/roche put --ring=artifacts/auto-nif \
  --payload='(object (title "Auto NIF"))' --codec=auto)"
auto_nif_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$auto_nif_out")"
bin/roche get --ring=artifacts/auto-nif --filter="{\"id\":\"$auto_nif_id\"}" |
  grep -q '"codec": "nif"'

raw_out="$(bin/roche put --ring=logs/raw --payload='plain text payload' --codec=raw)"
raw_text_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$raw_out")"
bin/roche get --ring=logs/raw --filter="{\"id\":\"$raw_text_id\"}" |
  grep -q '"codec": "raw"'

echo "[cli-crud] binary codec display"
printf '\001\002\003\004' >"$WORK/payload.bif"
bif_out="$(bin/roche put --ring=artifacts/bif \
  --in="$WORK/payload.bif" --codec=bif)"
bif_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$bif_out")"
bin/roche get --ring=artifacts/bif --filter="{\"id\":\"$bif_id\"}" |
  grep -q '"codec": "bif"'
bin/roche get --ring=artifacts/bif --filter="{\"id\":\"$bif_id\"}" |
  grep -q '"encoding": "base64"'
bin/roche get --ring=artifacts/bif --filter="{\"id\":\"$bif_id\"}" --view=hex |
  grep -q '"encoding": "hex"'
cat >"$WORK/fake_nif_tool" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "decode" ]]; then
  exit 2
fi
out=""
for arg in "$@"; do
  case "$arg" in
    --out=*) out="${arg#--out=}" ;;
  esac
done
if [[ -z "$out" ]]; then
  exit 2
fi
printf '(decoded "from adapter")' >"$out"
TOOL
chmod +x "$WORK/fake_nif_tool"
ROCHEDB_NIF_TOOL="$WORK/fake_nif_tool" \
  bin/roche get --ring=artifacts/bif --filter="{\"id\":\"$bif_id\"}" |
  grep -q '"encoding": "nif"'
ROCHEDB_NIF_TOOL="$WORK/fake_nif_tool" \
  bin/roche get --ring=artifacts/bif --filter="{\"id\":\"$bif_id\"}" |
  grep -q '"adapter": "nif"'
ROCHEDB_NIF_TOOL="$WORK/fake_nif_tool" \
  bin/roche get --ring=artifacts/bif --filter="{\"id\":\"$bif_id\"}" |
  grep -q 'decoded'

echo "[cli-crud] read validation"
bad_filter_out="$(bin/roche get --ring=docs/japan --filter='[]' 2>&1 >/dev/null || true)"
grep -q 'filter must be a JSON object' <<<"$bad_filter_out"
bad_sort_out="$(bin/roche get --ring=docs/japan --sort=payload 2>&1 >/dev/null || true)"
grep -q 'sort field must be id, time, or write' <<<"$bad_sort_out"
bad_selection_out="$(bin/roche get --ring=artifacts/bif --selection='{ title }' 2>&1 >/dev/null || true)"
grep -q 'payload codec bif does not support JSON projection' <<<"$bad_selection_out"

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

echo "[cli-crud] cluster connection config"
cat >"$WORK/cluster-config.json" <<CONFIG
{
  "peers": ["127.0.0.1:${BASE_PORT}"],
  "user": "app",
  "password": "right",
  "secret-key": "secret",
  "galaxy": "",
  "tls": false
}
CONFIG
bin/roche health --config="$WORK/cluster-config.json" |
  grep -q "node=0"
config_put="$(bin/roche put --config="$WORK/cluster-config.json" \
  --ring=cluster/config-demo --payload='{"kind":"config"}' --codec=json)"
config_raw_id="$(sed -n 's/.*rawId=\([^ ]*\).*/\1/p' <<<"$config_put")"
bin/roche get --config="$WORK/cluster-config.json" \
  --ring=cluster/config-demo --filter="{\"id\":\"$config_raw_id\"}" |
  grep -q '"kind": "config"'

auth_out="$(bin/roche health --peers="127.0.0.1:${BASE_PORT}" \
  --user=app --password=wrong --secret-key=secret 2>&1 >/dev/null || true)"
grep -q '^error: AUTHRESP failed: ERR auth-required$' <<<"$auth_out"

echo "[cli-crud] OK"
