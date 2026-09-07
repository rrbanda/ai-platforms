#!/usr/bin/env bash
# set-timeout.sh — Set or update the request timeout for a deployed MaaS model.
#
# Three-layer approach (all three must agree or the shortest one wins):
#   1. HTTPRoute rules  — Envoy-level per-model timeout (immediate)
#   2. LLMInferenceService spec — durable; the controller regenerates the HTTPRoute
#      from this on reconciliation (can be blocked by the admission webhook when the
#      hardware profile referenced in annotations no longer exists)
#   3. OpenShift Route annotation (haproxy.router.openshift.io/timeout) — HAProxy
#      cuts the TCP connection at 60s by default regardless of what Envoy allows.
#      This Route is shared across all models on the same gateway.
#
# To reapply after a reset:  ./set-timeout.sh -n <name> -ns <namespace> --timeout-seconds <N>

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") -n <name> -ns <namespace> --timeout-seconds <N>

Set the HTTPRoute request timeout for a deployed MaaS model.
Use 0 to remove an explicit timeout (revert to gateway default / no limit).

Required:
  -n,  --name        <name>       LLMInferenceService name
  -ns, --namespace   <namespace>  Model namespace
  -t,  --timeout-seconds <N>      Timeout in seconds (0 = no timeout)

Other:
  --dry-run                       Show the changes without applying
  -h, --help                      Show this help

Examples:
  # Set 20-minute timeout
  $(basename "$0") -n qwen3-8b-fp8-dynamic -ns ai-eng-cracow --timeout-seconds 1200

  # Remove explicit timeout (revert to no-limit)
  $(basename "$0") -n qwen3-8b-fp8-dynamic -ns ai-eng-cracow --timeout-seconds 0

  # Preview only
  $(basename "$0") -n qwen3-8b-fp8-dynamic -ns ai-eng-cracow --timeout-seconds 600 --dry-run
EOF
    exit 1
}

NAME="" NAMESPACE="" TIMEOUT_SEC="" DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)             NAME="$2";        shift 2 ;;
        -ns|--namespace)       NAMESPACE="$2";   shift 2 ;;
        -t|--timeout-seconds)  TIMEOUT_SEC="$2"; shift 2 ;;
        --dry-run)             DRY_RUN=true;     shift ;;
        -h|--help)             usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

[ -z "$NAME" ]        && { log_error "--name is required";            usage; }
[ -z "$NAMESPACE" ]   && { log_error "--namespace is required";       usage; }
[ -z "$TIMEOUT_SEC" ] && { log_error "--timeout-seconds is required"; usage; }

if ! [[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]]; then
    log_error "--timeout-seconds must be a non-negative integer (got: $TIMEOUT_SEC)"
    exit 1
fi

HTTPROUTE="${NAME}-kserve-route"
TIMEOUT_VAL="${TIMEOUT_SEC}s"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HW_PROFILE_SCRIPT="${SCRIPT_DIR}/../model-deployment/create-hardware-profile.sh"
HW_PROFILE_NAMESPACE="redhat-ods-applications"

# ── Verify resources exist ────────────────────────────────────────────────────
oc get llminferenceservice "$NAME" -n "$NAMESPACE" &>/dev/null || {
    log_error "LLMInferenceService not found: $NAME in $NAMESPACE"
    exit 1
}

oc get httproute "$HTTPROUTE" -n "$NAMESPACE" &>/dev/null || {
    log_error "HTTPRoute not found: $HTTPROUTE in $NAMESPACE"
    log_error "The model may not have completed deployment. Check: oc get llminferenceservice $NAME -n $NAMESPACE"
    exit 1
}

# ── Check hardware profile (required for durable LLMInferenceService spec patch) ──
# The admission webhook validates that the hardware profile referenced in the
# LLMInferenceService annotations exists. If it's missing, the durable spec patch
# will be rejected and the timeout will reset on the next controller reconciliation.
ISVC_JSON=$(oc get llminferenceservice "$NAME" -n "$NAMESPACE" -o json)
HW_PROFILE_NAME=$(echo "$ISVC_JSON" | python3 -c "
import json, sys
ann = json.load(sys.stdin)['metadata'].get('annotations', {})
print(ann.get('opendatahub.io/hardware-profile-name', ''))
" 2>/dev/null)

if [ -n "$HW_PROFILE_NAME" ]; then
    if ! oc get hardwareprofile "$HW_PROFILE_NAME" -n "$HW_PROFILE_NAMESPACE" &>/dev/null; then
        log_warning "Hardware profile '$HW_PROFILE_NAME' not found in $HW_PROFILE_NAMESPACE"
        log_warning "The admission webhook will reject the LLMInferenceService spec patch — timeout won't be durable."
        echo ""

        if [ -f "$HW_PROFILE_SCRIPT" ] && [ "$DRY_RUN" = false ]; then
            echo -n "  Recreate it now from the model's resources? [Y/n]: "
            read -r _RECREATE </dev/tty
            if [[ "${_RECREATE,,}" != "n" ]]; then
                CPU_REQ=$(echo "$ISVC_JSON" | python3 -c "
import json, sys
c = json.load(sys.stdin)['spec']['template']['containers'][0]['resources']
print(c.get('requests', {}).get('cpu', '2'))
")
                MEM_REQ=$(echo "$ISVC_JSON" | python3 -c "
import json, sys
c = json.load(sys.stdin)['spec']['template']['containers'][0]['resources']
print(c.get('requests', {}).get('memory', '8Gi'))
")
                GPU_COUNT=$(echo "$ISVC_JSON" | python3 -c "
import json, sys
c = json.load(sys.stdin)['spec']['template']['containers'][0]['resources']
print(c.get('requests', {}).get('nvidia.com/gpu', ''))
")
                GPU_TYPE="nvidia.com/gpu"

                log_info "Recreating hardware profile '$HW_PROFILE_NAME' (cpu=$CPU_REQ, memory=$MEM_REQ, gpu=$GPU_COUNT)..."
                CREATE_CMD="bash '$HW_PROFILE_SCRIPT' --name '$HW_PROFILE_NAME' --namespace '$HW_PROFILE_NAMESPACE'"
                CREATE_CMD="$CREATE_CMD --cpu-min 1 --cpu-default '$CPU_REQ' --cpu-max '$CPU_REQ'"
                CREATE_CMD="$CREATE_CMD --memory-min 4Gi --memory-default '$MEM_REQ' --memory-max '$MEM_REQ'"
                if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" != "0" ]; then
                    CREATE_CMD="$CREATE_CMD --gpu-min '$GPU_COUNT' --gpu-default '$GPU_COUNT' --gpu-max '$GPU_COUNT' --gpu-type '$GPU_TYPE'"
                else
                    CREATE_CMD="$CREATE_CMD --no-gpu"
                fi
                CREATE_CMD="$CREATE_CMD --description 'Recreated from $NAMESPACE/$NAME LLMInferenceService resources'"

                if eval "$CREATE_CMD" >/dev/null 2>&1; then
                    log_success "Hardware profile '$HW_PROFILE_NAME' recreated — durable patch will now succeed"
                else
                    log_warning "Hardware profile creation failed — continuing with HTTPRoute-only patch"
                fi
            else
                log_warning "Skipping recreation — timeout will be applied to HTTPRoute only (temporary)"
            fi
        else
            log_warning "Run manually to enable durable patch:"
            log_warning "  bash $HW_PROFILE_SCRIPT --name '$HW_PROFILE_NAME' --namespace '$HW_PROFILE_NAMESPACE' \\"
            log_warning "    --cpu-default <N> --memory-default <NNGi> --gpu-default <N>"
        fi
        echo ""
    else
        log_info "Hardware profile '$HW_PROFILE_NAME' found — durable patch will succeed"
    fi
fi

# ── Build updated rules ───────────────────────────────────────────────────────
CURRENT_RULE_COUNT=$(oc get httproute "$HTTPROUTE" -n "$NAMESPACE" -o json | \
    python3 -c "import json,sys; print(len(json.load(sys.stdin)['spec']['rules']))")

UPDATED_RULES=$(oc get httproute "$HTTPROUTE" -n "$NAMESPACE" -o json | python3 -c "
import json, sys
r = json.load(sys.stdin)
for rule in r['spec']['rules']:
    rule.setdefault('timeouts', {})
    rule['timeouts']['backendRequest'] = '${TIMEOUT_VAL}'
    rule['timeouts']['request'] = '${TIMEOUT_VAL}'
print(json.dumps(r['spec']['rules']))
")

# ── Discover the OpenShift Route for the MaaS gateway ────────────────────────
GW_NAME=$(oc get llminferenceservice "$NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.router.gateway.refs[0].name}' 2>/dev/null || echo "maas-default-gateway")
GW_NS=$(oc get llminferenceservice "$NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.router.gateway.refs[0].namespace}' 2>/dev/null || echo "openshift-ingress")
OCP_ROUTE=$(oc get route -n "$GW_NS" \
    -o jsonpath="{.items[?(@.spec.to.name==\"${GW_NAME}-openshift-default\")].metadata.name}" \
    2>/dev/null | tr ' ' '\n' | head -1)

CURRENT_ROUTE_TIMEOUT=$(oc get route "$OCP_ROUTE" -n "$GW_NS" \
    -o jsonpath='{.metadata.annotations.haproxy\.router\.openshift\.io/timeout}' \
    2>/dev/null || echo "unset (HAProxy default: 60s)")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Model:        $NAMESPACE/$NAME"
log_info "HTTPRoute:    $HTTPROUTE  ($CURRENT_RULE_COUNT rules)"
log_info "OCP Route:    ${OCP_ROUTE:-not found} (current: $CURRENT_ROUTE_TIMEOUT)"
log_info "Target:       $TIMEOUT_VAL  (all three layers)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$DRY_RUN" = true ]; then
    log_info "[dry-run] Would patch HTTPRoute ($CURRENT_RULE_COUNT rules) → ${TIMEOUT_VAL}"
    if [ -n "$HW_PROFILE_NAME" ] && oc get hardwareprofile "$HW_PROFILE_NAME" -n "$HW_PROFILE_NAMESPACE" &>/dev/null; then
        log_info "[dry-run] Hardware profile '$HW_PROFILE_NAME' exists — LLMInferenceService spec patch would succeed (durable)"
    elif [ -n "$HW_PROFILE_NAME" ]; then
        log_warning "[dry-run] Hardware profile '$HW_PROFILE_NAME' missing — LLMInferenceService spec patch would fail (HTTPRoute-only)"
    fi
    if [ -n "$OCP_ROUTE" ]; then
        log_info "[dry-run] Would annotate route/$OCP_ROUTE -n $GW_NS → haproxy.router.openshift.io/timeout=${TIMEOUT_VAL}"
    else
        log_warning "[dry-run] OpenShift Route not found for gateway $GW_NS/$GW_NAME — HAProxy step would be skipped"
    fi
    exit 0
fi

# ── 1. HTTPRoute rules (immediate) ───────────────────────────────────────────
oc patch httproute "$HTTPROUTE" -n "$NAMESPACE" \
    --type=merge -p "{\"spec\":{\"rules\":$UPDATED_RULES}}" >/dev/null
log_success "1/3  HTTPRoute timeout → ${TIMEOUT_VAL}"

# ── 2. LLMInferenceService spec (durable across reconciliation) ──────────────
if oc patch llminferenceservice "$NAME" -n "$NAMESPACE" --type=merge \
    -p "{\"spec\":{\"router\":{\"route\":{\"http\":{\"spec\":{\"rules\":$UPDATED_RULES}}}}}}" \
    >/dev/null 2>&1; then
    log_success "2/3  LLMInferenceService spec timeout → ${TIMEOUT_VAL} (durable)"
else
    log_warning "2/3  LLMInferenceService spec patch rejected by admission webhook"
    log_warning "     HTTPRoute timeout will reset on next controller reconciliation."
    log_warning "     To reapply: ./set-timeout.sh -n $NAME -ns $NAMESPACE --timeout-seconds $TIMEOUT_SEC"
fi

# ── 3. OpenShift Route / HAProxy ─────────────────────────────────────────────
# HAProxy enforces its own TCP timeout independently of Envoy. The default is 60s
# and will cut connections before Envoy gets a chance to apply its own timeout.
# This Route is shared across all models on the same gateway — setting it here
# raises the floor for everyone, so use the largest timeout needed in the cluster.
if [ -n "$OCP_ROUTE" ]; then
    oc annotate route "$OCP_ROUTE" -n "$GW_NS" \
        "haproxy.router.openshift.io/timeout=${TIMEOUT_VAL}" --overwrite >/dev/null
    log_success "3/3  OpenShift Route '$OCP_ROUTE' HAProxy timeout → ${TIMEOUT_VAL}"
else
    log_warning "3/3  OpenShift Route not found for gateway $GW_NS/$GW_NAME — set manually:"
    log_warning "     oc annotate route <route> -n $GW_NS haproxy.router.openshift.io/timeout=${TIMEOUT_VAL} --overwrite"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
sleep 3
ACTUAL_HTTPROUTE=$(oc get httproute "$HTTPROUTE" -n "$NAMESPACE" -o json | python3 -c "
import json, sys
rules = json.load(sys.stdin)['spec']['rules']
vals = {(r.get('timeouts',{}).get('backendRequest','?'), r.get('timeouts',{}).get('request','?')) for r in rules}
print(', '.join(f'backendRequest={b} request={r}' for b,r in vals))
")
ACTUAL_ROUTE=$(oc get route "$OCP_ROUTE" -n "$GW_NS" \
    -o jsonpath='{.metadata.annotations.haproxy\.router\.openshift\.io/timeout}' \
    2>/dev/null || echo "unknown")
log_info "Verified HTTPRoute:    $ACTUAL_HTTPROUTE"
log_info "Verified HAProxy:      $ACTUAL_ROUTE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
