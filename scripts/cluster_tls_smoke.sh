#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DATA="${TMPDIR:-/tmp}/rochedb-cluster-tls-smoke-$$"
PEERS="127.0.0.1:17651"
CERT="$DATA/server.crt"
KEY="$DATA/server.key"
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

mkdir -p "$DATA/node0"

echo "[cluster-tls] generate self-signed test certificate"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -keyout "$KEY" \
  -out "$CERT" \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1

echo "[cluster-tls] build TLS-enabled roched"
nim c -d:ssl -d:release --nimcache:/tmp/nimcache_roched_tls \
  -o:src/roched src/roched.nim >/dev/null

echo "[cluster-tls] build TLS-enabled roche CLI"
nim c -d:ssl -d:release --nimcache:/tmp/nimcache_rochecli_tls \
  -o:src/rochecli src/rochecli.nim >/dev/null

echo "[cluster-tls] start TLS roched on $PEERS"
src/roched --id=0 --peers="$PEERS" --data="$DATA/node0" \
  --user=alice --password=secret --secret-key=shared-secret \
  --tls-cert="$CERT" --tls-key="$KEY" --tls-ca="$CERT" \
  --slow-tick=0.05 >"$LOG" 2>&1 &
PID=$!

for _ in $(seq 1 60); do
  if src/rochecli health --peers="$PEERS" --user=alice --password=secret \
      --secret-key=shared-secret --tls --tls-ca="$CERT" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "[cluster-tls] health over TLS"
src/rochecli health --peers="$PEERS" --user=alice --password=secret \
  --secret-key=shared-secret --tls --tls-ca="$CERT"

echo "[cluster-tls] put JSON over TLS"
PUT_OUTPUT="$(src/rochecli put --peers="$PEERS" --user=alice --password=secret \
  --secret-key=shared-secret --tls --tls-ca="$CERT" \
  --ring=secure/demo --codec=json --payload='{"title":"tls smoke","ok":true}')"
echo "$PUT_OUTPUT"
RAW_ID="$(printf '%s\n' "$PUT_OUTPUT" | sed -n 's/.*rawId=\([^ ]*\).*/\1/p')"
test -n "$RAW_ID"

echo "[cluster-tls] get JSON over TLS"
GET_OUTPUT="$(src/rochecli get --peers="$PEERS" --user=alice --password=secret \
  --secret-key=shared-secret --tls --tls-ca="$CERT" \
  --ring=secure/demo --filter="{\"id\":\"$RAW_ID\"}" --selection='{ title ok }')"
echo "$GET_OUTPUT"
printf '%s\n' "$GET_OUTPUT" | grep -q '"title": "tls smoke"'
printf '%s\n' "$GET_OUTPUT" | grep -q '"ok": true'

echo "[cluster-tls] plain client must not pass against TLS listener"
if src/rochecli health --peers="$PEERS" --user=alice --password=secret \
    --secret-key=shared-secret >/dev/null 2>&1; then
  echo "plain client unexpectedly succeeded against TLS listener" >&2
  exit 1
fi

echo "[cluster-tls] OK"
