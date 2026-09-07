#!/usr/bin/env bash
# Deploy a model to MaaS via LLMInferenceService (serving.kserve.io/v1alpha2).
#
# Deployment modes (--deploy-mode):
#   vllm   — Creates a local LLMInferenceServiceConfig (cloned from the single-node vLLM template)
#            and references it in spec.baseRefs. Matches the pattern of currently running models
#            single-node template. This is the default.
#   llm-d  — Clones a user-selected global LLMInferenceServiceConfig (e.g. multi-node PD split)
#            into the model namespace and references it. Use for advanced llm-d scheduling.

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

TEMPLATES_NAMESPACE="redhat-ods-applications"
DEFAULT_REPLICAS=1
DEFAULT_TIMEOUT=600
DEFAULT_GATEWAY_NAME="maas-default-gateway"
DEFAULT_GATEWAY_NAMESPACE="openshift-ingress"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy a model to MaaS via LLMInferenceService. Both modes create a local
LLMInferenceServiceConfig in the model namespace and reference it via spec.baseRefs.

Deployment modes (--deploy-mode):
  vllm   [default]  Creates a local LLMInferenceServiceConfig from the single-node vLLM
                    template (auto-selected by GPU type).
  llm-d             Clones a selected global LLMInferenceServiceConfig from $TEMPLATES_NAMESPACE
                    into the model namespace. Use for multi-node / prefill-decode split.

Required:
  --name, -n        <name>          Deployment name (Kubernetes-safe)
  --namespace, -ns  <namespace>     Target namespace

Storage (at least one):
  --storage-uri, -s <uri>           Model URI (oci://, hf://, s3://)
                                    Or a catalog model name — OCI URI auto-extracted
  --clone-from, -c  <ns/name>       Clone from existing LLMInferenceService

Optional:
  --deploy-mode     <mode>          vllm (default) or llm-d — prompted interactively if omitted
  --cpu             <N[/limit]>     CPU request[/limit]  (e.g. "2" or "2/4")
  --memory          <SIZE[/limit]>  Memory request[/limit] (e.g. "16Gi")
  --gpu             <N[/type=N]>    GPU count (e.g. "1" or "nvidia.com/gpu=2")
  --replicas        <N>             Replica count (default: $DEFAULT_REPLICAS)
  --timeout         <seconds>       Wait timeout (default: $DEFAULT_TIMEOUT)
  --request-timeout <seconds>       HTTPRoute request timeout in seconds (0 = no timeout; default: 0)
                                    Applied to all gateway routes for this model. Can also be changed
                                    later with set-timeout.sh.
  --args            <arg,arg,...>   vLLM flags (comma-separated, set as VLLM_ADDITIONAL_ARGS)
  --env             <K=V,K=V,...>   Extra env vars
  --display-name    <text>          Display name annotation
  --description     <text>          Description annotation
  --hardware-profile <name>         Use this existing hardware profile instead of auto-creating one
  --hw-profile-preset <preset>      Preset for the auto-created profile (small-gpu|medium-gpu|large-gpu|cpu-only)
  --llm-config      <name>          Skip LLMInferenceServiceConfig creation — use this existing local config
  --gateway-name    <name>          MaaS gateway name (default: $DEFAULT_GATEWAY_NAME)
  --gateway-ns      <namespace>     MaaS gateway namespace (default: $DEFAULT_GATEWAY_NAMESPACE)
  --config-file, -f <file>          Load params from YAML file
  --dry-run                         Print manifests without applying
  --output, -o      <file>          Write manifests to file instead of applying
  --no-wait                         Don't wait for deployment to become ready
  --wait-timeout    <seconds>       Override default wait timeout

Examples:
  # vLLM mode (default)
  $(basename "$0") -n <name> -ns <model-namespace> -s "<org/model-name>" --gpu <N> --cpu <N> --memory <NNGi>
  # llm-d mode — advanced scheduling
  $(basename "$0") -n <name> -ns <model-namespace> --deploy-mode llm-d -s "<org/model-name>" --gpu <N> --cpu <N> --memory <NNGi>
  $(basename "$0") --clone-from <model-namespace>/<existing-model> -n <name> --dry-run
EOF
    exit 1
}

# ── OCI URI extraction from model catalog (same as deploy-kserve-model.sh) ───
extract_oci_uri_from_catalog() {
    local model_name="$1"
    log_info "Extracting OCI URI from catalog for: $model_name"

    local CATALOG_NS="rhoai-model-registries"
    local POD_NAME; POD_NAME=$(oc get pods -n "$CATALOG_NS" -o name 2>/dev/null \
        | grep model-catalog-postgres | cut -d'/' -f2)

    if [ -z "$POD_NAME" ]; then
        log_warning "Model catalog pod not found, falling back to hf:// URI"
        echo "hf://${model_name}"
        return
    fi

    local DB_USER DB_NAME
    DB_USER=$(oc get secret model-catalog-postgres -n "$CATALOG_NS" -o yaml 2>/dev/null \
        | yq '.data.database-user' | base64 -d)
    DB_NAME=$(oc get secret model-catalog-postgres -n "$CATALOG_NS" -o yaml 2>/dev/null \
        | yq '.data.database-name' | base64 -d)

    if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
        log_warning "Failed to get catalog DB credentials, falling back to hf:// URI"
        echo "hf://${model_name}"
        return
    fi

    local OCI_URI
    OCI_URI=$(oc exec -n "$CATALOG_NS" "$POD_NAME" -- \
        psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT a.uri
        FROM \"Artifact\" a
        JOIN \"Attribution\" attr ON a.id = attr.artifact_id
        JOIN \"Context\" c ON attr.context_id = c.id
        WHERE c.type_id = 15
        AND SPLIT_PART(c.name, ':', 2) = '${model_name}'
        AND a.uri LIKE 'oci://%'
        LIMIT 1;
    " 2>/dev/null | tr -d '[:space:]')

    if [ -z "$OCI_URI" ]; then
        log_warning "OCI URI not found in catalog for $model_name, falling back to hf:// URI"
        echo "hf://${model_name}"
        return
    fi

    log_success "Found OCI URI: $OCI_URI"
    echo "$OCI_URI"
}

# ── Clone from existing LLMInferenceService ───────────────────────────────────
clone_from_existing() {
    local clone_ref="$1"
    local clone_ns; clone_ns=$(echo "$clone_ref" | cut -d'/' -f1)
    local clone_name; clone_name=$(echo "$clone_ref" | cut -d'/' -f2)

    log_info "Cloning from: $clone_ns/$clone_name"

    local isvc
    isvc=$(oc get llminferenceservice "$clone_name" -n "$clone_ns" -o json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$isvc" ]; then
        log_error "LLMInferenceService not found: $clone_ns/$clone_name"
        exit 1
    fi

    STORAGE_URI=${STORAGE_URI:-$(echo "$isvc" | jq -r '.spec.model.uri // empty')}
    MIN_REPLICAS=${MIN_REPLICAS:-$(echo "$isvc" | jq -r '.spec.replicas // 1')}

    # Resources from spec.template.containers[0]
    if [ -z "$CPU" ]; then
        local cpu_req; cpu_req=$(echo "$isvc" | jq -r '.spec.template.containers[0].resources.requests.cpu // empty')
        local cpu_lim; cpu_lim=$(echo "$isvc" | jq -r '.spec.template.containers[0].resources.limits.cpu // empty')
        [ -n "$cpu_req" ] && CPU="$cpu_req"
        [ -n "$cpu_lim" ] && [ "$cpu_lim" != "$cpu_req" ] && CPU="$cpu_req/$cpu_lim"
    fi
    if [ -z "$MEMORY" ]; then
        local mem_req; mem_req=$(echo "$isvc" | jq -r '.spec.template.containers[0].resources.requests.memory // empty')
        local mem_lim; mem_lim=$(echo "$isvc" | jq -r '.spec.template.containers[0].resources.limits.memory // empty')
        [ -n "$mem_req" ] && MEMORY="$mem_req"
        [ -n "$mem_lim" ] && [ "$mem_lim" != "$mem_req" ] && MEMORY="$mem_req/$mem_lim"
    fi
    if [ -z "$GPU" ]; then
        local gpu_req; gpu_req=$(echo "$isvc" | jq -r '.spec.template.containers[0].resources.requests."nvidia.com/gpu" // empty')
        [ -n "$gpu_req" ] && GPU="$gpu_req"
    fi

    # VLLM_ADDITIONAL_ARGS from env
    if [ -z "$MODEL_ARGS" ]; then
        MODEL_ARGS=$(echo "$isvc" | jq -r '
            .spec.template.containers[0].env[]?
            | select(.name == "VLLM_ADDITIONAL_ARGS") | .value // empty')
        # Convert space-separated back to comma-separated for internal use
        [ -n "$MODEL_ARGS" ] && MODEL_ARGS=$(echo "$MODEL_ARGS" | tr ' ' ',')
    fi

    # Extra env vars (exclude VLLM_NO_USAGE_STATS and VLLM_ADDITIONAL_ARGS, we re-add those)
    if [ -z "$ENV_VARS" ]; then
        ENV_VARS=$(echo "$isvc" | jq -r '
            [.spec.template.containers[0].env[]?
             | select(.name != "VLLM_NO_USAGE_STATS" and .name != "VLLM_ADDITIONAL_ARGS")
             | "\(.name)=\(.value)"]
            | join(",")' | sed 's/^,//')
    fi

    HARDWARE_PROFILE=${HARDWARE_PROFILE:-$(echo "$isvc" | \
        jq -r '.metadata.annotations."opendatahub.io/hardware-profile-name" // empty')}
    DISPLAY_NAME=${DISPLAY_NAME:-$(echo "$isvc" | \
        jq -r '.metadata.annotations."openshift.io/display-name" // empty')}
    DESCRIPTION=${DESCRIPTION:-$(echo "$isvc" | \
        jq -r '.metadata.annotations."openshift.io/description" // empty')}
    GATEWAY_NAME=${GATEWAY_NAME:-$(echo "$isvc" | \
        jq -r '.spec.router.gateway.refs[0].name // "maas-default-gateway"')}
    GATEWAY_NAMESPACE=${GATEWAY_NAMESPACE:-$(echo "$isvc" | \
        jq -r '.spec.router.gateway.refs[0].namespace // "openshift-ingress"')}

    log_success "Cloned from $clone_ns/$clone_name"
}

# ── Config file loading (same keys as deploy-kserve-model.sh) ─────────────────
load_config_file() {
    local config_file="$1"
    [ -f "$config_file" ] || { log_error "Config file not found: $config_file"; exit 1; }
    log_info "Loading config from: $config_file"

    if command -v yq &>/dev/null; then
        NAME=${NAME:-$(yq eval '.name // ""' "$config_file")}
        NAMESPACE=${NAMESPACE:-$(yq eval '.namespace // ""' "$config_file")}
        STORAGE_URI=${STORAGE_URI:-$(yq eval '.storageUri // ""' "$config_file")}
        CPU=${CPU:-$(yq eval '.resources.cpu // ""' "$config_file")}
        MEMORY=${MEMORY:-$(yq eval '.resources.memory // ""' "$config_file")}
        GPU=${GPU:-$(yq eval '.resources.gpu // ""' "$config_file")}
        MIN_REPLICAS=${MIN_REPLICAS:-$(yq eval '.replicas // ""' "$config_file")}
        MODEL_ARGS=${MODEL_ARGS:-$(yq eval '.args // [] | join(",")' "$config_file")}
        ENV_VARS=${ENV_VARS:-$(yq eval \
            '.env // {} | to_entries | map(.key + "=" + .value) | join(",")' "$config_file")}
    else
        log_warning "yq not available — using grep-based parsing"
        NAME=${NAME:-$(grep "^name:" "$config_file" | awk '{print $2}')}
        NAMESPACE=${NAMESPACE:-$(grep "^namespace:" "$config_file" | awk '{print $2}')}
        STORAGE_URI=${STORAGE_URI:-$(grep "^storageUri:" "$config_file" | awk '{print $2}')}
    fi
}

# ── LLMInferenceServiceConfig picker for llm-d mode ──────────────────────────
# Shows only "user-facing" configs (those with a display-name + topology annotation).
# Derives a recommendation from GPU type, count, and replica count, explains why,
# lists all other options, then waits for user confirmation or a different choice.
detect_llm_config() {
    local gpu_type="$1"
    local replicas="$2"
    local gpu_count="${GPU_COUNT:-1}"

    # Filter to user-facing configs only (have both display-name and supported-topologies)
    local all_configs
    all_configs=$(oc get llminferenceserviceconfig -n "$TEMPLATES_NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[]
            | select(
                (.metadata.annotations."openshift.io/display-name"       // "" | length > 0) and
                (.metadata.annotations."opendatahub.io/supported-topologies" // "" | length > 0)
              )
            | .metadata.name' | sort) || all_configs=""

    if [ -z "$all_configs" ]; then
        log_warning "No user-facing LLMInferenceServiceConfig found in $TEMPLATES_NAMESPACE" >&2
        echo ""
        return
    fi

    # ── Recommendation logic ──────────────────────────────────────────────────
    local recommended="" reason=""
    local is_multi=false
    { [ "${replicas:-1}" -gt 1 ] 2>/dev/null && is_multi=true; } || true

    case "$gpu_type" in
        nvidia.com/gpu)
            if $is_multi; then
                recommended=$(resolve_template "kserve-config-llm-multi-node-pd-template-nvidia-cuda")
                reason="${replicas} replicas across nodes → multi-node with prefill/decode split gives best throughput"
            elif [ "${gpu_count:-1}" -gt 1 ] 2>/dev/null; then
                recommended=$(resolve_template "kserve-config-llm-single-node-pd-template-nvidia-cuda")
                reason="${gpu_count} GPUs on one node → single-node prefill/decode split maximises GPU utilisation"
            else
                recommended=$(resolve_template "kserve-config-llm-single-node-template-nvidia-cuda")
                reason="1 GPU × 1 replica → single-node vLLM (simplest, same pattern as running models)"
            fi
            ;;
        amd.com/gpu)
            recommended=$(resolve_template "kserve-config-llm-template-amd-rocm")
            reason="AMD GPU detected → ROCm template"
            ;;
        habana.ai/gaudi*)
            recommended=$(resolve_template "kserve-config-llm-template-intel-gaudi")
            reason="Intel Gaudi accelerator detected"
            ;;
        ibm.com/spyre*)
            recommended=$(resolve_template "kserve-config-llm-template-ibm-spyre-ppc64le")
            reason="IBM Spyre accelerator detected (ppc64le variant)"
            ;;
        *)
            recommended=$(resolve_template "kserve-config-llm-single-node-template-nvidia-cuda")
            reason="Unrecognised GPU type (${gpu_type:-none}) — defaulting to NVIDIA CUDA single-node"
            ;;
    esac

    # If recommended does not exist in the fetched list, fall back to first
    if ! echo "$all_configs" | grep -q "^${recommended}$"; then
        recommended=$(echo "$all_configs" | head -1)
        reason="${reason} [adjusted — template not available, using first match]"
    fi

    # Non-TTY (CI/piped): auto-select without prompting
    if [ ! -t 0 ] && [ ! -t 2 ]; then
        echo "$recommended"
        return
    fi

    # ── Interactive display ───────────────────────────────────────────────────
    echo "" >&2
    echo -e "${CYAN}━━━ llm-d: select LLMInferenceServiceConfig ━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo -e "  Context:  GPU=${YELLOW}${gpu_type:-nvidia.com/gpu}${NC} ×${YELLOW}${gpu_count}${NC}, replicas=${YELLOW}${replicas:-1}${NC}" >&2
    echo "" >&2

    local i=1
    local -a configs_arr

    # Recommended always listed first
    configs_arr+=("$recommended")
    local disp
    disp=$(oc get llminferenceserviceconfig "$recommended" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.openshift\.io/display-name}' 2>/dev/null)
    echo -e "  ${GREEN}${i}. ${recommended}  [RECOMMENDED]${NC}" >&2
    [ -n "$disp" ] && echo -e "     ${disp}" >&2
    echo -e "     ${BLUE}Why:${NC} ${reason}" >&2
    (( i++ )) || true

    # Remaining configs
    while IFS= read -r cfg; do
        [ -z "$cfg" ] || [ "$cfg" = "$recommended" ] && continue
        configs_arr+=("$cfg")
        disp=$(oc get llminferenceserviceconfig "$cfg" -n "$TEMPLATES_NAMESPACE" \
            -o jsonpath='{.metadata.annotations.openshift\.io/display-name}' 2>/dev/null)
        echo "  ${i}. ${cfg}" >&2
        [ -n "$disp" ] && echo "     ${disp}" >&2
        (( i++ )) || true
    done <<< "$all_configs"

    echo "" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo -n "  Enter choice [1]: " >&2
    local choice
    read -r choice </dev/tty
    choice="${choice:-1}"

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#configs_arr[@]}" ]; then
        echo "${configs_arr[$((choice - 1))]}"
    else
        log_warning "Invalid choice — using recommended: $recommended" >&2
        echo "$recommended"
    fi
}

# ── Parse env vars to YAML ────────────────────────────────────────────────────
yaml_env_vars() {
    local env_string="$1"
    echo "$env_string" | tr ',' '\n' | while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        printf "      - name: %s\n        value: \"%s\"\n" "$key" "$value"
    done
}

# ── Patch HTTPRoute + OpenShift Route request timeout ────────────────────────
# Three-layer approach:
#   1. HTTPRoute rules  — Envoy-level timeout per model (per-model, immediate)
#   2. LLMInferenceService spec — durable source so the controller regenerates
#      the HTTPRoute with the correct timeout after reconciliation
#   3. OpenShift Route annotation — HAProxy cuts connections at 60s by default;
#      must be raised to match, otherwise HAProxy terminates first regardless of
#      what Envoy is configured to allow. The Route is shared across all models
#      so this sets a cluster-wide floor — use the largest timeout in play.
patch_request_timeout() {
    local name="$1" namespace="$2" timeout_sec="$3"
    local httproute="${name}-kserve-route"

    # Wait up to 20s for HTTPRoute to appear
    local tries=0
    until oc get httproute "$httproute" -n "$namespace" &>/dev/null; do
        (( tries++ )) || true
        if [ "$tries" -ge 10 ]; then
            log_warning "HTTPRoute $httproute not found after 20s — timeout patch skipped"
            return
        fi
        sleep 2
    done

    # ── 1. HTTPRoute rules ────────────────────────────────────────────────────
    local updated_rules
    updated_rules=$(oc get httproute "$httproute" -n "$namespace" -o json | python3 -c "
import json, sys
r = json.load(sys.stdin)
for rule in r['spec']['rules']:
    rule.setdefault('timeouts', {})
    rule['timeouts']['backendRequest'] = '${timeout_sec}s'
    rule['timeouts']['request'] = '${timeout_sec}s'
print(json.dumps(r['spec']['rules']))
")

    oc patch httproute "$httproute" -n "$namespace" \
        --type=merge -p "{\"spec\":{\"rules\":$updated_rules}}" >/dev/null
    log_success "HTTPRoute timeout set to ${timeout_sec}s"

    # ── 2. LLMInferenceService spec (durable) ────────────────────────────────
    if oc patch llminferenceservice "$name" -n "$namespace" --type=merge \
        -p "{\"spec\":{\"router\":{\"route\":{\"http\":{\"spec\":{\"rules\":$updated_rules}}}}}}" \
        >/dev/null 2>&1; then
        log_success "Timeout written to LLMInferenceService spec (durable across reconciliation)"
    else
        log_warning "LLMInferenceService spec patch rejected — HTTPRoute timeout will reset on next reconciliation"
        log_warning "To reapply later: ./set-timeout.sh -n $name -ns $namespace --timeout-seconds $timeout_sec"
    fi

    # ── 3. OpenShift Route (HAProxy) ─────────────────────────────────────────
    # HAProxy defaults to 60s and cuts the TCP connection regardless of Envoy settings.
    # Discover the Route from the Gateway the LLMInferenceService is wired to.
    local gw_name gw_ns
    gw_name=$(oc get llminferenceservice "$name" -n "$namespace" \
        -o jsonpath='{.spec.router.gateway.refs[0].name}' 2>/dev/null || echo "$DEFAULT_GATEWAY_NAME")
    gw_ns=$(oc get llminferenceservice "$name" -n "$namespace" \
        -o jsonpath='{.spec.router.gateway.refs[0].namespace}' 2>/dev/null || echo "$DEFAULT_GATEWAY_NAMESPACE")

    local route_name
    route_name=$(oc get route -n "$gw_ns" \
        -o jsonpath="{.items[?(@.spec.to.name==\"${gw_name}-openshift-default\")].metadata.name}" \
        2>/dev/null | tr ' ' '\n' | head -1)

    if [ -n "$route_name" ]; then
        oc annotate route "$route_name" -n "$gw_ns" \
            "haproxy.router.openshift.io/timeout=${timeout_sec}s" --overwrite >/dev/null
        log_success "OpenShift Route '$route_name' HAProxy timeout set to ${timeout_sec}s"
    else
        log_warning "Could not find OpenShift Route for gateway $gw_ns/$gw_name — set manually:"
        log_warning "  oc annotate route <route-name> -n $gw_ns haproxy.router.openshift.io/timeout=${timeout_sec}s --overwrite"
    fi
}

# ── Generate test files from templates ────────────────────────────────────────
# Called after successful deployment. Uses envsubst with an explicit variable
# list so only connection details are filled in — ${API_KEY} is preserved as
# a shell variable reference in the generated scripts.
generate_test_files() {
    local model_name="$1"
    local model_namespace="$2"
    local maas_model_url="$3"   # full URL incl. /namespace/model path
    local maas_base_url="$4"    # gateway root, no path

    local TMPL_DIR; TMPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"
    local TEST_FILE="test-${model_name}.sh"
    local APIKEY_FILE="create-apikey.sh"

    if [ ! -d "$TMPL_DIR" ]; then
        log_warning "Templates directory not found: $TMPL_DIR — skipping test file generation"
        return
    fi

    # Export for envsubst
    export MODEL_NAME="$model_name"
    export MODEL_NAMESPACE="$model_namespace"
    export MAAS_MODEL_URL="$maas_model_url"
    export MAAS_BASE_URL="$maas_base_url"

    # Generate: only substitute the 4 connection vars; leave ${API_KEY} etc. intact
    if [ -f "$TMPL_DIR/test-chat.sh.tmpl" ]; then
        envsubst '${MODEL_NAME} ${MODEL_NAMESPACE} ${MAAS_MODEL_URL}' \
            < "$TMPL_DIR/test-chat.sh.tmpl" > "$TEST_FILE"
        chmod +x "$TEST_FILE"
    fi

    if [ -f "$TMPL_DIR/create-api-key.sh.tmpl" ]; then
        envsubst '${MODEL_NAME} ${MAAS_BASE_URL}' \
            < "$TMPL_DIR/create-api-key.sh.tmpl" > "$APIKEY_FILE"
        chmod +x "$APIKEY_FILE"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Generated test scripts in: $(pwd)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -f "$APIKEY_FILE" ]; then
        log_info "=== $APIKEY_FILE ==="
        cat "$APIKEY_FILE"
        echo ""
    fi

    if [ -f "$TEST_FILE" ]; then
        log_info "=== $TEST_FILE ==="
        cat "$TEST_FILE"
        echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Quick start:"
    log_info "  Step 1 — Create API key:  bash $APIKEY_FILE"
    log_info "  Step 2 — Test the model:  API_KEY=sk-oai-... bash $TEST_FILE"
    echo ""
}

# ── Deployment mode selection ─────────────────────────────────────────────────
# Analyses GPU type, count, and replicas to recommend a mode, then lets the user
# confirm or switch. Called only when --deploy-mode was not given and TTY is present.
# GPU_TYPE and GPU_COUNT must already be set (parsed from --gpu before this runs).
prompt_deploy_mode() {
    local gpu_count="${GPU_COUNT:-1}"
    local replicas="${MIN_REPLICAS:-1}"
    local is_multi=false
    { [ "${replicas}" -gt 1 ] 2>/dev/null && is_multi=true; } || true

    # Decide recommendation + reason
    local rec_mode rec_reason default_choice=1
    if $is_multi; then
        rec_mode="llm-d"
        rec_reason="${replicas} replicas → multi-node scheduling, prefill/decode split recommended"
        default_choice=2
    elif [ "${gpu_count:-1}" -gt 1 ] 2>/dev/null; then
        rec_mode="llm-d"
        rec_reason="${gpu_count} GPUs → prefill/decode split benefits from llm-d scheduling"
        default_choice=2
    else
        rec_mode="vllm"
        rec_reason="1 GPU × 1 replica → single-node vLLM is sufficient"
        default_choice=1
    fi

    echo "" >&2
    echo -e "${CYAN}━━━ Deployment mode ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo -e "  Context: GPU=${YELLOW}${GPU_TYPE:-nvidia.com/gpu}${NC} ×${YELLOW}${gpu_count}${NC}, replicas=${YELLOW}${replicas}${NC}" >&2
    echo "" >&2

    if [ "$rec_mode" = "vllm" ]; then
        echo -e "  ${GREEN}1. vLLM (InferenceConfig)  [RECOMMENDED]${NC}" >&2
        echo    "     Creates a local LLMInferenceServiceConfig from the single-node vLLM template." >&2
        echo -e "     ${BLUE}Why:${NC} ${rec_reason}" >&2
        echo "" >&2
        echo    "  2. llm-d" >&2
        echo    "     Clones a user-selected global config (multi-node / prefill/decode split)." >&2
        echo    "     Choose when: >1 replica, multi-GPU PD split, or advanced scheduling needed." >&2
    else
        echo    "  1. vLLM (InferenceConfig)" >&2
        echo    "     Creates a local LLMInferenceServiceConfig from the single-node vLLM template." >&2
        echo    "     Choose when: simple single-node deployment, same as running models." >&2
        echo "" >&2
        echo -e "  ${GREEN}2. llm-d  [RECOMMENDED]${NC}" >&2
        echo    "     Clones a user-selected global config (multi-node / prefill/decode split)." >&2
        echo -e "     ${BLUE}Why:${NC} ${rec_reason}" >&2
    fi

    echo "" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    echo -n "  Enter choice [${default_choice}]: " >&2
    local choice
    read -r choice </dev/tty
    case "${choice:-$default_choice}" in
        2) DEPLOY_MODE="llm-d" ;;
        *) DEPLOY_MODE="vllm" ;;
    esac
}

# ── Resolve a template name by suffix, ignoring the version prefix ─────────────
# Usage: resolve_template <suffix> [namespace]
# Returns the first config whose name ends with <suffix>, or the suffix itself if not found.
resolve_template() {
    local suffix="$1" ns="${2:-$TEMPLATES_NAMESPACE}"
    local match
    match=$(oc get llminferenceserviceconfig -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null \
        | tr ' ' '\n' | grep -E "(-|^)${suffix}$" | head -1)
    echo "${match:-$suffix}"
}

# ── Create local LLMInferenceServiceConfig from single-node vLLM template ─────
# Creates a namespace-local config named after the model, containing only the vLLM image + template annotations.
create_vllm_inferenceconfig() {
    local template_suffix template_name
    case "$GPU_TYPE" in
        amd.com/gpu)       template_suffix="kserve-config-llm-template-amd-rocm" ;;
        intel.com/gaudi2)  template_suffix="kserve-config-llm-template-intel-gaudi" ;;
        *)                 template_suffix="kserve-config-llm-single-node-template-nvidia-cuda" ;;
    esac
    template_name=$(resolve_template "$template_suffix")

    log_info "vLLM mode: sourcing global template '$template_name'"

    local vllm_image rec_accel supp_top rt_ver disp desc
    vllm_image=$(oc get llminferenceserviceconfig "$template_name" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.spec.template.containers[0].image}' 2>/dev/null)
    if [ -z "$vllm_image" ]; then
        log_error "Could not read vLLM image from $template_name in $TEMPLATES_NAMESPACE"
        exit 1
    fi
    rec_accel=$(oc get llminferenceserviceconfig "$template_name" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.opendatahub\.io/recommended-accelerators}' 2>/dev/null)
    supp_top=$(oc get llminferenceserviceconfig "$template_name" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.opendatahub\.io/supported-topologies}' 2>/dev/null)
    rt_ver=$(oc get llminferenceserviceconfig "$template_name" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.opendatahub\.io/runtime-version}' 2>/dev/null)
    disp=$(oc get llminferenceserviceconfig "$template_name" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.openshift\.io/display-name}' 2>/dev/null)
    desc=$(oc get llminferenceserviceconfig "$template_name" -n "$TEMPLATES_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.openshift\.io/description}' 2>/dev/null)

    log_info "Creating LLMInferenceServiceConfig '$NAME' in $NAMESPACE"
    log_info "  vLLM image: $vllm_image"

    if [ "$DRY_RUN" = true ] || [ -n "$OUTPUT_FILE" ]; then
        log_info "[dry-run] Would create LLMInferenceServiceConfig: $NAME in $NAMESPACE"
    else
        cat <<EOF | oc apply -f - >/dev/null
apiVersion: serving.kserve.io/v1alpha2
kind: LLMInferenceServiceConfig
metadata:
  name: $NAME
  namespace: $NAMESPACE
  annotations:
    opendatahub.io/template-name: $template_name
    opendatahub.io/recommended-accelerators: '$rec_accel'
    opendatahub.io/supported-topologies: '$supp_top'
    opendatahub.io/runtime-version: $rt_ver
    openshift.io/display-name: "$disp"
    openshift.io/description: "$desc"
    serving.kserve.io/well-known-config: "true"
spec:
  model:
    uri: ""
  template:
    containers:
    - image: $vllm_image
      name: main
      resources: {}
EOF
        log_success "LLMInferenceServiceConfig created: $NAME"
    fi
    LLM_CONFIG="$NAME"
}

# ── Clone a global LLMInferenceServiceConfig for llm-d mode ───────────────────
# Copies the full spec from a global config in $TEMPLATES_NAMESPACE into the model
# namespace under the model name, then sets LLM_CONFIG=$NAME for spec.baseRefs.
clone_llmd_inferenceconfig() {
    local source_name="$1"
    log_info "llm-d mode: cloning '$source_name' → '$NAME' in $NAMESPACE"

    if [ "$DRY_RUN" = true ] || [ -n "$OUTPUT_FILE" ]; then
        log_info "[dry-run] Would clone LLMInferenceServiceConfig: $source_name → $NAME"
    else
        oc get llminferenceserviceconfig "$source_name" -n "$TEMPLATES_NAMESPACE" -o json | \
            jq --arg name "$NAME" --arg ns "$NAMESPACE" '
                .metadata.name = $name |
                .metadata.namespace = $ns |
                del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp,
                    .metadata.generation, .metadata.finalizers, .status)
            ' | oc apply -f - >/dev/null
        log_success "LLMInferenceServiceConfig cloned: $NAME"
    fi
    LLM_CONFIG="$NAME"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
CONFIG_FILE="" CLONE_FROM=""
NAME="${MAAS_NAME:-}"
NAMESPACE="${MAAS_NAMESPACE:-}"
STORAGE_URI="${MAAS_STORAGE_URI:-}"
CPU="${MAAS_CPU:-}"
MEMORY="${MAAS_MEMORY:-}"
GPU="${MAAS_GPU:-}"
MIN_REPLICAS="${MAAS_REPLICAS:-$DEFAULT_REPLICAS}"
TIMEOUT="${MAAS_TIMEOUT:-$DEFAULT_TIMEOUT}"
WAIT_TIMEOUT="${MAAS_WAIT_TIMEOUT:-}"
MODEL_ARGS="${MAAS_ARGS:-}"
ENV_VARS="${MAAS_ENV:-}"
DISPLAY_NAME="${MAAS_DISPLAY_NAME:-}"
DESCRIPTION="${MAAS_DESCRIPTION:-}"
HARDWARE_PROFILE="${MAAS_HARDWARE_PROFILE:-}"
REQUEST_TIMEOUT="${MAAS_REQUEST_TIMEOUT:-}"
LLM_CONFIG="${MAAS_LLM_CONFIG:-}"
DEPLOY_MODE="${MAAS_DEPLOY_MODE:-}"
CREATE_HW_PROFILE=false
HW_PROFILE_PRESET=""
GATEWAY_NAME="$DEFAULT_GATEWAY_NAME"
GATEWAY_NAMESPACE="$DEFAULT_GATEWAY_NAMESPACE"
DRY_RUN=false
OUTPUT_FILE=""
NO_WAIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)            usage ;;
        -f|--config-file)     CONFIG_FILE="$2"; shift 2 ;;
        -c|--clone-from)      CLONE_FROM="$2"; shift 2 ;;
        -n|--name)            NAME="$2"; shift 2 ;;
        -ns|--namespace)      NAMESPACE="$2"; shift 2 ;;
        -s|--storage-uri)     STORAGE_URI="$2"; shift 2 ;;
        --deploy-mode)        DEPLOY_MODE="$2"; shift 2 ;;
        --cpu)                CPU="$2"; shift 2 ;;
        --memory)             MEMORY="$2"; shift 2 ;;
        --gpu)                GPU="$2"; shift 2 ;;
        --replicas)           MIN_REPLICAS="$2"; shift 2 ;;
        --timeout)            TIMEOUT="$2"; shift 2 ;;
        --wait-timeout)       WAIT_TIMEOUT="$2"; shift 2 ;;
        --args)               MODEL_ARGS="$2"; shift 2 ;;
        --env)                ENV_VARS="$2"; shift 2 ;;
        --display-name)       DISPLAY_NAME="$2"; shift 2 ;;
        --description)        DESCRIPTION="$2"; shift 2 ;;
        --hardware-profile)   HARDWARE_PROFILE="$2"; shift 2 ;;
        --request-timeout)    REQUEST_TIMEOUT="$2"; shift 2 ;;
        --create-hw-profile)  CREATE_HW_PROFILE=true; shift ;;
        --hw-profile-preset)  HW_PROFILE_PRESET="$2"; shift 2 ;;
        --llm-config)         LLM_CONFIG="$2"; shift 2 ;;
        --gateway-name)       GATEWAY_NAME="$2"; shift 2 ;;
        --gateway-ns)         GATEWAY_NAMESPACE="$2"; shift 2 ;;
        --dry-run)            DRY_RUN=true; shift ;;
        -o|--output)          OUTPUT_FILE="$2"; shift 2 ;;
        --no-wait)            NO_WAIT=true; shift ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

[ -n "$CONFIG_FILE" ] && load_config_file "$CONFIG_FILE"
[ -n "$CLONE_FROM" ]  && clone_from_existing "$CLONE_FROM"

if [ -z "$NAME" ] || [ -z "$NAMESPACE" ]; then
    log_error "Missing required parameters: --name and --namespace"
    usage
fi


# ── Label namespace for MaaS gateway access ───────────────────────────────────
if [ "$DRY_RUN" = false ]; then
    EXISTING_LABEL=$(oc get namespace "$NAMESPACE" \
        -o jsonpath='{.metadata.labels.maas-gateway-access}' 2>/dev/null || echo "")
    if [ "$EXISTING_LABEL" != "true" ]; then
        log_info "Labeling namespace $NAMESPACE with maas-gateway-access=true..."
        oc label namespace "$NAMESPACE" maas-gateway-access=true --overwrite \
            && log_success "Namespace labeled — HTTPRoutes from $NAMESPACE allowed through MaaS gateway"
    else
        log_info "Namespace $NAMESPACE already has maas-gateway-access=true"
    fi
else
    log_info "[dry-run] Would label namespace $NAMESPACE with maas-gateway-access=true"
fi

# ── Storage URI resolution (same logic as deploy-kserve-model.sh) ─────────────
if [[ "$STORAGE_URI" =~ ^hf://RedHatAI/ ]] || [[ "$NAME" =~ ^[Rr]ed[Hh]at ]]; then
    MODEL_LOOKUP="${STORAGE_URI#hf://}"
    [ -z "$MODEL_LOOKUP" ] || [[ ! "$STORAGE_URI" =~ ^(oci|s3|pvc):// ]] && MODEL_LOOKUP="${STORAGE_URI:-$NAME}"
    OCI=$(extract_oci_uri_from_catalog "$MODEL_LOOKUP")
    [[ "$OCI" =~ ^oci:// ]] && STORAGE_URI="$OCI" || { log_error "Failed to get OCI URI for RedHatAI model"; exit 1; }
elif [ -z "$STORAGE_URI" ]; then
    log_warning "No --storage-uri provided, looking up by name in catalog: $NAME"
    STORAGE_URI=$(extract_oci_uri_from_catalog "$NAME")
elif [[ ! "$STORAGE_URI" =~ ^(oci|hf|s3|pvc):// ]]; then
    log_info "Treating storage-uri as catalog model name: $STORAGE_URI"
    STORAGE_URI=$(extract_oci_uri_from_catalog "$STORAGE_URI")
fi

DISPLAY_NAME="${DISPLAY_NAME:-$NAME}"

# ── Model family detection & interactive param suggestions ────────────────────
MODEL_CONFIGS_FILE="${SCRIPT_DIR}/model-configs.json"

_detect_family() {
    local name_lower
    name_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [ ! -f "$MODEL_CONFIGS_FILE" ] && echo "unknown" && return
    while IFS= read -r fam; do
        while IFS= read -r pat; do
            echo "$name_lower" | grep -qi "$pat" && echo "$fam" && return
        done < <(jq -r ".model_families.${fam}.patterns[]" "$MODEL_CONFIGS_FILE" 2>/dev/null)
    done < <(jq -r '.model_families | keys[]' "$MODEL_CONFIGS_FILE" 2>/dev/null)
    echo "unknown"
}

_detect_variant() {
    local name_lower
    name_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    echo "$name_lower" | grep -qiE '(fp8|fp-8)' && echo "fp8" && return
    echo "$name_lower" | grep -qiE '(instruct|chat|-it$)' && echo "instruct" && return
    echo "$name_lower" | grep -qi 'code' && echo "code" && return
    echo "llm"
}

_family_args() {
    local fam="$1" variant="$2"
    [ ! -f "$MODEL_CONFIGS_FILE" ] && return
    local args
    args=$(jq -r ".model_families.${fam}.default_args.${variant}[]? // empty" "$MODEL_CONFIGS_FILE" 2>/dev/null)
    [ -z "$args" ] && args=$(jq -r ".model_families.${fam}.default_args.llm[]? // empty" "$MODEL_CONFIGS_FILE" 2>/dev/null)
    [ -z "$args" ] && args=$(jq -r ".global_defaults.inference.args[]? // empty" "$MODEL_CONFIGS_FILE" 2>/dev/null)
    echo "$args"
}

_family_size_extra() {
    local fam="$1" size="$2"
    [ ! -f "$MODEL_CONFIGS_FILE" ] && return
    jq -r ".model_families.${fam}.size_specific.\"${size}\".additional_args[]? // empty" "$MODEL_CONFIGS_FILE" 2>/dev/null
}

_detect_size() {
    local n
    n=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    for sz in 405b 236b 8x22b 8x7b 72b 70b 67b 32b 27b 14b 9b 8b 7b 3b 2b; do
        echo "$n" | grep -qE "(^|[-_/])${sz}([^0-9]|$)" && echo "$sz" && return
    done
    echo "unknown"
}

if [ -z "$MODEL_ARGS" ] && [ -t 0 ]; then
    _LOOKUP="${STORAGE_URI:-$NAME}"
    _FAM=$(_detect_family "$_LOOKUP")
    _VAR=$(_detect_variant "$_LOOKUP")
    _SZ=$(_detect_size "$_LOOKUP")
    _FAM_TYPE=$([ -f "$MODEL_CONFIGS_FILE" ] && jq -r ".model_families.${_FAM}.type // \"inference\"" "$MODEL_CONFIGS_FILE" 2>/dev/null || echo "inference")

    echo ""
    echo -e "${CYAN}━━━ Model configuration ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Family: ${YELLOW}${_FAM}${NC}  Variant: ${YELLOW}${_VAR}${NC}  Size: ${YELLOW}${_SZ}${NC}"

    # Show recommended args from family config
    _REC_LINES=$(_family_args "$_FAM" "$_VAR")
    _REC_EXTRA=$(_family_size_extra "$_FAM" "$_SZ")
    [ -n "$_REC_EXTRA" ] && _REC_LINES="${_REC_LINES}"$'\n'"${_REC_EXTRA}"
    _REC_COMMA=$(echo "$_REC_LINES" | tr '\n' ',' | sed 's/,*$//')

    if [ -n "$_REC_COMMA" ] && [ "$_FAM" != "unknown" ]; then
        echo -e "  Recommended args: ${GREEN}${_REC_COMMA}${NC}"
        echo ""
        read -p "  Use recommended args? [Y/n]: " _USE_REC
        [[ "${_USE_REC,,}" != "n" ]] && MODEL_ARGS="$_REC_COMMA"
    fi

    # Embedding vs inference
    echo ""
    if [ "$_FAM_TYPE" = "embedding" ]; then
        echo -e "  Model type auto-detected: ${YELLOW}embedding${NC}"
        read -p "  Confirm as embedding model? [Y/n]: " _CONFIRM_EMB
        [[ "${_CONFIRM_EMB,,}" != "n" ]] && _MODEL_IS_EMBEDDING=true
    else
        echo "  Model type:"
        echo "    1) Inference / text generation  [default]"
        echo "    2) Embedding  (adds --runner=pooling)"
        read -p "  Select [1/2]: " _TYPE_CHOICE
        [ "${_TYPE_CHOICE}" = "2" ] && _MODEL_IS_EMBEDDING=true
    fi

    if [ "${_MODEL_IS_EMBEDDING:-false}" = true ]; then
        echo "$MODEL_ARGS" | grep -q "runner=pooling" || MODEL_ARGS="${MODEL_ARGS:+${MODEL_ARGS},}--runner=pooling"
        log_info "Embedding model — added --runner=pooling"
    fi

    # Extra args
    echo ""
    if [ -n "$MODEL_ARGS" ]; then
        echo -e "  Default args to be deployed: ${GREEN}${MODEL_ARGS}${NC}"
    else
        echo -e "  Default args to be deployed: ${YELLOW}(none)${NC}"
    fi
    read -p "  Add extra vLLM args? (comma-separated, leave empty to skip): " _EXTRA
    if [ -n "$_EXTRA" ]; then
        MODEL_ARGS="${MODEL_ARGS:+${MODEL_ARGS},}${_EXTRA}"
    fi

    [ -n "$MODEL_ARGS" ] && echo -e "  ${GREEN}Final VLLM_ADDITIONAL_ARGS:${NC} $MODEL_ARGS"

    # Request timeout
    if [ -z "$REQUEST_TIMEOUT" ]; then
        echo ""
        echo "  HTTPRoute request timeout:"
        echo "    1) No timeout / 0s  [default — gateway decides; suitable for most models]"
        echo "    2) 600s  — 10 min   (slow first-token or large context)"
        echo "    3) 1200s — 20 min   (very large or reasoning models)"
        echo "    4) Custom"
        read -p "  Select [1]: " _TO_CHOICE </dev/tty
        case "${_TO_CHOICE:-1}" in
            2) REQUEST_TIMEOUT=600 ;;
            3) REQUEST_TIMEOUT=1200 ;;
            4) read -p "  Enter seconds: " REQUEST_TIMEOUT </dev/tty ;;
            *) REQUEST_TIMEOUT="" ;;
        esac
    fi
    if [ -n "$REQUEST_TIMEOUT" ] && [ "$REQUEST_TIMEOUT" != "0" ]; then
        echo -e "  ${GREEN}Request timeout:${NC} ${REQUEST_TIMEOUT}s"
    else
        echo -e "  ${GREEN}Request timeout:${NC} none (0s — no limit)"
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

# ── Resource parsing ──────────────────────────────────────────────────────────
IFS='/' read -r CPU_REQ CPU_LIM <<< "$CPU"
CPU_LIM="${CPU_LIM:-$CPU_REQ}"

IFS='/' read -r MEM_REQ MEM_LIM <<< "$MEMORY"
MEM_LIM="${MEM_LIM:-$MEM_REQ}"

if [[ "$GPU" == *"="* ]]; then
    GPU_TYPE=$(echo "$GPU" | cut -d'=' -f1)
    GPU_COUNT=$(echo "$GPU" | cut -d'=' -f2)
else
    GPU_TYPE="nvidia.com/gpu"
    GPU_COUNT="$GPU"
fi

# ── Hardware profile (always auto-created, matching deploy-kserve-model.sh) ───
# If --hardware-profile <name> was given, use that existing profile.
# Otherwise always create ${NAME}-hw-profile from the deployment resources.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HW_PROFILE_SCRIPT="${SCRIPT_DIR}/create-hardware-profile.sh"
HW_PROFILE_NAMESPACE="redhat-ods-applications"

if [ -z "$HARDWARE_PROFILE" ]; then
    HARDWARE_PROFILE="${NAME}-hw-profile"
    CREATE_HW_PROFILE=true
fi

if [ "$CREATE_HW_PROFILE" = true ]; then
    if oc get hardwareprofile "$HARDWARE_PROFILE" -n "$HW_PROFILE_NAMESPACE" &>/dev/null; then
        log_info "Hardware profile $HARDWARE_PROFILE already exists — skipping creation"
    elif [ -f "$HW_PROFILE_SCRIPT" ]; then
        log_info "Creating hardware profile: $HARDWARE_PROFILE (namespace: $HW_PROFILE_NAMESPACE)"

        # Resource bounds: default=request, max=limit or 2×default for CPU / 1.5×default for memory
        CPU_HP_MIN="1"
        CPU_HP_DEFAULT="${CPU_REQ:-2}"
        if [ -n "$CPU_LIM" ]; then
            CPU_HP_MAX="$CPU_LIM"
        else
            CPU_HP_MAX=$(( ${CPU_HP_DEFAULT%%.*} * 2 ))
        fi

        MEM_HP_MIN="4Gi"
        MEM_HP_DEFAULT="${MEM_REQ:-8Gi}"
        MEM_HP_MAX="${MEM_LIM:-$MEM_HP_DEFAULT}"

        CREATE_CMD="bash '$HW_PROFILE_SCRIPT' --name '$HARDWARE_PROFILE' --namespace '$HW_PROFILE_NAMESPACE'"
        CREATE_CMD="$CREATE_CMD --description 'Auto-generated hardware profile for $NAME'"

        if [ -n "$HW_PROFILE_PRESET" ]; then
            CREATE_CMD="$CREATE_CMD --preset '$HW_PROFILE_PRESET'"
        else
            CREATE_CMD="$CREATE_CMD --cpu-min '$CPU_HP_MIN' --cpu-default '$CPU_HP_DEFAULT' --cpu-max '$CPU_HP_MAX'"
            CREATE_CMD="$CREATE_CMD --memory-min '$MEM_HP_MIN' --memory-default '$MEM_HP_DEFAULT' --memory-max '$MEM_HP_MAX'"
            if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" != "0" ]; then
                CREATE_CMD="$CREATE_CMD --gpu-min '$GPU_COUNT' --gpu-default '$GPU_COUNT' --gpu-max '$GPU_COUNT' --gpu-type '$GPU_TYPE'"
            else
                CREATE_CMD="$CREATE_CMD --no-gpu"
            fi
        fi

        eval "$CREATE_CMD" || log_warning "Hardware profile creation failed — proceeding without it"
    else
        log_warning "create-hardware-profile.sh not found at: $HW_PROFILE_SCRIPT — skipping profile creation"
        HARDWARE_PROFILE=""
    fi
fi

# ── Hardware profile annotation lookup ────────────────────────────────────────
HW_PROFILE_ANNOTATIONS=""
if [ -n "$HARDWARE_PROFILE" ]; then
    HW_RV=$(oc get hardwareprofile "$HARDWARE_PROFILE" -n redhat-ods-applications \
        -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || echo "")
    HW_PROFILE_ANNOTATIONS=$(cat <<EOF
    opendatahub.io/hardware-profile-name: $HARDWARE_PROFILE
    opendatahub.io/hardware-profile-namespace: redhat-ods-applications
EOF
)
    [ -n "$HW_RV" ] && HW_PROFILE_ANNOTATIONS="${HW_PROFILE_ANNOTATIONS}
    opendatahub.io/hardware-profile-resource-version: \"$HW_RV\""
fi

# ── Connection secret ─────────────────────────────────────────────────────────
CONNECTION_SECRET_NAME=""
if [ "$DRY_RUN" = false ] && [ -z "$OUTPUT_FILE" ]; then
    if [[ "$STORAGE_URI" =~ ^s3:// ]]; then
        S3_SECRET=$(oc get secret s3-connection -n "$NAMESPACE" -o name 2>/dev/null || echo "")
        if [ -n "$S3_SECRET" ]; then
            CONNECTION_SECRET_NAME="s3-connection"
        else
            log_warning "S3 storage detected but no s3-connection secret in $NAMESPACE — skipping connection annotation"
        fi
    elif [[ "$STORAGE_URI" =~ ^(oci|hf|pvc):// ]]; then
        CONNECTION_SECRET_NAME="secret-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | fold -w 6 | head -n 1)"
        STORAGE_URI_B64=$(echo -n "$STORAGE_URI" | base64)
        cat <<EOF | oc apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: $CONNECTION_SECRET_NAME
  namespace: $NAMESPACE
  annotations:
    opendatahub.io/connection-type-ref: uri-v1
    opendatahub.io/connection-type-protocol: uri
    opendatahub.io/connection-hidden: "true"
    openshift.io/display-name: $CONNECTION_SECRET_NAME
  labels:
    opendatahub.io/dashboard: "true"
type: Opaque
data:
  URI: $STORAGE_URI_B64
EOF
        log_success "Connection secret created: $CONNECTION_SECRET_NAME"
    fi
fi

# ── Build env block for the main container ────────────────────────────────────
CONTAINER_ENV=""
CONTAINER_ENV="${CONTAINER_ENV}      - name: VLLM_NO_USAGE_STATS\n        value: \"1\"\n"

if [ -n "$MODEL_ARGS" ]; then
    VLLM_ARGS_VALUE=$(echo "$MODEL_ARGS" | tr ',' ' ')
    CONTAINER_ENV="${CONTAINER_ENV}      - name: VLLM_ADDITIONAL_ARGS\n        value: \"${VLLM_ARGS_VALUE}\"\n"
fi

if [ -n "$ENV_VARS" ]; then
    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        CONTAINER_ENV="${CONTAINER_ENV}      - name: ${key}\n        value: \"${value}\"\n"
    done < <(echo "$ENV_VARS" | tr ',' '\n')
fi

# ── Deploy mode selection and LLMInferenceServiceConfig setup ─────────────────
# --llm-config explicitly given → skip creation, use that existing local config as-is.
# Otherwise select mode (interactively when TTY, or use DEPLOY_MODE env/flag), then
# create or clone a local LLMInferenceServiceConfig named $NAME in $NAMESPACE.
if [ -n "$LLM_CONFIG" ]; then
    log_info "Using provided LLMInferenceServiceConfig: $LLM_CONFIG (skipping creation)"
else
    if [ -z "$DEPLOY_MODE" ]; then
        if [ -t 0 ]; then
            prompt_deploy_mode
        else
            DEPLOY_MODE="vllm"
        fi
    fi

    case "$DEPLOY_MODE" in
        llm-d)
            log_info "Deploy mode: llm-d"
            LLMD_SOURCE=$(detect_llm_config "$GPU_TYPE" "$MIN_REPLICAS")
            if [ -z "$LLMD_SOURCE" ]; then
                log_warning "No LLMInferenceServiceConfig found in $TEMPLATES_NAMESPACE — falling back to vllm mode"
                create_vllm_inferenceconfig
            else
                clone_llmd_inferenceconfig "$LLMD_SOURCE"
            fi
            ;;
        vllm|*)
            log_info "Deploy mode: vllm (InferenceConfig)"
            create_vllm_inferenceconfig
            ;;
    esac
fi
log_info "LLMInferenceServiceConfig for spec.baseRefs: $LLM_CONFIG"

# ── Generate LLMInferenceService manifest ─────────────────────────────────────
log_info "Generating LLMInferenceService manifest..."

TEMP_DIR=$(mktemp -d)
LLMISVC_MANIFEST="$TEMP_DIR/llminferenceservice.yaml"

cat > "$LLMISVC_MANIFEST" <<EOF
apiVersion: serving.kserve.io/v1alpha2
kind: LLMInferenceService
metadata:
  name: $NAME
  namespace: $NAMESPACE
  annotations:
    opendatahub.io/model-type: generative
    opendatahub.io/genai-use-case: chat
    openshift.io/display-name: "$DISPLAY_NAME"
    openshift.io/description: "$DESCRIPTION"
    serving.kserve.io/stop: "false"
EOF

[ -n "$HW_PROFILE_ANNOTATIONS" ] && echo "$HW_PROFILE_ANNOTATIONS" >> "$LLMISVC_MANIFEST"
[ -n "$CONNECTION_SECRET_NAME" ] && echo "    opendatahub.io/connections: $CONNECTION_SECRET_NAME" >> "$LLMISVC_MANIFEST"

cat >> "$LLMISVC_MANIFEST" <<EOF
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/genai-asset: "true"
spec:
  baseRefs:
  - name: $LLM_CONFIG
  model:
    name: $NAME
    uri: $STORAGE_URI
  replicas: $MIN_REPLICAS
  router:
    gateway:
      refs:
      - name: $GATEWAY_NAME
        namespace: $GATEWAY_NAMESPACE
    route: {}
  template:
    containers:
    - name: main
      env:
$(echo -e "$CONTAINER_ENV" | sed '/^$/d')
EOF

# Resources (only if specified)
if [ -n "$CPU" ] || [ -n "$MEMORY" ] || [ -n "$GPU_COUNT" ]; then
    cat >> "$LLMISVC_MANIFEST" <<EOF
      resources:
        requests:
EOF
    [ -n "$CPU_REQ" ]   && echo "          cpu: \"$CPU_REQ\""         >> "$LLMISVC_MANIFEST"
    [ -n "$MEM_REQ" ]   && echo "          memory: $MEM_REQ"          >> "$LLMISVC_MANIFEST"
    [ -n "$GPU_COUNT" ] && echo "          $GPU_TYPE: \"$GPU_COUNT\"" >> "$LLMISVC_MANIFEST"
    cat >> "$LLMISVC_MANIFEST" <<EOF
        limits:
EOF
    [ -n "$CPU_LIM" ]   && echo "          cpu: \"$CPU_LIM\""         >> "$LLMISVC_MANIFEST"
    [ -n "$MEM_LIM" ]   && echo "          memory: $MEM_LIM"          >> "$LLMISVC_MANIFEST"
    [ -n "$GPU_COUNT" ] && echo "          $GPU_TYPE: \"$GPU_COUNT\"" >> "$LLMISVC_MANIFEST"
fi

# ── RBAC for namespace-level access ──────────────────────────────────────────
RBAC_MANIFEST="$TEMP_DIR/rbac.yaml"
cat > "$RBAC_MANIFEST" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${NAME}-view-role
  namespace: $NAMESPACE
  labels:
    opendatahub.io/dashboard: "true"
rules:
- apiGroups: ["serving.kserve.io"]
  resources: ["llminferenceservices"]
  resourceNames: ["$NAME"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${NAME}-view
  namespace: $NAMESPACE
  labels:
    opendatahub.io/dashboard: "true"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${NAME}-view-role
subjects:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:authenticated
EOF

# ── Dry-run / output-to-file / apply ─────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    log_info "=== LLMInferenceService Manifest ==="
    cat "$LLMISVC_MANIFEST"
    echo "---"
    cat "$RBAC_MANIFEST"

elif [ -n "$OUTPUT_FILE" ]; then
    cat "$LLMISVC_MANIFEST" > "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    cat "$RBAC_MANIFEST" >> "$OUTPUT_FILE"
    log_success "Manifests written to: $OUTPUT_FILE"

else
    log_info "Creating LLMInferenceService..."
    oc apply -f "$LLMISVC_MANIFEST"

    log_info "Creating RBAC..."
    oc apply -f "$RBAC_MANIFEST"

    # Link connection secret to LLMInferenceService
    if [ -n "$CONNECTION_SECRET_NAME" ] && [ "$CONNECTION_SECRET_NAME" != "s3-connection" ]; then
        LLMISVC_UID=$(oc get llminferenceservice "$NAME" -n "$NAMESPACE" \
            -o jsonpath='{.metadata.uid}' 2>/dev/null || echo "")
        if [ -n "$LLMISVC_UID" ]; then
            oc patch secret "$CONNECTION_SECRET_NAME" -n "$NAMESPACE" --type=json -p="[{
                \"op\":\"add\",
                \"path\":\"/metadata/ownerReferences\",
                \"value\":[{
                    \"apiVersion\":\"serving.kserve.io/v1alpha2\",
                    \"kind\":\"LLMInferenceService\",
                    \"name\":\"$NAME\",
                    \"uid\":\"$LLMISVC_UID\",
                    \"blockOwnerDeletion\":false
                }]
            }]" 2>/dev/null || true
            log_success "Connection secret linked to LLMInferenceService"
        fi
    fi

    # ── Wait for Ready (FIFO-based, zero-delay event delivery) ──────────────
    if [ "$NO_WAIT" = true ]; then
        log_info "Skipping wait (--no-wait). Monitor with:"
        log_info "  oc get pods -n $NAMESPACE -w | grep ${NAME}-kserve"
        log_info "  oc get llminferenceservice $NAME -n $NAMESPACE -w"
        exit 0
    fi

    EFFECTIVE_TIMEOUT="${WAIT_TIMEOUT:-$TIMEOUT}"
    log_info "Watching deployment (timeout: ${EFFECTIVE_TIMEOUT}s) — exits immediately on pod failure..."

    WATCH_DIR=$(mktemp -d)
    EVENT_FIFO="$WATCH_DIR/events"
    mkfifo "$EVENT_FIFO"

    cleanup_watchers() {
        kill "$POD_WATCH_PID" "$ISVC_WAIT_PID" 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        rm -rf "$WATCH_DIR"
    }
    trap cleanup_watchers EXIT

    # Keep FIFO open from our side so writers never get EOF-on-open blocked
    exec 3<>"$EVENT_FIFO"

    # Background 1: watch ALL pods in namespace, filter by name prefix
    # (label selector misses prefill/decode split pods — name prefix is reliable)
    (
        oc get pods -n "$NAMESPACE" -w --no-headers 2>/dev/null | \
        while IFS= read -r line; do
            pod_name=$(echo "$line" | awk '{print $1}')
            [[ "$pod_name" != "${NAME}-kserve"* ]] && continue
            pod_status=$(echo "$line" | awk '{print $3}')
            printf 'POD\t%s\t%s\n' "$pod_name" "$pod_status" >> "$EVENT_FIFO"
        done
    ) &
    POD_WATCH_PID=$!

    # Background 2: oc wait → writes READY event the instant condition flips
    (
        oc wait llminferenceservice "$NAME" -n "$NAMESPACE" \
            --for=condition=Ready \
            --timeout="${EFFECTIVE_TIMEOUT}s" 2>/dev/null && \
        printf 'READY\n' >> "$EVENT_FIFO"
    ) &
    ISVC_WAIT_PID=$!

    # Main event loop — read blocks until an event arrives or timeout expires
    DEADLINE=$(( $(date +%s) + EFFECTIVE_TIMEOUT ))
    TIMED_OUT=false
    SUCCESS=false

    while true; do
        REMAINING=$(( DEADLINE - $(date +%s) ))
        if [ "$REMAINING" -le 0 ]; then
            TIMED_OUT=true; break
        fi

        # read -u 3 unblocks the moment a watcher writes a line — no polling delay
        if ! IFS=$'\t' read -r -u 3 -t "$REMAINING" event_type pod_name pod_status; then
            TIMED_OUT=true; break
        fi

        case "$event_type" in
            POD)
                log_info "  Pod $pod_name → $pod_status"
                case "$pod_status" in
                    ImagePullBackOff|ErrImagePull|InvalidImageName)
                        echo ""
                        log_error "Pod $pod_name stuck in $pod_status — image cannot be pulled."
                        log_error "Diagnose: oc describe pod $pod_name -n $NAMESPACE"
                        exit 1 ;;
                    CrashLoopBackOff|OOMKilled)
                        echo ""
                        log_error "Pod $pod_name in $pod_status — container is crashing."
                        log_error "Logs:     oc logs $pod_name -n $NAMESPACE -c main"
                        log_error "Previous: oc logs $pod_name -n $NAMESPACE -c main --previous"
                        log_error "Describe: oc describe pod $pod_name -n $NAMESPACE"
                        echo ""
                        log_info "=== Last log lines ==="
                        oc logs "$pod_name" -n "$NAMESPACE" -c main --tail=20 2>/dev/null || true
                        exit 1 ;;
                    Error)
                        MAIN_STATE=$(oc get pod "$pod_name" -n "$NAMESPACE" \
                            -o jsonpath='{.status.containerStatuses[?(@.name=="main")].state.terminated.reason}' \
                            2>/dev/null || echo "")
                        if [ -n "$MAIN_STATE" ] && [ "$MAIN_STATE" != "Completed" ]; then
                            echo ""
                            log_error "Main container of $pod_name terminated: $MAIN_STATE"
                            log_error "Logs: oc logs $pod_name -n $NAMESPACE -c main --previous"
                            exit 1
                        fi ;;
                esac ;;
            READY)
                SUCCESS=true; break ;;
        esac
    done

    if $SUCCESS; then
        log_success "LLMInferenceService is Ready."
        echo ""

        ISVC_JSON=$(oc get llminferenceservice "$NAME" -n "$NAMESPACE" -o json 2>/dev/null)

        MAAS_MODEL_URL=$(echo "$ISVC_JSON" | jq -r '
            .status.addresses[]?
            | select(.name == "gateway-external")
            | select(.url | contains("/'"$NAMESPACE"'/'"$NAME"'"))
            | .url' | head -1)

        MAAS_BASE_URL=$(echo "$ISVC_JSON" | jq -r '
            .status.addresses[]?
            | select(.name == "gateway-external-model-routing")
            | .url' | head -1 | sed 's|/$||')

        [ -n "$MAAS_MODEL_URL" ] && log_success "Model endpoint: $MAAS_MODEL_URL"
        log_info "Monitor HTTPRoute: oc get httproute -n $NAMESPACE | grep $NAME"

        if [ -z "$MAAS_BASE_URL" ]; then
            _maas_host=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null)
            _maas_tls=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
            _maas_scheme=$([[ -n "$_maas_tls" ]] && echo "https" || echo "http")
            MAAS_BASE_URL="${_maas_scheme}://${_maas_host}"
        fi
        MAAS_MODEL_URL="${MAAS_MODEL_URL:-${MAAS_BASE_URL}/${NAMESPACE}/${NAME}}"

        generate_test_files \
            "$NAME" \
            "$NAMESPACE" \
            "$MAAS_MODEL_URL" \
            "$MAAS_BASE_URL"

        if [ -n "$REQUEST_TIMEOUT" ] && [ "$REQUEST_TIMEOUT" != "0" ]; then
            log_info "Applying request timeout: ${REQUEST_TIMEOUT}s..."
            patch_request_timeout "$NAME" "$NAMESPACE" "$REQUEST_TIMEOUT"
        fi

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Next step — wire up governance and create an API key:"
        log_info "  bash create-governance.sh -n $NAME -ns $NAMESPACE --user <username>"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    elif $TIMED_OUT; then
        log_error "Timed out after ${EFFECTIVE_TIMEOUT}s waiting for Ready."
        echo ""
        log_info "=== Current status ==="
        oc get llminferenceservice "$NAME" -n "$NAMESPACE" -o json 2>/dev/null | \
            jq -r '.status.conditions[]? | "  \(.type): \(.status) — \(.message // "")"' 2>/dev/null || true
        echo ""
        log_info "=== Pods ==="
        oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "^${NAME}-kserve" || true
        echo ""
        log_info "=== HTTPRoute ==="
        oc get httproute -n "$NAMESPACE" 2>/dev/null | grep "$NAME" || true
        echo ""
        log_info "Full diagnostics: /debug-maas"

        DEPLOY_NAME=$(oc get deployment -n "$NAMESPACE" \
            -l "serving.kserve.io/llminferenceservice=$NAME" \
            --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
        if [ -n "$DEPLOY_NAME" ]; then
            REVISIONS=$(oc rollout history deployment/"$DEPLOY_NAME" -n "$NAMESPACE" 2>/dev/null \
                | grep -c "^[0-9]" || echo 0)
            if [ "$REVISIONS" -gt 1 ]; then
                log_info "Rolling back deployment/$DEPLOY_NAME to previous revision to clear stuck pods..."
                oc rollout undo deployment/"$DEPLOY_NAME" -n "$NAMESPACE" &>/dev/null \
                    && log_info "Rollback complete — cluster restored to previous state" || true
            fi
        fi

        exit 1
    fi
fi

rm -rf "$TEMP_DIR"
