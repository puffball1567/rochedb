#!/usr/bin/env bash
set -euo pipefail

N="${N:-10000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
BASE_PORT="${KOUTEN_BENCH_BASE_PORT:-17311}"
PGPORT="${PGPORT:-55432}"
PGHOST="${PGHOST:-127.0.0.1}"
TMP_ROOT="${TMPDIR:-/tmp}/koutendb-postgres-bench-$$"
PG_BIN="${PG_BIN:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PEERS="127.0.0.1:${BASE_PORT},127.0.0.1:$((BASE_PORT + 1)),127.0.0.1:$((BASE_PORT + 2))"
KOUTEN_DATA="$TMP_ROOT/kouten"
PGDATA="$TMP_ROOT/pgdata"
PGLOG="$TMP_ROOT/postgres.log"
PIDS=()

resolve_cmd() {
  local name="$1"
  if [[ -n "$PG_BIN" && -x "$PG_BIN/$name" ]]; then
    printf "%s\n" "$PG_BIN/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  local candidate
  for candidate in /usr/lib/postgresql/*/bin/"$name" /opt/homebrew/opt/postgresql*/bin/"$name"; do
    if [[ -x "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done
  return 1
}

need_path() {
  local name="$1"
  local var_name="$2"
  local path
  if ! path="$(resolve_cmd "$name")"; then
    echo "missing required command: $name" >&2
    echo "hint: set PG_BIN=/path/to/postgresql/bin if PostgreSQL tools are not on PATH" >&2
    exit 127
  fi
  printf -v "$var_name" "%s" "$path"
}

run_pgbench() {
  local out
  if ! out="$("$PGBENCH" "$@" 2>&1)"; then
    printf "%s\n" "$out" >&2
    return 1
  fi
  printf "%s\n" "$out" | grep -E \
    "^(pgbench \\(|transaction type:|query mode:|number of clients:|number of threads:|number of transactions|latency average =|tps =)"
}

cleanup() {
  if [[ -n "${PG_STARTED:-}" ]]; then
    "$PG_CTL" -D "$PGDATA" -m fast stop >/dev/null 2>&1 || true
  fi
  if ((${#PIDS[@]} > 0)); then
    kill "${PIDS[@]}" >/dev/null 2>&1 || true
    wait "${PIDS[@]}" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if ! command -v nim >/dev/null 2>&1; then
  echo "missing required command: nim" >&2
  exit 127
fi
need_path initdb INITDB
need_path pg_ctl PG_CTL
need_path psql PSQL
need_path pgbench PGBENCH

cd "$ROOT"
mkdir -p "$KOUTEN_DATA" bin

payload="$(printf "%${PAYLOAD_BYTES}s" "" | tr " " "a")"
select_sql="$TMP_ROOT/select.sql"
write_sql="$TMP_ROOT/write.sql"

echo "[postgres-bench] build KoutenDB binaries"
nim c -d:release --nimcache:/tmp/nimcache_koutend -o:bin/koutend src/koutend.nim
nim c -d:release --nimcache:/tmp/nimcache_koutencli -o:bin/kouten src/koutencli.nim

echo "[postgres-bench] start KoutenDB cluster on $PEERS"
for id in 0 1 2; do
  bin/koutend --id="$id" --peers="$PEERS" --data="$KOUTEN_DATA/node$id" --slow-tick=0.05 &
  PIDS+=("$!")
done

for _ in $(seq 1 50); do
  if bin/kouten health --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
bin/kouten health --peers="$PEERS" >/dev/null

echo "[postgres-bench] KoutenDB cluster benchmark"
bin/kouten bench --peers="$PEERS" --n="$N"

echo "[postgres-bench] init temporary PostgreSQL cluster on $PGHOST:$PGPORT"
"$INITDB" -A trust -D "$PGDATA" >/dev/null
if ! "$PG_CTL" -D "$PGDATA" -l "$PGLOG" -o "-h $PGHOST -p $PGPORT -k $TMP_ROOT" -w start >/dev/null; then
  cat "$PGLOG" >&2 || true
  exit 1
fi
PG_STARTED=1

"$PSQL" -h "$PGHOST" -p "$PGPORT" -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
CREATE TABLE kv (
  k integer PRIMARY KEY,
  v text NOT NULL
);
INSERT INTO kv
SELECT i, repeat('a', $PAYLOAD_BYTES)
FROM generate_series(1, $N) AS s(i);

CREATE TABLE kv_write (
  k integer PRIMARY KEY,
  v text NOT NULL
);
SQL

cat >"$select_sql" <<SQL
\set id random(1, $N)
SELECT v FROM kv WHERE k = :id;
SQL

cat >"$write_sql" <<SQL
\set id random(1, 1000000000)
INSERT INTO kv_write(k, v)
VALUES (:id, '$payload')
ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
SQL

echo "[postgres-bench] PostgreSQL primary-key SELECT"
run_pgbench -h "$PGHOST" -p "$PGPORT" -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f "$select_sql"

echo "[postgres-bench] PostgreSQL single-row write, synchronous_commit=off"
PGOPTIONS="-c synchronous_commit=off" \
  run_pgbench -h "$PGHOST" -p "$PGPORT" -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f "$write_sql"

echo "[postgres-bench] PostgreSQL single-row write, synchronous_commit=on"
PGOPTIONS="-c synchronous_commit=on" \
  run_pgbench -h "$PGHOST" -p "$PGPORT" -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f "$write_sql"
