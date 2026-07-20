#!/usr/bin/env bash
set -euo pipefail

DOCS_PER_RING="${DOCS_PER_RING:-24}"
NOISE_DOCS="${NOISE_DOCS:-96}"
GLOBAL_BUDGET="${GLOBAL_BUDGET:-8}"
ROUTED_BUDGET="${ROUTED_BUDGET:-3}"
QUERY_RING="${QUERY_RING:-docs/japan}"
QUESTION="${QUESTION:-How should a Japanese customer request a refund?}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/koutendb-effect-validation-$$"
CORPUS="$WORK/corpus.jsonl"
DATA="$WORK/data"
PROMPT="$WORK/prompt.txt"

cleanup() {
  if [[ "${KEEP_EFFECT_VALIDATION_DEMO:-0}" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "kept workdir: $WORK"
  fi
}
trap cleanup EXIT

mkdir -p "$WORK" "$ROOT/bin"
cd "$ROOT"

write_ring() {
  local ring="$1"
  local prefix="$2"
  local title_prefix="$3"
  local text="$4"
  local emb="$5"

  for ((i=0; i<DOCS_PER_RING; i++)); do
    local id
    printf -v id "%s-%03d" "$prefix" "$i"
    printf '{"ring":"%s","body":{"id":"%s","title":"%s %03d","text":"%s Example %03d includes enough detail for a small local model to answer from retrieved context."},"embedding":[%s]}\n' \
      "$ring" "$id" "$title_prefix" "$i" "$text" "$i" "$emb" >> "$CORPUS"
  done
}

write_noise() {
  for ((i=0; i<NOISE_DOCS; i++)); do
    local id
    printf -v id "noise-general-%03d" "$i"
    printf '{"ring":"noise/general","body":{"id":"%s","title":"General background %03d","text":"Unrelated background material about office moves, lunch menus, planning notes, and generic announcements."},"embedding":[0.05,0.04,0.03,1.0]}\n' \
      "$id" "$i" >> "$CORPUS"
  done
}

echo "== Generate deterministic effect-validation corpus =="
write_ring "docs/japan" "docs-japan" "Japanese refund support" \
  "Japanese customers should contact support with their order number, invoice email, payment method, and refund reason. Support confirms eligibility and then starts the refund workflow." \
  "1.0,0.02,0.01,0.0"
write_ring "docs/us" "docs-us" "US enterprise billing" \
  "US enterprise customers should contact the billing administrator for invoice changes, SSO setup, procurement forms, and tax exemption requests." \
  "0.01,1.0,0.02,0.0"
write_ring "support/errors" "support-errors" "Timeout incident runbook" \
  "Operators should check retry rates, database latency, queue depth, and recent deploys before escalating timeout incidents." \
  "0.0,0.02,1.0,0.02"
write_noise

echo "corpus: $CORPUS"
echo "docs:   $(wc -l < "$CORPUS")"
echo

echo "== Build effect validation runner =="
nim c -d:release --nimcache:/tmp/nimcache_kouten_effect_validation \
  -o:bin/effect_validation_demo examples/effect_validation_demo.nim

echo
echo "== Retrieve compact context with KoutenDB =="
bin/effect_validation_demo \
  --corpus="$CORPUS" \
  --data="$DATA" \
  --prompt-out="$PROMPT" \
  --ring="$QUERY_RING" \
  --question="$QUESTION" \
  --global-budget="$GLOBAL_BUDGET" \
  --routed-budget="$ROUTED_BUDGET"

echo
echo "== Prompt preview =="
sed -n '1,40p' "$PROMPT"

echo
if [[ -n "${KOUTEN_TRUSTED_LLM_CMD:-}" ]]; then
  echo "== Run trusted tiny LLM command =="
  echo "command: $KOUTEN_TRUSTED_LLM_CMD"
  "${SHELL:-/bin/sh}" -lc "$KOUTEN_TRUSTED_LLM_CMD" < "$PROMPT"
else
  echo "LLM execution skipped."
  echo "Recommended trusted small model path:"
  echo "  ollama pull gemma4:e2b"
  echo "  KOUTEN_TRUSTED_LLM_CMD='ollama run gemma4:e2b' examples/effect_validation_demo.sh"
  echo
  echo "Gemma 4 E2B is the recommended demo target because it is an official Google Gemma 4 edge-size model."
fi
