#!/usr/bin/env bash
# Estimate VRAM requirement for a model.
# Resolution order: --vram flag → internal catalog DB → HuggingFace API → name heuristics
#
# Usage:
#   check-vram.sh <model>              # auto-detect source
#   check-vram.sh <model> -v           # verbose breakdown
#   check-vram.sh <model> --vram 40    # skip calculation, use manual GB value
#   check-vram.sh --vram 40            # no model name needed, just confirm the value
#
# Machine-readable output (always last line on stdout):
#   VRAM_GB=<number>
#
# Capture it in scripts:
#   VRAM=$(./check-vram.sh "org/model" | grep ^VRAM_GB= | cut -d= -f2)

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- Argument parsing ---
MODEL_NAME=""
MANUAL_VRAM=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vram)    MANUAL_VRAM="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -*) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
        *)  MODEL_NAME="$1"; shift ;;
    esac
done

# --- Manual override: skip all calculation ---
if [ -n "$MANUAL_VRAM" ]; then
    if [ -n "$MODEL_NAME" ]; then
        echo -e "${CYAN}Model:${NC}  $MODEL_NAME"
    fi
    echo -e "${GREEN}VRAM:   ${MANUAL_VRAM} GB${NC} (manually specified)"
    echo -e "${YELLOW}Source: manual override${NC}"
    echo ""
    echo "VRAM_GB=$MANUAL_VRAM"
    exit 0
fi

if [ -z "$MODEL_NAME" ]; then
    cat <<EOF >&2
Usage: $(basename "$0") <model> [-v] [--vram <GB>]

  <model>      Catalog name (e.g. RedHatAI/Qwen3-8B-FP8-dynamic)
               or HuggingFace ID (e.g. meta-llama/Llama-3.1-8B-Instruct)
  -v           Verbose: show VRAM calculation breakdown
  --vram <GB>  Skip calculation and use this value directly

Examples:
  $(basename "$0") "RedHatAI/Qwen3-8B-FP8-dynamic"
  $(basename "$0") "meta-llama/Llama-3.1-70B-Instruct" -v
  $(basename "$0") "my-custom-model" --vram 24
EOF
    exit 1
fi

# --- Precision helpers ---
# Returns: "bytes_per_param:precision_name:overhead_multiplier"
_precision_from_tags() {
    local tags="$1"
    if   [[ "$tags" =~ fp8|FP8|f8_e4m3|F8_E4M3 ]];       then echo "1:FP8:1.25"
    elif [[ "$tags" =~ nvfp4|NVFP4|mxfp4|MXFP4 ]];         then echo "0.5:NVFP4:1.15"
    elif [[ "$tags" =~ w4a16|W4A16|int4|INT4|fp4|FP4 ]];   then echo "0.5:INT4/W4A16:1.15"
    elif [[ "$tags" =~ w8a8|W8A8|int8|INT8 ]];              then echo "1:INT8/W8A8:1.25"
    elif [[ "$tags" =~ fp16|FP16|bf16|BF16|f16|F16|BF16 ]]; then echo "2:FP16/BF16:1.35"
    elif [[ "$tags" =~ fp32|FP32|f32|F32 ]];                then echo "4:FP32:1.35"
    else                                                          echo "2:FP16/BF16:1.35"  # safe default
    fi
}

# Extract parameter count in billions from model name
_params_from_name() {
    local name="$1"
    if   [[ "$name" =~ ([0-9]+\.?[0-9]*)[Bb](-| |_|$|\.) ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ "$name" =~ -([0-9]+\.?[0-9]*)b ]];                then echo "${BASH_REMATCH[1]}"
    elif [[ "$name" =~ ([0-9]+\.?[0-9]*)B ]];                 then echo "${BASH_REMATCH[1]}"
    else echo ""
    fi
}

_calc_vram() {
    local params_b="$1" precision_str="$2"
    local bpp; bpp=$(echo "$precision_str" | cut -d: -f1)
    local prec; prec=$(echo "$precision_str" | cut -d: -f2)
    local ovhd; ovhd=$(echo "$precision_str" | cut -d: -f3)
    local base; base=$(echo "scale=2; $params_b * $bpp" | bc)
    local total; total=$(echo "scale=2; $base * $ovhd" | bc)
    echo "$total:$prec:$base:$ovhd"
}

_verbose_breakdown() {
    local params_b="$1" prec="$2" base="$3" ovhd="$4" total="$5" source="$6"
    echo -e "  ${CYAN}Parameters:${NC}   ${params_b}B"
    echo -e "  ${CYAN}Precision:${NC}    $prec"
    echo -e "  ${CYAN}Base VRAM:${NC}    ${base} GB  (params × bytes/param)"
    echo -e "  ${CYAN}Overhead:${NC}     ${ovhd}×   (KV cache + activations + runtime)"
    echo -e "  ${CYAN}Total VRAM:${NC}   ${total} GB"
    echo -e "  ${CYAN}Source:${NC}       $source"
}

# ── Path 1: Internal catalog DB ────────────────────────────────────────────────
CATALOG_VRAM="" CATALOG_PREC_TAGS=""

_try_catalog() {
    local NAMESPACE="rhoai-model-registries"
    local pod; pod=$(oc get pods -n "$NAMESPACE" -o name 2>/dev/null | grep model-catalog-postgres | cut -d'/' -f2) || true
    [ -z "$pod" ] && return 1

    local db_user db_name
    db_user=$(oc get secret model-catalog-postgres -n "$NAMESPACE" -o yaml 2>/dev/null | yq '.data.database-user' | base64 -d) || return 1
    db_name=$(oc get secret model-catalog-postgres -n "$NAMESPACE" -o yaml 2>/dev/null | yq '.data.database-name' | base64 -d) || return 1

    local result
    result=$(oc exec -n "$NAMESPACE" "$pod" -- psql -U "$db_user" -d "$db_name" -t -c "
    SELECT
        cp_vram.string_value AS min_vram_gb,
        STRING_AGG(DISTINCT cp_prec.name, ',') AS precision_tags
    FROM \"Context\" c
    LEFT JOIN \"ContextProperty\" cp_vram  ON c.id = cp_vram.context_id  AND cp_vram.name = 'min_vram_gb'
    LEFT JOIN \"ContextProperty\" cp_prec  ON c.id = cp_prec.context_id
        AND cp_prec.name IN ('fp32','fp16','FP16','bf16','fp8','FP8',
                              'int4','INT4','int8','INT8',
                              'w4a16','W4A16','w8a8','W8A8',
                              'fp4','nvfp4','NVFP4','mxfp4')
    WHERE c.type_id = 15
    AND SPLIT_PART(c.name, ':', 2) = '${MODEL_NAME}'
    GROUP BY cp_vram.string_value
    LIMIT 1;
    " 2>/dev/null) || return 1

    CATALOG_VRAM=$(echo "$result"   | awk -F'|' '{print $1}' | xargs)
    CATALOG_PREC_TAGS=$(echo "$result" | awk -F'|' '{print $2}' | xargs)
    [ -n "$CATALOG_VRAM" ] || return 1
    return 0
}

# ── Path 2: HuggingFace API ───────────────────────────────────────────────────
HF_PARAMS_B="" HF_DTYPE_TAGS=""

_try_huggingface() {
    command -v curl &>/dev/null || return 1

    local api_url="https://huggingface.co/api/models/${MODEL_NAME}"
    local resp; resp=$(curl -sf --connect-timeout 5 "$api_url") || return 1

    # Try to get total parameter count from safetensors metadata
    local total_params; total_params=$(echo "$resp" | python3 -c "
import sys, json
d = json.load(sys.stdin)
st = d.get('safetensors', {})
total = st.get('total', 0)
if total: print(total)
" 2>/dev/null) || true

    if [ -n "$total_params" ] && [ "$total_params" -gt 0 ] 2>/dev/null; then
        HF_PARAMS_B=$(echo "scale=1; $total_params / 1000000000" | bc)

        # Extract dtype from safetensors.parameters keys
        local dtype_keys; dtype_keys=$(echo "$resp" | python3 -c "
import sys, json
d = json.load(sys.stdin)
keys = list(d.get('safetensors', {}).get('parameters', {}).keys())
print(','.join(keys))
" 2>/dev/null) || true
        HF_DTYPE_TAGS="$dtype_keys"
        return 0
    fi

    # Fallback: extract parameter count from model tags like '7B', '70B'
    local size_tag; size_tag=$(echo "$resp" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
tags = d.get('tags', []) + [d.get('modelId','')]
for t in tags:
    m = re.search(r'(\d+\.?\d*)[Bb]', str(t))
    if m:
        print(m.group(1))
        break
" 2>/dev/null) || true

    if [ -n "$size_tag" ]; then
        HF_PARAMS_B="$size_tag"
        return 0
    fi

    return 1
}

# ── Path 3: Name heuristics ───────────────────────────────────────────────────
_try_name_heuristics() {
    HF_PARAMS_B=$(_params_from_name "$MODEL_NAME")
    [ -n "$HF_PARAMS_B" ] || return 1
    return 0
}

# ── Main resolution logic ─────────────────────────────────────────────────────
echo -e "${BLUE}VRAM estimator${NC}"
echo -e "Model: ${CYAN}$MODEL_NAME${NC}"
echo ""

VRAM_GB="" VRAM_SOURCE="" PRECISION_STR="" PARAMS_B=""

# Try catalog first
if $VERBOSE; then echo "Checking internal catalog..."; fi
if _try_catalog 2>/dev/null; then
    VRAM_GB="$CATALOG_VRAM"
    VRAM_SOURCE="catalog (min_vram_gb field)"
    PRECISION_STR=$(_precision_from_tags "$CATALOG_PREC_TAGS")
    PARAMS_B=$(_params_from_name "$MODEL_NAME")
    if $VERBOSE; then
        echo -e "  ${GREEN}Found in catalog${NC} — VRAM stored directly: ${CATALOG_VRAM} GB"
        [ -n "$CATALOG_PREC_TAGS" ] && echo "  Precision tags: $CATALOG_PREC_TAGS"
        echo ""
    fi
else
    if $VERBOSE; then echo "  Not in catalog (or catalog unavailable), trying HuggingFace..."; fi

    if _try_huggingface 2>/dev/null; then
        PARAMS_B="$HF_PARAMS_B"
        PRECISION_STR=$(_precision_from_tags "${HF_DTYPE_TAGS:-$MODEL_NAME}")
        local_result=$(_calc_vram "$PARAMS_B" "$PRECISION_STR")
        VRAM_GB=$(echo "$local_result" | cut -d: -f1)
        VRAM_SOURCE="HuggingFace API"
        if $VERBOSE; then
            echo -e "  ${GREEN}Found via HuggingFace API${NC}"
            [ -n "$HF_DTYPE_TAGS" ] && echo "  Dtype: $HF_DTYPE_TAGS"
            echo ""
        fi
    elif _try_name_heuristics 2>/dev/null; then
        PARAMS_B="$HF_PARAMS_B"
        PRECISION_STR=$(_precision_from_tags "$MODEL_NAME")
        local_result=$(_calc_vram "$PARAMS_B" "$PRECISION_STR")
        VRAM_GB=$(echo "$local_result" | cut -d: -f1)
        VRAM_SOURCE="name heuristics"
        if $VERBOSE; then
            echo -e "  ${YELLOW}Using name heuristics (no API data available)${NC}"
            echo ""
        fi
    else
        echo -e "${RED}Cannot estimate VRAM automatically.${NC}"
        echo ""
        echo "Options:"
        echo "  1. Specify manually: $(basename "$0") \"$MODEL_NAME\" --vram <GB>"
        echo "  2. Check the model card on HuggingFace for parameter count, then:"
        echo "     $(basename "$0") \"$MODEL_NAME\" --vram <calculated-GB>"
        exit 1
    fi
fi

# --- If we calculated (not taken directly from catalog), recompute with full detail ---
if [ -z "$VRAM_GB" ] || [[ "$VRAM_SOURCE" != "catalog"* ]]; then
    if [ -n "$PARAMS_B" ]; then
        calc=$(_calc_vram "$PARAMS_B" "$PRECISION_STR")
        VRAM_GB=$(echo "$calc"    | cut -d: -f1)
        PREC=$(echo "$calc"       | cut -d: -f2)
        BASE=$(echo "$calc"       | cut -d: -f3)
        OVHD=$(echo "$calc"       | cut -d: -f4)

        if $VERBOSE; then
            _verbose_breakdown "$PARAMS_B" "$PREC" "$BASE" "$OVHD" "$VRAM_GB" "$VRAM_SOURCE"
        fi
    fi
fi

# --- Print result ---
echo -e "${GREEN}Required VRAM: ${VRAM_GB} GB${NC}"
echo -e "Source: $VRAM_SOURCE"
echo ""
echo -e "Pass to check-machines.sh:"
echo -e "  ${CYAN}./check-machines.sh cluster --vram $VRAM_GB${NC}"
echo -e "  ${CYAN}./check-machines.sh aws --vram $VRAM_GB${NC}"
echo ""
echo "VRAM_GB=$VRAM_GB"
