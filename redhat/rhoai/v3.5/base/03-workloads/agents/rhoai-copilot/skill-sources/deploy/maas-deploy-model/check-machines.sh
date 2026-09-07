#!/usr/bin/env bash
# Check GPU availability on the cluster, or get AWS instance recommendations.
# Fully model-agnostic — only needs a VRAM requirement in GB.
#
# Usage:
#   check-machines.sh cluster --vram <GB> [-v] [--cpu <cores>] [--memory <GiB>]
#   check-machines.sh aws     --vram <GB> [--top N]
#
# Typical workflow:
#   VRAM=$(./check-vram.sh "org/model" | grep ^VRAM_GB= | cut -d= -f2)
#   ./check-machines.sh cluster --vram "$VRAM" --cpu 4 --memory 20
#   # If nothing available:
#   ./check-machines.sh aws --vram "$VRAM" --top 5

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# instances.json lives in the model-deployment skill; reference it in-place
INSTANCES_JSON="${SCRIPT_DIR}/../model-deployment/instances.json"

# ── Argument parsing ──────────────────────────────────────────────────────────
SUBCOMMAND="${1:-}"
shift || true

VRAM_GB=""
TOP=5
VERBOSE=false
REQ_CPU_CORES=""   # optional: requested CPU cores for the deployment
REQ_MEM_GIB=""     # optional: requested memory in GiB for the deployment

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vram)    VRAM_GB="$2";       shift 2 ;;
        --top)     TOP="$2";           shift 2 ;;
        --cpu)     REQ_CPU_CORES="$2"; shift 2 ;;
        --memory)  REQ_MEM_GIB="$2";   shift 2 ;;
        -v|--verbose) VERBOSE=true;    shift ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
    esac
done

_require_vram() {
    if [ -z "$VRAM_GB" ]; then
        echo -e "${RED}Error: --vram <GB> is required${NC}" >&2
        echo "Get it from: ./check-vram.sh <model>" >&2
        exit 1
    fi
}

# ── Cluster GPU check ─────────────────────────────────────────────────────────
cmd_cluster() {
    _require_vram

    local BUFFER=0.85
    local REQUIRED_WITH_BUFFER; REQUIRED_WITH_BUFFER=$(echo "scale=2; $VRAM_GB / $BUFFER" | bc)

    echo -e "${BLUE}Cluster GPU Availability${NC}"
    echo -e "Required VRAM: ${CYAN}${VRAM_GB} GB${NC}  (checking nodes with ≥${VRAM_GB} GB usable after 15% buffer)"
    echo ""

    # ── Phase 1: Discover GPU nodes (single oc call, filter client-side) ──────
    echo "Phase 1: Discovering GPU nodes..."
    local all_nodes_json
    all_nodes_json=$(oc get nodes -o json 2>/dev/null) || {
        echo -e "${RED}Failed to query cluster nodes${NC}" >&2; exit 1
    }

    # jq helpers: parse Kubernetes CPU (e.g. "7800m", "8") → millicores
    #             parse Kubernetes memory (e.g. "32614912Ki", "20Gi") → MiB
    local JQ_HELPERS='
        def parse_cpu:
          if . == null then 0
          elif test("m$") then (.[:-1] | tonumber)
          else (tonumber * 1000)
          end;
        def parse_mem_mi:
          if . == null then 0
          elif test("Ki$") then (.[:-2] | tonumber / 1024)
          elif test("Mi$") then (.[:-2] | tonumber)
          elif test("Gi$") then (.[:-2] | tonumber * 1024)
          elif test("Ti$") then (.[:-2] | tonumber * 1024 * 1024)
          elif test("K$")  then (.[:-1] | tonumber / 1024)
          elif test("M$")  then (.[:-1] | tonumber)
          elif test("G$")  then (.[:-1] | tonumber * 1024)
          else (tonumber / 1048576)
          end;
    '

    NVIDIA_NODES=$(echo "$all_nodes_json" | jq -c "$JQ_HELPERS"'
        .items[] |
        select((.status.capacity["nvidia.com/gpu"] | tonumber? // 0) > 0) |
        {
            name:               .metadata.name,
            gpu_count:          (.status.capacity["nvidia.com/gpu"] | tonumber),
            allocatable:        (.status.allocatable["nvidia.com/gpu"] | tonumber),
            gpu_memory_mib:     (.metadata.labels["nvidia.com/gpu.memory"]  // "0"),
            gpu_product:        (.metadata.labels["nvidia.com/gpu.product"] // "unknown"),
            cpu_alloc_m:        (.status.allocatable.cpu    | parse_cpu),
            mem_alloc_mi:       (.status.allocatable.memory | parse_mem_mi)
        }') || NVIDIA_NODES=""

    AMD_NODES=$(echo "$all_nodes_json" | jq -c "$JQ_HELPERS"'
        .items[] |
        select((.status.capacity["amd.com/gpu"] | tonumber? // 0) > 0) |
        {
            name:               .metadata.name,
            gpu_count:          (.status.capacity["amd.com/gpu"] | tonumber),
            allocatable:        (.status.allocatable["amd.com/gpu"] | tonumber),
            gpu_memory_mib:     (.metadata.labels["amd.com/gpu.memory"]  // "0"),
            gpu_product:        (.metadata.labels["amd.com/gpu.product"] // "unknown"),
            cpu_alloc_m:        (.status.allocatable.cpu    | parse_cpu),
            mem_alloc_mi:       (.status.allocatable.memory | parse_mem_mi)
        }') || AMD_NODES=""

    if [ -z "$NVIDIA_NODES" ] && [ -z "$AMD_NODES" ]; then
        echo -e "${RED}No GPU nodes found in the cluster.${NC}"
        echo ""
        echo "Try: ./check-machines.sh aws --vram $VRAM_GB"
        exit 1
    fi

    local nvidia_count=0 amd_count=0
    [ -n "$NVIDIA_NODES" ] && nvidia_count=$(echo "$NVIDIA_NODES" | wc -l | tr -d ' ')
    [ -n "$AMD_NODES" ]    && amd_count=$(echo "$AMD_NODES"    | wc -l | tr -d ' ')
    echo "Found ${nvidia_count} NVIDIA + ${amd_count} AMD GPU node(s)."
    echo ""

    # ── Phase 2: Query pod resource usage across all namespaces (single oc call) ─
    echo "Phase 2: Checking GPU pod usage..."
    local JQ_POD_HELPERS='
        def parse_cpu:
          if . == null then 0
          elif test("m$") then (.[:-1] | tonumber)
          else (tonumber * 1000)
          end;
        def parse_mem_mi:
          if . == null then 0
          elif test("Ki$") then (.[:-2] | tonumber / 1024)
          elif test("Mi$") then (.[:-2] | tonumber)
          elif test("Gi$") then (.[:-2] | tonumber * 1024)
          elif test("Ti$") then (.[:-2] | tonumber * 1024 * 1024)
          elif test("K$")  then (.[:-1] | tonumber / 1024)
          elif test("M$")  then (.[:-1] | tonumber)
          elif test("G$")  then (.[:-1] | tonumber * 1024)
          else (tonumber / 1048576)
          end;
    '
    # Output per pod: node|nvidia|amd|cpu_m|mem_mi  (for all Running pods on GPU nodes)
    ALL_PODS_USAGE=$(oc get pods --all-namespaces -o json 2>/dev/null | jq -r "$JQ_POD_HELPERS"'
        .items[] |
        select(.spec.nodeName != null and .status.phase == "Running") |
        {
            node:    .spec.nodeName,
            nvidia:  ([.spec.containers[]?.resources.requests["nvidia.com/gpu"]? // "0" | tonumber? // 0] | add // 0),
            amd:     ([.spec.containers[]?.resources.requests["amd.com/gpu"]?   // "0" | tonumber? // 0] | add // 0),
            cpu_m:   ([.spec.containers[]?.resources.requests.cpu?    // "0" | parse_cpu]    | add // 0),
            mem_mi:  ([.spec.containers[]?.resources.requests.memory? // "0" | parse_mem_mi] | add // 0)
        } |
        "\(.node)|\(.nvidia)|\(.amd)|\(.cpu_m)|\(.mem_mi)"') || ALL_PODS_USAGE=""
    # Backwards-compat alias for GPU-only filtering used below
    GPU_USAGE=$(echo "$ALL_PODS_USAGE" | awk -F'|' '($2+0)>0 || ($3+0)>0')
    echo ""

    # ── Phase 3: Check each GPU node for free capacity ────────────────────────
    CAN_DEPLOY=false INSUFFICIENT_MEM=false RESOURCE_WARN=false

    # Convert requested resources to comparable units
    local REQ_CPU_M=0 REQ_MEM_MI=0
    if [ -n "$REQ_CPU_CORES" ]; then
        REQ_CPU_M=$(echo "$REQ_CPU_CORES * 1000" | bc | cut -d. -f1)
    fi
    if [ -n "$REQ_MEM_GIB" ]; then
        REQ_MEM_MI=$(echo "$REQ_MEM_GIB * 1024" | bc | cut -d. -f1)
    fi

    _check_node_type() {
        local VENDOR="$1"; local NODES="$2"; local COL="$3"  # COL=2 nvidia, COL=3 amd

        while IFS= read -r node; do
            [ -z "$node" ] && continue
            local NAME; NAME=$(echo "$node" | jq -r '.name')
            local ALLOC; ALLOC=$(echo "$node" | jq -r '.allocatable')
            local MEM_MIB; MEM_MIB=$(echo "$node" | jq -r '.gpu_memory_mib')
            local PRODUCT; PRODUCT=$(echo "$node" | jq -r '.gpu_product')
            local CPU_ALLOC_M; CPU_ALLOC_M=$(echo "$node" | jq -r '.cpu_alloc_m | floor')
            local MEM_ALLOC_MI; MEM_ALLOC_MI=$(echo "$node" | jq -r '.mem_alloc_mi | floor')

            local USED=0
            local USED_CPU_M=0 USED_MEM_MI=0
            if [ -n "$ALL_PODS_USAGE" ]; then
                USED=$(echo "$ALL_PODS_USAGE" | awk -F'|' -v name="$NAME" -v col="$COL" 'BEGIN{s=0} $1==name{s+=$col} END{print s}')
                USED_CPU_M=$(echo "$ALL_PODS_USAGE" | awk -F'|' -v name="$NAME" 'BEGIN{s=0} $1==name{s+=$4} END{printf "%d", s}')
                USED_MEM_MI=$(echo "$ALL_PODS_USAGE" | awk -F'|' -v name="$NAME" 'BEGIN{s=0} $1==name{s+=$5} END{printf "%d", s}')
            fi

            local FREE=$(( ALLOC - USED ))
            local FREE_CPU_M=$(( CPU_ALLOC_M - USED_CPU_M ))
            local FREE_MEM_MI=$(( MEM_ALLOC_MI - USED_MEM_MI ))
            local FREE_CPU_CORES; FREE_CPU_CORES=$(echo "scale=1; $FREE_CPU_M / 1000" | bc)
            local FREE_MEM_GIB; FREE_MEM_GIB=$(echo "scale=1; $FREE_MEM_MI / 1024" | bc)
            local TOT_CPU_CORES; TOT_CPU_CORES=$(echo "scale=1; $CPU_ALLOC_M / 1000" | bc)
            local TOT_MEM_GIB; TOT_MEM_GIB=$(echo "scale=1; $MEM_ALLOC_MI / 1024" | bc)

            local MEM_GB=0
            if [[ "$MEM_MIB" =~ ([0-9]+) ]]; then
                MEM_GB=$(( ${BASH_REMATCH[1]} / 1024 ))
            fi

            local USABLE; USABLE=$(echo "scale=1; $MEM_GB * $BUFFER" | bc)
            local CAN_FIT=0
            [ "$MEM_GB" -gt 0 ] && CAN_FIT=$(echo "$USABLE >= $VRAM_GB" | bc)

            # Check if requested CPU/memory fit on this node
            local CPU_OK=true MEM_OK=true
            local CPU_WARN="" MEM_WARN=""
            if [ -n "$REQ_CPU_CORES" ] && [ "$FREE_CPU_M" -lt "$REQ_CPU_M" ]; then
                CPU_OK=false
                local AVAIL_CORES; AVAIL_CORES=$(echo "scale=1; $FREE_CPU_M / 1000" | bc)
                CPU_WARN="  ${RED}  ✗ CPU:    ${FREE_CPU_CORES} cores free (${TOT_CPU_CORES} allocatable) — need ${REQ_CPU_CORES} cores${NC}"
            fi
            if [ -n "$REQ_MEM_GIB" ] && [ "$FREE_MEM_MI" -lt "$REQ_MEM_MI" ]; then
                MEM_OK=false
                MEM_WARN="  ${RED}  ✗ Memory: ${FREE_MEM_GIB} GiB free (${TOT_MEM_GIB} GiB allocatable) — need ${REQ_MEM_GIB} GiB${NC}"
            fi

            if [ "$FREE" -gt 0 ] && [ "$CAN_FIT" -eq 1 ]; then
                if $CPU_OK && $MEM_OK; then
                    echo -e "${GREEN}  ✓ $VENDOR: $NAME${NC}"
                    CAN_DEPLOY=true
                else
                    echo -e "${YELLOW}  ~ $VENDOR: $NAME${NC}  — GPU free but insufficient CPU/memory for deployment"
                    RESOURCE_WARN=true
                fi
                echo "    Free GPUs:  $FREE  (${USED}/${ALLOC} in use)"
                echo "    GPU Memory: ${MEM_GB} GB total  →  ${USABLE} GB usable (15% buffer)"
                echo "    Product:    $PRODUCT"
                echo "    CPU:        ${FREE_CPU_CORES} cores free  /  ${TOT_CPU_CORES} allocatable"
                echo "    Memory:     ${FREE_MEM_GIB} GiB free  /  ${TOT_MEM_GIB} GiB allocatable"
                [ -n "$CPU_WARN" ] && echo -e "$CPU_WARN"
                [ -n "$MEM_WARN" ] && echo -e "$MEM_WARN"
            elif [ "$FREE" -gt 0 ]; then
                echo -e "${YELLOW}  ~ $VENDOR: $NAME${NC}  — free GPUs but insufficient GPU memory"
                if $VERBOSE; then
                    echo "    Free GPUs:  $FREE  (${USED}/${ALLOC} in use)"
                    echo "    GPU Memory: ${MEM_GB} GB total  →  ${USABLE} GB usable  (need ${VRAM_GB} GB)"
                    echo "    Product:    $PRODUCT"
                    echo "    CPU:        ${FREE_CPU_CORES} cores free  /  ${TOT_CPU_CORES} allocatable"
                    echo "    Memory:     ${FREE_MEM_GIB} GiB free  /  ${TOT_MEM_GIB} GiB allocatable"
                fi
                INSUFFICIENT_MEM=true
            else
                echo -e "${RED}  ✗ $VENDOR: $NAME${NC}  — all GPUs in use (${USED}/${ALLOC})"
                if $VERBOSE; then
                    echo "    GPU Memory: ${MEM_GB} GB  |  Product: $PRODUCT"
                    echo "    CPU:        ${FREE_CPU_CORES} cores free  /  ${TOT_CPU_CORES} allocatable"
                    echo "    Memory:     ${FREE_MEM_GIB} GiB free  /  ${TOT_MEM_GIB} GiB allocatable"
                fi
            fi
        done <<< "$NODES"
    }

    [ -n "$NVIDIA_NODES" ] && echo -e "${CYAN}NVIDIA nodes:${NC}" && _check_node_type "NVIDIA" "$NVIDIA_NODES" 2
    [ -n "$AMD_NODES" ]    && echo -e "${CYAN}AMD nodes:${NC}"    && _check_node_type "AMD"    "$AMD_NODES"    3

    echo ""
    echo "────────────────────────────────────────"
    if $CAN_DEPLOY; then
        echo -e "${GREEN}RESULT: Cluster has capacity — deployment can proceed.${NC}"
        exit 0
    elif $RESOURCE_WARN; then
        echo -e "${YELLOW}RESULT: GPU is free but node lacks CPU or memory for the requested deployment.${NC}"
        echo ""
        echo "Options:"
        if [ -n "$REQ_CPU_CORES" ]; then
            echo "  - Reduce --cpu below the free cores shown above"
        fi
        if [ -n "$REQ_MEM_GIB" ]; then
            echo "  - Reduce --memory below the free GiB shown above"
        fi
        echo "  - Provision a larger AWS instance: ./check-machines.sh aws --vram $VRAM_GB"
        exit 1
    elif $INSUFFICIENT_MEM; then
        echo -e "${RED}RESULT: Nodes are free but no GPU has enough memory for ${VRAM_GB} GB.${NC}"
        echo ""
        echo "Options:"
        echo "  - Use a quantized model variant (FP8 / INT4) to reduce VRAM"
        echo "  - Provision an AWS instance: ./check-machines.sh aws --vram $VRAM_GB"
        exit 1
    else
        echo -e "${RED}RESULT: All GPU nodes are fully occupied.${NC}"
        echo ""
        echo "  - Wait for a node to free up, or"
        echo "  - Provision an AWS instance: ./check-machines.sh aws --vram $VRAM_GB"
        exit 1
    fi
}

# ── AWS instance recommendations ───────────────────────────────────────────────
cmd_aws() {
    _require_vram

    if [ ! -f "$INSTANCES_JSON" ]; then
        echo -e "${RED}Error: instances.json not found at:${NC}" >&2
        echo "  $INSTANCES_JSON" >&2
        echo "Run: ~/.claude/skills/model-deployment/refresh-aws-instances.sh" >&2
        exit 1
    fi

    local BUFFER_FACTOR=1.15  # add 15% safety margin to required VRAM
    local REQUIRED; REQUIRED=$(echo "scale=2; $VRAM_GB * $BUFFER_FACTOR" | bc)

    echo -e "${BLUE}AWS Instance Recommendations${NC}"
    echo -e "Required VRAM: ${CYAN}${VRAM_GB} GB${NC}  →  ${REQUIRED} GB with 15% safety buffer"
    echo ""

    INSTANCES=$(jq -r --arg req "$REQUIRED" '
    .[] |
    select(.gpu_memory_gb != null and .gpu_memory_gb > 0 and .gpu_count > 0) |
    select(.instance_type | endswith(".metal") | not) |
    {
        instance:              .instance_type,
        gpu_name:              .gpu_name,
        gpu_count:             .gpu_count,
        total_vram_gb:         .gpu_memory_gb,
        single_vram_gb:       (.gpu_memory_gb / .gpu_count),
        vcpus:                 .vcpus,
        memory_gb:             .memory_gb
    } |
    select(.total_vram_gb >= ($req | tonumber)) |
    . + {
        fits_single: (.single_vram_gb >= ($req | tonumber)),
        mem_ratio:   (.total_vram_gb  / ($req | tonumber)),
        ram_ratio:   (.memory_gb      / .total_vram_gb)
    } |
    . + {
        score: (
            (if .mem_ratio >= 1.2 and .mem_ratio <= 1.5 then 100
             elif .mem_ratio < 2.0 then 70
             else (50 - ((.mem_ratio - 2) * 10)) end)
            + (if .fits_single then 50 else 0 end)
            + (if .fits_single and .gpu_count > 1 then -30 else 0 end)
            + (if .ram_ratio <= 4 then 20 elif .ram_ratio <= 8 then 10 elif .ram_ratio <= 12 then 0
               else (0 - ((.ram_ratio - 12) * 2)) end)
            + (if .vcpus <= 8 then 30 elif .vcpus <= 16 then 20 elif .vcpus <= 32 then 0
               else (0 - ((.vcpus - 32) / 4)) end)
        )
    }
    ' "$INSTANCES_JSON" | jq -s 'sort_by(-.score)')

    if [ -z "$INSTANCES" ] || [ "$INSTANCES" == "[]" ]; then
        echo -e "${RED}No AWS instances found with enough VRAM (${REQUIRED} GB).${NC}"
        echo "Consider a more quantized model variant to reduce VRAM requirement."
        exit 1
    fi

    local TOTAL; TOTAL=$(echo "$INSTANCES" | jq 'length')

    # Top recommendation
    TOP=$(echo "$INSTANCES" | jq -r 'sort_by([-.score, .memory_gb]) | .[0]')
    echo -e "${GREEN}RECOMMENDED (best fit):${NC}"
    echo "$TOP" | jq -r '"
  Instance:     \(.instance)
  GPU:          \(.gpu_count)x \(.gpu_name)
  GPU Memory:   \(.single_vram_gb | floor) GB per GPU  (\(.total_vram_gb | floor) GB total)
  vCPUs:        \(.vcpus)
  System RAM:   \(.memory_gb | floor) GB
  Deployment:   \(if .fits_single then "Single GPU" else "Tensor Parallelism (\(.gpu_count) GPUs)" end)
  Headroom:     +\((.mem_ratio * 100 - 100) | floor)% above requirement
  Score:        \(.score | floor) / 100
"'

    # Summary table
    local SHOW; SHOW=$(echo "$INSTANCES" | jq --argjson top "$TOP" 'length')
    local DISPLAY=$(( TOP < SHOW ? TOP : SHOW ))
    DISPLAY=$TOP

    echo -e "${CYAN}Top ${TOP} instances by score:${NC}"
    echo "──────────────────────────────────────────────────────────────────────────"
    printf "%-18s %-22s %-18s %-8s %-10s %s\n" "Instance" "GPU" "VRAM (per/total)" "vCPUs" "RAM" "Score"
    echo "──────────────────────────────────────────────────────────────────────────"

    echo "$INSTANCES" | jq -r --argjson top "$TOP" '
    sort_by([-.score, .memory_gb]) | .[:$top] | .[] |
    "\(.instance)\t\(.gpu_count)x \(.gpu_name)\t\(.single_vram_gb | floor)\t\(.total_vram_gb | floor)\t\(.vcpus)\t\(.memory_gb | floor)GB\t\(.score | floor)"
    ' | while IFS=$'\t' read -r inst gpu sv tv vcpu ram score; do
        printf "%-18s %-22s %-18s %-8s %-10s %s\n" \
            "$inst" "$gpu" "$(printf '%3s GB / %s GB' "$sv" "$tv")" "$vcpu" "$ram" "$score"
    done

    echo ""
    echo -e "${GREEN}Showing $TOP of $TOTAL matching instances${NC}"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <subcommand> --vram <GB> [options]

Subcommands:
  cluster --vram <GB> [-v] [--cpu <cores>] [--memory <GiB>]
                                    Check live GPU node availability on the cluster
  aws     --vram <GB> [--top N]     Recommend AWS instances (default: top 5)

Options:
  --vram <GB>      Minimum VRAM required (output of check-vram.sh)
  --cpu  <cores>   CPU cores your deployment will request (validates fit on node)
  --memory <GiB>   System memory your deployment will request in GiB (validates fit)
  --top  N         Number of AWS instances to show (aws subcommand only)
  -v               Verbose: show all node details including unavailable ones

Examples:
  $(basename "$0") cluster --vram 18
  $(basename "$0") cluster --vram 18 --cpu 4 --memory 20
  $(basename "$0") cluster --vram 18 -v
  $(basename "$0") aws --vram 18 --top 10

Typical workflow:
  VRAM=\$(./check-vram.sh "meta-llama/Llama-3.1-8B-Instruct" | grep ^VRAM_GB= | cut -d= -f2)
  ./check-machines.sh cluster --vram "\$VRAM" --cpu 4 --memory 20
EOF
    exit 1
}

case "$SUBCOMMAND" in
    cluster) cmd_cluster ;;
    aws)     cmd_aws ;;
    *) usage ;;
esac
