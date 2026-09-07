#!/usr/bin/env bash
# create-governance.sh — Wire a deployed model into MaaS governance.
#
# Creates three resources in order:
#   1. MaaSModelRef    (in the model namespace)
#   2. MaaSSubscription (in models-as-a-service)
#   3. MaaSAuthPolicy   (in models-as-a-service)
#
# Run this once per model after deploy-llm.sh reports Ready.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") -n <name> -ns <namespace> [OPTIONS]

Create MaaS governance objects for a model that was deployed with deploy-llm.sh.

Required:
  -n,  --name        <name>       LLMInferenceService / MaaSModelRef name
  -ns, --namespace   <namespace>  Model namespace

MaaSSubscription:
  --sub-name         <name>       Subscription name (default: <name>-sub)
  --user             <username>   Subscribe this OpenShift user (repeatable)
  --group            <group>      Subscribe this OpenShift group (repeatable)
  --rate-hour        <N>          Token limit per hour   (default: 1000000)
  --rate-day         <N>          Token limit per 24h    (default: 10000000)
  --priority         <N>          Subscription priority  (default: 10)

MaaSAuthPolicy:
  --auth-name        <name>       AuthPolicy name (default: <name>-auth)

Other:
  --dry-run                       Print manifests without applying
  -h, --help                      Show this help

Examples:
  # Single user, default rate limits
  $(basename "$0") -n <model-name> -ns <model-namespace> --user <oc-username>

  # Group access with high rate limits
  $(basename "$0") -n <model-name> -ns <model-namespace> \\
    --group <group-name> --rate-hour 10000000 --rate-day 100000000

  # Dry-run — preview manifests only
  $(basename "$0") -n <model-name> -ns <model-namespace> --user <oc-username> --dry-run
EOF
    exit 1
}

# ── defaults ─────────────────────────────────────────────────────────────────
NAME=""
NAMESPACE=""
SUB_NAME=""
AUTH_NAME=""
USERS=()
OWNER_GROUPS=()
RATE_HOUR=1000000
RATE_DAY=10000000
PRIORITY=10
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)        NAME="$2";       shift 2 ;;
        -ns|--namespace)  NAMESPACE="$2";  shift 2 ;;
        --sub-name)       SUB_NAME="$2";   shift 2 ;;
        --auth-name)      AUTH_NAME="$2";  shift 2 ;;
        --user)           USERS+=("$2");   shift 2 ;;
        --group)          OWNER_GROUPS+=("$2");  shift 2 ;;
        --rate-hour)      RATE_HOUR="$2";  shift 2 ;;
        --rate-day)       RATE_DAY="$2";   shift 2 ;;
        --priority)       PRIORITY="$2";   shift 2 ;;
        --dry-run)        DRY_RUN=true;    shift ;;
        -h|--help)        usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

[ -z "$NAME" ]      && { log_error "--name is required";      usage; }
[ -z "$NAMESPACE" ] && { log_error "--namespace is required"; usage; }

if [ ${#USERS[@]} -eq 0 ] && [ ${#OWNER_GROUPS[@]} -eq 0 ]; then
    log_error "At least one --user or --group is required."
    exit 1
fi

SUB_NAME="${SUB_NAME:-${NAME}-sub}"
AUTH_NAME="${AUTH_NAME:-${NAME}-auth}"

# ── build owner YAML ─────────────────────────────────────────────────────────
build_owner_yaml() {
    if [ ${#USERS[@]} -gt 0 ]; then
        echo "    users:"
        for u in "${USERS[@]}"; do echo "      - $u"; done
    fi
    if [ ${#OWNER_GROUPS[@]} -gt 0 ]; then
        echo "    groups:"
        for g in "${OWNER_GROUPS[@]}"; do
            echo "      - kind: Group"
            echo "        name: $g"
        done
    fi
}

build_subjects_yaml() {
    if [ ${#USERS[@]} -gt 0 ]; then
        echo "    users:"
        for u in "${USERS[@]}"; do echo "      - $u"; done
    fi
    if [ ${#OWNER_GROUPS[@]} -gt 0 ]; then
        echo "    groups:"
        for g in "${OWNER_GROUPS[@]}"; do echo "      - name: $g"; done
    fi
}

OWNER_YAML=$(build_owner_yaml)
SUBJECTS_YAML=$(build_subjects_yaml)

# ── manifests ─────────────────────────────────────────────────────────────────
MODELREF_MANIFEST=$(cat <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata:
  name: $NAME
  namespace: $NAMESPACE
spec:
  modelRef:
    kind: LLMInferenceService
    name: $NAME
EOF
)

SUBSCRIPTION_MANIFEST=$(cat <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: $SUB_NAME
  namespace: models-as-a-service
spec:
  owner:
$OWNER_YAML
  modelRefs:
    - name: $NAME
      namespace: $NAMESPACE
      tokenRateLimits:
        - limit: $RATE_HOUR
          window: "1h"
        - limit: $RATE_DAY
          window: "24h"
  priority: $PRIORITY
EOF
)

AUTHPOLICY_MANIFEST=$(cat <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: $AUTH_NAME
  namespace: models-as-a-service
spec:
  subjects:
$SUBJECTS_YAML
  modelRefs:
    - name: $NAME
      namespace: $NAMESPACE
EOF
)

# ── dry-run ───────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo "# ── MaaSModelRef ────────────────────────────────────────────"
    echo "$MODELREF_MANIFEST"
    echo "---"
    echo "# ── MaaSSubscription ────────────────────────────────────────"
    echo "$SUBSCRIPTION_MANIFEST"
    echo "---"
    echo "# ── MaaSAuthPolicy ──────────────────────────────────────────"
    echo "$AUTHPOLICY_MANIFEST"
    exit 0
fi

# ── apply ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Creating MaaS governance objects for: $NAMESPACE/$NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "1/3  MaaSModelRef ($NAMESPACE/$NAME)..."
echo "$MODELREF_MANIFEST" | oc apply -f -
log_success "MaaSModelRef applied."

log_info "2/3  MaaSSubscription (models-as-a-service/$SUB_NAME)..."
echo "$SUBSCRIPTION_MANIFEST" | oc apply -f -
log_success "MaaSSubscription applied."

log_info "3/3  MaaSAuthPolicy (models-as-a-service/$AUTH_NAME)..."
echo "$AUTHPOLICY_MANIFEST" | oc apply -f -
log_success "MaaSAuthPolicy applied."

# ── verify ────────────────────────────────────────────────────────────────────
echo ""
log_info "Waiting up to 30s for resources to reconcile..."
sleep 10

SUB_PHASE=$(oc get maassubscription "$SUB_NAME" -n models-as-a-service \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
AUTH_PHASE=$(oc get maasauthpolicy "$AUTH_NAME" -n models-as-a-service \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
MODELREF_PHASE=$(oc get maasmodelref "$NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  MaaSModelRef:    %s\n" "$MODELREF_PHASE"
printf "  MaaSSubscription: %s\n" "$SUB_PHASE"
printf "  MaaSAuthPolicy:  %s\n" "$AUTH_PHASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SUB_PHASE" = "Active" ] && [ "$AUTH_PHASE" = "Active" ]; then
    log_success "Governance ready."

    # ── generate test scripts ─────────────────────────────────────────────────
    TMPL_DIR="$SCRIPT_DIR/templates"
    TEST_FILE="test-${NAME}.sh"
    APIKEY_FILE="create-apikey.sh"

    _MAAS_HOST=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null)
    _MAAS_TLS=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
    _MAAS_SCHEME=$([[ -n "$_MAAS_TLS" ]] && echo "https" || echo "http")
    MAAS_BASE_URL="${_MAAS_SCHEME}://${_MAAS_HOST:-maas.apps.<cluster>}"
    MAAS_MODEL_URL="${MAAS_BASE_URL}/${NAMESPACE}/${NAME}"

    if [ -d "$TMPL_DIR" ]; then
        export MODEL_NAME="$NAME"
        export MODEL_NAMESPACE="$NAMESPACE"
        export MAAS_MODEL_URL
        export MAAS_BASE_URL

        envsubst '${MODEL_NAME} ${MODEL_NAMESPACE} ${MAAS_MODEL_URL}' \
            < "$TMPL_DIR/test-chat.sh.tmpl" > "$TEST_FILE"
        chmod +x "$TEST_FILE"

        envsubst '${MODEL_NAME} ${MAAS_BASE_URL}' \
            < "$TMPL_DIR/create-api-key.sh.tmpl" > "$APIKEY_FILE"
        chmod +x "$APIKEY_FILE"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_success "Generated test scripts in: $(pwd)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        log_info "=== $APIKEY_FILE ==="
        cat "$APIKEY_FILE"
        echo ""
        log_info "=== $TEST_FILE ==="
        cat "$TEST_FILE"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Quick start:"
        log_info "  Step 1 — Create API key:  bash $APIKEY_FILE"
        log_info "  Step 2 — Test the model:  API_KEY=sk-oai-... bash $TEST_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        log_info "Quick start:"
        log_info "  Step 1 — Create API key:  bash create-apikey.sh"
        log_info "  Step 2 — Test the model:  API_KEY=sk-oai-... bash test-${NAME}.sh"
    fi
else
    echo ""
    log_error "One or more resources did not reach expected phase."
    log_error "Check controller logs: oc logs -n redhat-ods-applications -l app.kubernetes.io/name=maas-controller --tail=40"
    if [ "$MODELREF_PHASE" = "unknown" ] || [ "$MODELREF_PHASE" = "Pending" ]; then
        log_error "MaaSModelRef is $MODELREF_PHASE — ensure LLMInferenceService '$NAME' is Ready in '$NAMESPACE'."
    fi
    exit 1
fi
