#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${KOUTEN_EFFECT_WORKDIR:-}" ]]; then
  WORK="$KOUTEN_EFFECT_WORKDIR"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/koutendb-effect-matrix.XXXXXX")"
fi
BIN="$ROOT/bin/effect_validation_demo"
SCALE="${KOUTEN_EFFECT_SCALE:-1000}"
BATCH_SIZE="${KOUTEN_EFFECT_BATCH_SIZE:-10000}"
DISK_BACKED="${KOUTEN_EFFECT_DISK_BACKED:-1}"
PACK_DURING_IMPORT="${KOUTEN_EFFECT_PACK_DURING_IMPORT:-0}"

if [[ "${KOUTEN_EFFECT_QUICK:-0}" == "1" ]]; then
  SCALE=1
fi

cleanup() {
  if [[ "${KEEP_EFFECT_MATRIX:-0}" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "kept workdir: $WORK"
  fi
}
trap cleanup EXIT

mkdir -p "$WORK" "$ROOT/bin"
cd "$ROOT"

echo "== Build effect validation runner =="
nim c -d:release --nimcache:/tmp/nimcache_kouten_effect_matrix \
  -o:"$BIN" examples/effect_validation_demo.nim >/dev/null

write_ring() {
  local corpus="$1"
  local ring="$2"
  local prefix="$3"
  local title_prefix="$4"
  local text="$5"
  local emb="$6"
  local count="$7"

  for ((i=0; i<count; i++)); do
    local id
    printf -v id "%s-%06d" "$prefix" "$i"
    printf '{"ring":"%s","body":{"id":"%s","title":"%s %06d","text":"%s Example %06d includes enough detail for RAG prompt construction and downstream token estimates."},"embedding":[%s]}\n' \
      "$ring" "$id" "$title_prefix" "$i" "$text" "$i" "$emb" >> "$corpus"
  done
}

generate_corpus() {
  local corpus="$1"
  local docs_per_target="$2"
  local docs_per_neighbor="$3"
  local noise_docs="$4"
  local distractor_docs="$5"
  : > "$corpus"

  write_ring "$corpus" "docs/japan" "docs-japan" "Japanese refund support" \
    "Japanese customers should contact support with order number, invoice email, payment method, and refund reason. Support confirms eligibility and starts the refund workflow." \
    "1.0,0.02,0.01,0.0" "$docs_per_target"
  write_ring "$corpus" "docs/us" "docs-us" "US enterprise billing" \
    "US enterprise customers should contact billing administrators for invoice changes, SSO setup, procurement forms, and tax exemption requests." \
    "0.01,1.0,0.02,0.0" "$docs_per_neighbor"
  write_ring "$corpus" "support/errors" "support-errors" "Timeout incident runbook" \
    "Operators should check retry rates, database latency, queue depth, and recent deploys before escalating timeout incidents." \
    "0.0,0.02,1.0,0.02" "$docs_per_neighbor"
  write_ring "$corpus" "noise/general" "noise-general" "General background" \
    "Unrelated background material about office moves, lunch menus, planning notes, and generic announcements." \
    "0.05,0.04,0.03,1.0" "$noise_docs"
  write_ring "$corpus" "noise/near-japan" "noise-near-japan" "Near-topic distractor" \
    "Near-topic but irrelevant material mentions Japan, invoices, customer email, and support processes without describing refund eligibility." \
    "0.78,0.08,0.04,0.0" "$distractor_docs"
}

metric() {
  local key="$1"
  local file="$2"
  awk -v k="$key" '$1 == k { print $2; found=1 } END { if (!found) print "" }' "$file"
}

run_case() {
  local name="$1"
  local docs_per_target="$2"
  local docs_per_neighbor="$3"
  local noise_docs="$4"
  local distractor_docs="$5"
  local global_budget="$6"
  local routed_budget="$7"

  local case_dir="$WORK/$name"
  local corpus="$case_dir/corpus.jsonl"
  local data="$case_dir/data"
  local prompt="$case_dir/prompt.txt"
  local out="$case_dir/metrics.txt"
  rm -rf "$case_dir"
  mkdir -p "$case_dir"

  generate_corpus "$corpus" "$docs_per_target" "$docs_per_neighbor" "$noise_docs" "$distractor_docs"
  "$BIN" \
    --corpus="$corpus" \
    --data="$data" \
    --prompt-out="$prompt" \
    --ring=docs/japan \
    --question="How should a Japanese customer request a refund?" \
    --global-budget="$global_budget" \
    --routed-budget="$routed_budget" \
    --batch-size="$BATCH_SIZE" \
    $([[ "$DISK_BACKED" == "1" ]] && printf '%s' "--disk-backed") \
    $([[ "$PACK_DURING_IMPORT" == "1" ]] && printf '%s' "--pack-during-import") \
    --metrics > "$out"

  local docs global_scanned routed_scanned global_tokens routed_tokens scan_red token_red prompt_bytes global_us routed_us set_us set_us_record pack_us pack_records pack_rings pack_bytes
  docs="$(wc -l < "$corpus")"
  set_us="$(metric effectSetLatencyUs "$out")"
  set_us_record="$(metric effectSetLatencyUsPerRecord "$out")"
  pack_us="$(metric effectPackLatencyUs "$out")"
  pack_records="$(metric effectPackRecords "$out")"
  pack_rings="$(metric effectPackRings "$out")"
  pack_bytes="$(metric effectPackBytes "$out")"
  global_scanned="$(metric effectGlobalScanned "$out")"
  routed_scanned="$(metric effectRoutedScanned "$out")"
  global_tokens="$(metric effectGlobalTokens "$out")"
  routed_tokens="$(metric effectRoutedTokens "$out")"
  global_us="$(metric effectGlobalLatencyUs "$out")"
  routed_us="$(metric effectRoutedLatencyUs "$out")"
  scan_red="$(metric effectScannedReductionPct "$out")"
  token_red="$(metric effectTokenReductionPct "$out")"
  prompt_bytes="$(metric effectPromptBytes "$out")"

  printf '| %s | %s | %s | %s | %s | %s | %s | %s / %s / %s | %s -> %s | %s -> %s | %s -> %s | %s%% | %s%% | %s |\n' \
    "$name" "$docs" "$global_budget" "$routed_budget" \
    "$set_us" "$set_us_record" "$pack_us" "$pack_records" "$pack_rings" "$pack_bytes" \
    "$global_scanned" "$routed_scanned" "$global_tokens" "$routed_tokens" \
    "$global_us" "$routed_us" "$scan_red" "$token_red" "$prompt_bytes"
}

scaled() {
  local n="$1"
  echo $((n * SCALE))
}

echo
echo "== KoutenDB effect validation matrix =="
echo "scale: $SCALE"
echo "batch size: $BATCH_SIZE"
echo "disk backed: $DISK_BACKED"
echo "pack during import: $PACK_DURING_IMPORT"
echo
echo "| case | docs | global budget | routed budget | set latency us | set us/record | pack latency us | pack records/rings/bytes | scanned | tokens | retrieve latency us | scanned reduction | token reduction | prompt bytes |"
echo "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
run_case "small-balanced" "$(scaled 24)" "$(scaled 24)" "$(scaled 96)" 0 8 3
run_case "near-distractors" "$(scaled 120)" "$(scaled 120)" "$(scaled 1000)" "$(scaled 500)" 20 5
run_case "medium-noisy" "$(scaled 500)" "$(scaled 500)" "$(scaled 10000)" "$(scaled 2000)" 30 8

if [[ "${KOUTEN_EFFECT_LARGE:-0}" == "1" ]]; then
  run_case "large-noisy" "$(scaled 2000)" "$(scaled 2000)" "$(scaled 80000)" "$(scaled 12000)" 40 10
fi

echo
echo "Set KOUTEN_EFFECT_QUICK=1 for the small fast matrix."
echo "Set KOUTEN_EFFECT_SCALE=N to control generated corpus size."
echo "Set KOUTEN_EFFECT_BATCH_SIZE=N to control JSONL import chunk commits."
echo "Set KOUTEN_EFFECT_DISK_BACKED=0 to force the legacy in-memory validation path."
echo "Set KOUTEN_EFFECT_PACK_DURING_IMPORT=0 to measure explicit post-import segment packing."
echo "Set KOUTEN_EFFECT_LARGE=1 to include the larger stress case."
