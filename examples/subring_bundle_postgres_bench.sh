#!/usr/bin/env bash
set -euo pipefail

N="${N:-10000}"
READS="${READS:-1000}"
TARGET_INDEX="${TARGET_INDEX:-}"
PGPORT="${PGPORT:-55434}"
PGHOST="${PGHOST:-127.0.0.1}"
PG_BIN="${PG_BIN:-}"
TMP_ROOT="${TMPDIR:-/tmp}/koutendb-subring-bundle-bench-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOUTEN_DATA="$TMP_ROOT/kouten"
PGDATA="$TMP_ROOT/pgdata"
PGLOG="$TMP_ROOT/postgres.log"
KOUTEN_BIN="$ROOT/bin/subring_bundle_bench"

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

cleanup() {
  if [[ -n "${PG_STARTED:-}" ]]; then
    "$PG_CTL" -D "$PGDATA" -m fast stop >/dev/null 2>&1 || true
  fi
  if [[ "${KEEP_KOUTEN_SUBRING_BUNDLE:-0}" != "1" ]]; then
    rm -rf "$TMP_ROOT"
  else
    echo "kept workdir: $TMP_ROOT"
  fi
}
trap cleanup EXIT

metric() {
  local key="$1"
  local file="$2"
  awk -v k="$key" '$1 == k { print $2; found=1 } END { if (!found) print "" }' "$file"
}

run_pgbench_latency() {
  local script="$1"
  local out
  if ! out="$("$PGBENCH" -h "$PGHOST" -p "$PGPORT" -d postgres -n -M prepared -c 1 -j 1 -t "$READS" -f "$script" 2>&1)"; then
    printf "%s\n" "$out" >&2
    return 1
  fi
  printf "%s\n" "$out" | awk -F'= ' '/latency average =/ { sub(/ ms$/, "", $2); print $2 * 1000 }'
}

if ! command -v nim >/dev/null 2>&1; then
  echo "missing required command: nim" >&2
  exit 127
fi
need_path initdb INITDB
need_path pg_ctl PG_CTL
need_path psql PSQL
need_path pgbench PGBENCH

if [[ -z "$TARGET_INDEX" ]]; then
  TARGET_INDEX=$((N / 2))
fi
TARGET_ID="$(printf "user-%08d" "$TARGET_INDEX")"

mkdir -p "$TMP_ROOT" "$ROOT/bin"
cd "$ROOT"

echo "[subring-bundle-bench] build KoutenDB benchmark"
nim c -d:release --nimcache:/tmp/nimcache_kouten_subring_bundle_bench \
  -o:"$KOUTEN_BIN" examples/subring_bundle_bench.nim >/dev/null

echo "[subring-bundle-bench] run KoutenDB bundle benchmark"
kouten_out="$TMP_ROOT/kouten.txt"
"$KOUTEN_BIN" --data="$KOUTEN_DATA" --users="$N" --target-index="$TARGET_INDEX" \
  --reads="$READS" --disk-backed --metrics > "$kouten_out"

echo "[subring-bundle-bench] init temporary PostgreSQL cluster on $PGHOST:$PGPORT"
"$INITDB" -A trust -D "$PGDATA" >/dev/null
if ! "$PG_CTL" -D "$PGDATA" -l "$PGLOG" -o "-h $PGHOST -p $PGPORT -k $TMP_ROOT" -w start >/dev/null; then
  cat "$PGLOG" >&2 || true
  exit 1
fi
PG_STARTED=1

echo "[subring-bundle-bench] load PostgreSQL bundle tables"
"$PSQL" -h "$PGHOST" -p "$PGPORT" -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
CREATE TABLE users (
  id text PRIMARY KEY,
  payload jsonb NOT NULL
);
CREATE TABLE user_addresses (
  user_id text NOT NULL,
  n integer NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY (user_id, n)
);
CREATE TABLE user_careers (
  user_id text NOT NULL,
  n integer NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY (user_id, n)
);
CREATE TABLE user_preferences (
  user_id text PRIMARY KEY,
  payload jsonb NOT NULL
);
CREATE TABLE user_orders (
  user_id text NOT NULL,
  n integer NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY (user_id, n)
);
CREATE TABLE user_notifications (
  user_id text NOT NULL,
  n integer NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY (user_id, n)
);

INSERT INTO users
SELECT
  format('user-%s', lpad(i::text, 8, '0')),
  jsonb_build_object('kind', 'profile', 'userId', format('user-%s', lpad(i::text, 8, '0')),
                     'name', 'Bundle User ' || i, 'tier',
                     CASE WHEN i % 17 = 0 THEN 'enterprise' ELSE 'standard' END)
FROM generate_series(0, $((N - 1))) AS s(i);

INSERT INTO user_addresses
SELECT u.id, n,
       jsonb_build_object('kind', 'address', 'userId', u.id, 'n', n,
                          'country', CASE WHEN n % 2 = 0 THEN 'JP' ELSE 'US' END,
                          'line', n || ' Orbit Avenue')
FROM users u CROSS JOIN generate_series(0, 7) AS n;

INSERT INTO user_careers
SELECT u.id, n,
       jsonb_build_object('kind', 'career', 'userId', u.id, 'n', n,
                          'company', 'Company ' || n,
                          'role', CASE WHEN n = 0 THEN 'Engineer' ELSE 'Advisor' END)
FROM users u CROSS JOIN generate_series(0, 4) AS n;

INSERT INTO user_preferences
SELECT u.id,
       jsonb_build_object('kind', 'preferences', 'userId', u.id,
                          'locale', CASE WHEN substring(u.id from '[0-9]+')::int % 3 = 0 THEN 'ja-JP'
                                         WHEN substring(u.id from '[0-9]+')::int % 3 = 1 THEN 'en-US'
                                         ELSE 'fr-FR' END,
                          'newsletter', substring(u.id from '[0-9]+')::int % 2 = 0)
FROM users u;

INSERT INTO user_orders
SELECT u.id, n,
       jsonb_build_object('kind', 'order', 'userId', u.id, 'n', n,
                          'sku', 'SKU-' || lpad((substring(u.id from '[0-9]+')::int % 1000)::text, 4, '0') || '-' || lpad(n::text, 2, '0'),
                          'amount', 1000 + ((substring(u.id from '[0-9]+')::int + n) % 20000))
FROM users u CROSS JOIN generate_series(0, 49) AS n;

INSERT INTO user_notifications
SELECT u.id, n,
       jsonb_build_object('kind', 'notification', 'userId', u.id, 'n', n,
                          'unread', n % 3 = 0, 'title', 'Notification ' || n)
FROM users u CROSS JOIN generate_series(0, 39) AS n;

ANALYZE;
SQL

multi_sql="$TMP_ROOT/postgres-multi-select.sql"
json_sql="$TMP_ROOT/postgres-json-bundle.sql"

cat >"$multi_sql" <<SQL
SELECT payload FROM users WHERE id = '$TARGET_ID';
SELECT payload FROM user_addresses WHERE user_id = '$TARGET_ID' ORDER BY n LIMIT 3;
SELECT payload FROM user_careers WHERE user_id = '$TARGET_ID' ORDER BY n LIMIT 2;
SELECT payload FROM user_preferences WHERE user_id = '$TARGET_ID';
SELECT payload FROM user_orders WHERE user_id = '$TARGET_ID' ORDER BY n DESC LIMIT 10;
SELECT payload FROM user_notifications WHERE user_id = '$TARGET_ID' ORDER BY n DESC LIMIT 5;
SQL

cat >"$json_sql" <<SQL
SELECT jsonb_build_object(
  'profile', (SELECT payload FROM users WHERE id = '$TARGET_ID'),
  'addresses', (SELECT jsonb_agg(payload ORDER BY n) FROM (SELECT payload, n FROM user_addresses WHERE user_id = '$TARGET_ID' ORDER BY n LIMIT 3) s),
  'career', (SELECT jsonb_agg(payload ORDER BY n) FROM (SELECT payload, n FROM user_careers WHERE user_id = '$TARGET_ID' ORDER BY n LIMIT 2) s),
  'preferences', (SELECT payload FROM user_preferences WHERE user_id = '$TARGET_ID'),
  'orders', (SELECT jsonb_agg(payload ORDER BY n DESC) FROM (SELECT payload, n FROM user_orders WHERE user_id = '$TARGET_ID' ORDER BY n DESC LIMIT 10) s),
  'notifications', (SELECT jsonb_agg(payload ORDER BY n DESC) FROM (SELECT payload, n FROM user_notifications WHERE user_id = '$TARGET_ID' ORDER BY n DESC LIMIT 5) s)
);
SQL

pg_multi_us="$(run_pgbench_latency "$multi_sql")"
pg_json_us="$(run_pgbench_latency "$json_sql")"

kouten_set="$(metric subringBundleSetLatencyUs "$kouten_out")"
kouten_set_record="$(metric subringBundleSetUsPerRecord "$kouten_out")"
kouten_pack="$(metric subringBundlePackLatencyUs "$kouten_out")"
kouten_pack_records="$(metric subringBundlePackRecords "$kouten_out")"
kouten_read="$(metric subringBundleReadLatencyUs "$kouten_out")"
kouten_count="$(metric subringBundleReadCount "$kouten_out")"
kouten_rings="$(metric subringBundleReadRings "$kouten_out")"
kouten_records="$(metric subringBundleLogicalRecords "$kouten_out")"

echo
echo "== KoutenDB vs PostgreSQL heterogeneous subring bundle benchmark =="
echo "users: $N"
echo "logical records: $kouten_records"
echo "target: $TARGET_ID"
echo "reads: $READS"
echo
echo "| system | layout/query | returned records | setup or load note | read latency us |"
echo "| --- | --- | ---: | --- | ---: |"
echo "| KoutenDB | users/<id>/* stellar read with per-subring limits/sorts | $kouten_count across $kouten_rings rings | set ${kouten_set} us, ${kouten_set_record} us/record, pack ${kouten_pack} us (${kouten_pack_records} records) | $kouten_read |"
echo "| PostgreSQL | 6 indexed SELECT statements, each with its own ORDER BY/LIMIT | 22 | tables analyzed after load | $pg_multi_us |"
echo "| PostgreSQL | one JSON aggregate query over indexed limited subqueries | 1 JSON bundle | tables analyzed after load | $pg_json_us |"
echo
echo "This benchmark compares a heterogeneous related-data bundle, not a single primary-key lookup."
echo "KoutenDB expresses the shape as coordinate-local subrings; PostgreSQL expresses it with multiple indexed reads or JSON aggregation."
