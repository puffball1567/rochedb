#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP="${TMPDIR:-/tmp}/roche-recovery-smoke-$$"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/src" "$TMP/plain-a" "$TMP/plain-b" "$TMP/encrypted"

nim c -d:release --nimcache:/tmp/nimcache_rochecli_recovery -o:bin/rochecli src/rochecli.nim >/dev/null

cat > "$TMP/src/roche.log" <<'LOG'
G 15
recovery-smoke
N 1 8
docs/ops
R 1 60.0 0.0
P 1 0 60.0 0.0 1.0 5 0
hello
LOG

echo "[recovery-smoke] plain mirrors"
bin/rochecli recovery-backup \
  --data="$TMP/src" \
  --mirror="$TMP/plain-a" \
  --mirror="$TMP/plain-b" >/dev/null

plain_metrics="$(bin/rochecli recovery-verify --mirror="$TMP/plain-a" --metrics)"
echo "$plain_metrics"
grep -q "recoveryMirrorHealthy 1" <<<"$plain_metrics"
grep -q "recoveryMirrorEncrypted 0" <<<"$plain_metrics"
grep -q "recoveryMirrorItems 1" <<<"$plain_metrics"
grep -q "recoveryMirrorRings 1" <<<"$plain_metrics"

bin/rochecli recovery-verify --mirror="$TMP/plain-b" >/dev/null

echo "[recovery-smoke] encrypted mirror"
bin/rochecli recovery-backup \
  --data="$TMP/src" \
  --mirror="$TMP/encrypted" \
  --passphrase=recovery-passphrase >/dev/null

encrypted_metrics="$(bin/rochecli recovery-verify \
  --mirror="$TMP/encrypted" \
  --passphrase=recovery-passphrase \
  --metrics)"
echo "$encrypted_metrics"
grep -q "recoveryMirrorHealthy 1" <<<"$encrypted_metrics"
grep -q "recoveryMirrorEncrypted 1" <<<"$encrypted_metrics"

echo "[recovery-smoke] manifest mismatch fails closed"
perl -0pi -e 's/"items": 1/"items": 2/' "$TMP/plain-a/roche.recovery.json"
if bin/rochecli recovery-verify --mirror="$TMP/plain-a" >/dev/null 2>&1; then
  echo "recovery-verify unexpectedly accepted mismatched manifest" >&2
  exit 1
fi

echo "[recovery-smoke] OK"
