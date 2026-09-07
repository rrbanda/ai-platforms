#!/usr/bin/env bash
# Extracts default vLLM args for a model from model-configs.json.
# Usage: ./get-default-args.sh "<model-name>"
# Output: one arg per line (machine-readable), or JSON with --json flag.
#
# Matching order:
#   1. Model family (llama, qwen, deepseek, ...)
#   2. Variant within family (fp8, instruct, code, embedding, llm)
#   3. Size-specific additional_args (8b, 70b, ...)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/model-configs.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: model-configs.json not found at $CONFIG" >&2
  exit 1
fi

MODEL="${1:-}"
JSON_OUTPUT=false

if [[ -z "$MODEL" ]]; then
  echo "Usage: $0 <model-name> [--json]" >&2
  exit 1
fi

if [[ "${2:-}" == "--json" ]]; then
  JSON_OUTPUT=true
fi

MODEL_LOWER=$(echo "$MODEL" | tr '[:upper:]' '[:lower:]')

# --- Detect family ---
FAMILY=""
FAMILY_KEYS=$(jq -r '.model_families | keys[]' "$CONFIG")

for family in $FAMILY_KEYS; do
  patterns=$(jq -r --arg f "$family" '.model_families[$f].patterns[]' "$CONFIG")
  while IFS= read -r pattern; do
    pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
    if [[ "$MODEL_LOWER" == *"$pattern_lower"* ]]; then
      FAMILY="$family"
      break 2
    fi
  done <<< "$patterns"
done

if [[ -z "$FAMILY" ]]; then
  echo "WARNING: No family match for '$MODEL' — using global_defaults" >&2
  VARIANT="inference"
  ARGS=$(jq -r '.global_defaults.inference.args[]' "$CONFIG")
  if $JSON_OUTPUT; then
    jq -n --argjson args "$(jq '.global_defaults.inference.args' "$CONFIG")" \
      '{family: "unknown", variant: "inference", size: null, args: $args, additional_args: []}'
  else
    echo "$ARGS"
  fi
  exit 0
fi

# --- Detect variant within family ---
AVAILABLE_VARIANTS=$(jq -r --arg f "$FAMILY" '.model_families[$f].default_args | keys[]' "$CONFIG")

VARIANT=""
# Priority order: fp8 > embedding > code > instruct > llm
for candidate in fp8 embedding code instruct llm; do
  if echo "$AVAILABLE_VARIANTS" | grep -qx "$candidate"; then
    if [[ "$MODEL_LOWER" == *"$candidate"* ]]; then
      VARIANT="$candidate"
      break
    fi
  fi
done

# Fallback: pick instruct if model name has "instruct", else first available variant
if [[ -z "$VARIANT" ]]; then
  if [[ "$MODEL_LOWER" == *"instruct"* ]] && echo "$AVAILABLE_VARIANTS" | grep -qx "instruct"; then
    VARIANT="instruct"
  else
    VARIANT=$(echo "$AVAILABLE_VARIANTS" | head -1)
  fi
fi

# --- Detect size ---
SIZE=""
SIZE_KEYS=$(jq -r --arg f "$FAMILY" '.model_families[$f].size_specific // {} | keys[]' "$CONFIG" 2>/dev/null || true)

for size in $SIZE_KEYS; do
  size_lower=$(echo "$size" | tr '[:upper:]' '[:lower:]')
  # Match e.g. "8b", "70b", "8x7b" as word-like segments
  if echo "$MODEL_LOWER" | grep -qE "(^|[-_./])${size_lower}([^0-9]|$)"; then
    SIZE="$size"
    break
  fi
done

# --- Extract args ---
BASE_ARGS=$(jq -r --arg f "$FAMILY" --arg v "$VARIANT" \
  '.model_families[$f].default_args[$v][]' "$CONFIG")

ADDITIONAL_ARGS=""
if [[ -n "$SIZE" ]]; then
  ADDITIONAL_ARGS=$(jq -r --arg f "$FAMILY" --arg s "$SIZE" \
    '.model_families[$f].size_specific[$s].additional_args // [] | .[]' "$CONFIG")
fi

if $JSON_OUTPUT; then
  BASE_JSON=$(jq --arg f "$FAMILY" --arg v "$VARIANT" \
    '.model_families[$f].default_args[$v]' "$CONFIG")
  ADD_JSON="[]"
  if [[ -n "$SIZE" ]]; then
    ADD_JSON=$(jq --arg f "$FAMILY" --arg s "$SIZE" \
      '.model_families[$f].size_specific[$s].additional_args // []' "$CONFIG")
  fi
  jq -n \
    --arg family "$FAMILY" \
    --arg variant "$VARIANT" \
    --arg size "${SIZE:-null}" \
    --argjson base "$BASE_JSON" \
    --argjson additional "$ADD_JSON" \
    '{family: $family, variant: $variant, size: (if $size == "null" then null else $size end), args: $base, additional_args: $additional}'
else
  echo "$BASE_ARGS"
  if [[ -n "$ADDITIONAL_ARGS" ]]; then
    echo "$ADDITIONAL_ARGS"
  fi
fi
