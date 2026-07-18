#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DATA="${TMPDIR:-/tmp}/rochedb-cabi-tls-smoke-$$"
PORT="${ROCHE_CABI_TLS_SMOKE_PORT:-$((17661 + ($$ % 1000)))}"
PEERS="localhost:${PORT}"
CERT="$DATA/server.crt"
KEY="$DATA/server.key"
CA_CERT="$DATA/ca.crt"
CA_KEY="$DATA/ca.key"
CSR="$DATA/server.csr"
EXT="$DATA/server.ext"
LOG="$DATA/roched.log"
PID=""

cleanup() {
  if [ -n "${PID:-}" ]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

mkdir -p "$DATA/node0" bin

echo "[cabi-tls] generate test CA and server certificate"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -keyout "$CA_KEY" \
  -out "$CA_CERT" \
  -subj "/CN=RocheDB Test CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1
openssl req -nodes -newkey rsa:2048 \
  -keyout "$KEY" \
  -out "$CSR" \
  -subj "/CN=localhost" >/dev/null 2>&1
cat >"$EXT" <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
EXT
openssl x509 -req -in "$CSR" \
  -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$CERT" -days 1 -sha256 -extfile "$EXT" >/dev/null 2>&1

echo "[cabi-tls] build TLS-enabled C ABI library"
scripts/build_capi.sh >/dev/null

echo "[cabi-tls] build TLS-enabled roched"
nim c -d:ssl -d:release --nimcache:/tmp/nimcache_roched_cabi_tls \
  -o:src/roched src/roched.nim >/dev/null

echo "[cabi-tls] build C ABI TLS contract"
gcc examples/cabi_tls_contract.c -Iinclude -Llib -lrochedb \
  -Wl,-rpath,'$ORIGIN/../lib' -o bin/cabi_tls_contract

echo "[cabi-tls] start TLS roched on $PEERS"
src/roched --id=0 --peers="$PEERS" --data="$DATA/node0" \
  --user=alice --password=secret --secret-key=shared-secret \
  --tls-cert="$CERT" --tls-key="$KEY" \
  --slow-tick=0.05 >"$LOG" 2>&1 &
PID=$!

for _ in $(seq 1 60); do
  if grep -q "listening" "$LOG" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

echo "[cabi-tls] run C ABI TLS contract"
ROCHE_TLS_PEERS="$PEERS" ROCHE_TLS_CA="$CA_CERT" ROCHE_TLS_INSECURE=0 \
  LD_LIBRARY_PATH=lib bin/cabi_tls_contract

echo "[cabi-tls] OK"
