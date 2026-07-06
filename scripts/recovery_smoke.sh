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

cat > "$TMP/universe.json" <<JSON
{
  "version": 1,
  "requiredHealthy": 2,
  "lanes": [
    {
      "lane": "lane-a",
      "mirror": "$TMP/plain-a",
      "failureDomain": "local-a",
      "priority": 10,
      "snapshotSeq": 42
    },
    {
      "lane": "lane-b",
      "mirror": "$TMP/plain-b",
      "failureDomain": "local-b",
      "priority": 5,
      "snapshotSeq": 41
    }
  ]
}
JSON

echo "[recovery-smoke] plain mirrors"
bin/rochecli recovery-backup \
  --data="$TMP/src" \
  --universe-config="$TMP/universe.json" >/dev/null

plain_metrics="$(bin/rochecli recovery-verify --mirror="$TMP/plain-a" --metrics)"
echo "$plain_metrics"
grep -q "recoveryMirrorHealthy 1" <<<"$plain_metrics"
grep -q "recoveryMirrorEncrypted 0" <<<"$plain_metrics"
grep -q "recoveryMirrorItems 1" <<<"$plain_metrics"
grep -q "recoveryMirrorRings 1" <<<"$plain_metrics"
grep -q "recoveryMirrorPriority 10" <<<"$plain_metrics"
grep -q "recoveryMirrorSnapshotSeq 42" <<<"$plain_metrics"

bin/rochecli recovery-verify --mirror="$TMP/plain-b" >/dev/null

status_metrics="$(bin/rochecli recovery-status \
  --universe-config="$TMP/universe.json" \
  --metrics)"
echo "$status_metrics"
grep -q "recoveryUniverseHealthy 1" <<<"$status_metrics"
grep -q "recoveryHealthyLanes 2" <<<"$status_metrics"
grep -q "recoveryRequiredHealthyLanes 2" <<<"$status_metrics"
grep -q "recoveryBestPriority 10" <<<"$status_metrics"
grep -q "recoveryBestSnapshotSeq 42" <<<"$status_metrics"

echo "[recovery-smoke] restore selects eligible mirror"
mkdir -p "$TMP/restore"
bin/rochecli recovery-restore \
  --universe-config="$TMP/universe.json" \
  --data="$TMP/restore" >/dev/null
grep -q "hello" "$TMP/restore/roche.log"

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
if bin/rochecli recovery-status \
  --universe-config="$TMP/universe.json" >/dev/null 2>&1; then
  echo "recovery-status unexpectedly accepted too few healthy mirrors" >&2
  exit 1
fi
bin/rochecli recovery-status \
  --universe-config="$TMP/universe.json" \
  --required-healthy=1 >/dev/null

echo "[recovery-smoke] checksum mismatch fails closed"
printf 'x' >> "$TMP/plain-b/roche.log"
if bin/rochecli recovery-verify --mirror="$TMP/plain-b" >/dev/null 2>&1; then
  echo "recovery-verify unexpectedly accepted mismatched checksum" >&2
  exit 1
fi

echo "[recovery-smoke] OK"
