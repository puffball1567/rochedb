#!/usr/bin/env bash
set -euo pipefail

N="${N:-10000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:14}"
ORBELIASD_IMAGE="${ORBELIASD_IMAGE:-orbeliasdb-bench:local}"
NETWORK="${NETWORK:-orbeliasdb-postgres-bench-$$}"
PG_CONTAINER="${PG_CONTAINER:-orbelias-postgres-bench-$$}"
ORBELIASD_PREFIX="${ORBELIASD_PREFIX:-orbelias-pg-orbeliasd-$$}"
BUILD_IMAGE="${BUILD_IMAGE:-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${ORBELIAS_BENCH_TMP:-$ROOT/.tmp/orbeliasdb-postgres-docker-bench-$$}"
ORBELIAS_DATA="$TMP_ROOT/orbelias"
POSTGRES_DATA="$TMP_ROOT/postgres"
PEERS="${ORBELIASD_PREFIX}0:17301,${ORBELIASD_PREFIX}1:17301,${ORBELIASD_PREFIX}2:17301"

cleanup() {
  docker rm -f "$PG_CONTAINER" "${ORBELIASD_PREFIX}0" "${ORBELIASD_PREFIX}1" "${ORBELIASD_PREFIX}2" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "missing required command: docker" >&2
  exit 127
fi

cd "$ROOT"

if [[ "$BUILD_IMAGE" == "1" ]]; then
  echo "[postgres-docker-bench] build OrbeliasDB image $ORBELIASD_IMAGE"
  docker build -f examples/compose/Dockerfile -t "$ORBELIASD_IMAGE" .
fi

cleanup
docker network create "$NETWORK" >/dev/null
mkdir -p "$ORBELIAS_DATA" "$POSTGRES_DATA"

echo "[postgres-docker-bench] start OrbeliasDB cluster on Docker network $NETWORK"
for id in 0 1 2; do
  mkdir -p "$ORBELIAS_DATA/node$id"
  docker run -d --rm --network "$NETWORK" --name "${ORBELIASD_PREFIX}${id}" \
    -v "$ORBELIAS_DATA/node$id:/data" \
    "$ORBELIASD_IMAGE" --id="$id" --peers="$PEERS" --slow-tick=0.05 >/dev/null
done

for _ in $(seq 1 50); do
  if docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/orbeliascli \
    "$ORBELIASD_IMAGE" health --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/orbeliascli \
  "$ORBELIASD_IMAGE" health --peers="$PEERS" >/dev/null

echo "[postgres-docker-bench] OrbeliasDB cluster benchmark"
docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/orbeliascli \
  "$ORBELIASD_IMAGE" bench --peers="$PEERS" --n="$N"

echo "[postgres-docker-bench] start PostgreSQL container"
docker run -d --rm --network "$NETWORK" --name "$PG_CONTAINER" \
  -v "$POSTGRES_DATA:/var/lib/postgresql/data" \
  -e POSTGRES_HOST_AUTH_METHOD=trust "$POSTGRES_IMAGE" >/dev/null

for _ in $(seq 1 80); do
  if docker exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
docker exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null

if ! docker exec "$PG_CONTAINER" pgbench --version >/dev/null 2>&1; then
  echo "missing pgbench in $POSTGRES_IMAGE; use POSTGRES_IMAGE with pgbench installed" >&2
  exit 127
fi

payload="$(printf "%${PAYLOAD_BYTES}s" "" | tr " " "a")"

docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
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

docker exec -i "$PG_CONTAINER" sh -c 'cat > /tmp/select.sql' <<SQL
\set id random(1, $N)
SELECT v FROM kv WHERE k = :id;
SQL

docker exec -i "$PG_CONTAINER" sh -c 'cat > /tmp/write.sql' <<SQL
\set id random(1, 1000000000)
INSERT INTO kv_write(k, v)
VALUES (:id, '$payload')
ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
SQL

run_pgbench() {
  local out
  if ! out="$(docker exec "$PG_CONTAINER" "$@" 2>&1)"; then
    printf "%s\n" "$out" >&2
    return 1
  fi
  printf "%s\n" "$out" | grep -E \
    "^(pgbench \\(|transaction type:|query mode:|number of clients:|number of threads:|number of transactions|latency average =|tps =)"
}

echo "[postgres-docker-bench] PostgreSQL primary-key SELECT"
run_pgbench pgbench -U postgres -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f /tmp/select.sql

echo "[postgres-docker-bench] PostgreSQL single-row write, synchronous_commit=off"
run_pgbench env PGOPTIONS="-c synchronous_commit=off" \
  pgbench -U postgres -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f /tmp/write.sql

echo "[postgres-docker-bench] PostgreSQL single-row write, synchronous_commit=on"
run_pgbench env PGOPTIONS="-c synchronous_commit=on" \
  pgbench -U postgres -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f /tmp/write.sql
