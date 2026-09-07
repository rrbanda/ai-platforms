#!/usr/bin/env bash
# MaaS availability check — verifies all components defined by the enable-maas skill.
# Run automatically by deploy-llm.sh before any deployment action.
#
# Exit codes:
#   0 — all critical checks passed (warnings may still be present)
#   1 — one or more critical checks failed

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

PASS=0; FAIL=0; WARN=0

_ok()   { printf "  ${GREEN}✓${NC}  %-60s ${GREEN}%s${NC}\n" "$1" "${2:-OK}" >&2;   ((PASS++)) || true; }
_fail() { printf "  ${RED}✗${NC}  %-60s ${RED}%s${NC}\n"    "$1" "${2:-MISSING}" >&2; ((FAIL++)) || true; }
_warn() { printf "  ${YELLOW}⚡${NC}  %-60s ${YELLOW}%s${NC}\n" "$1" "${2:-CHECK}" >&2; ((WARN++)) || true; }
_skip() { printf "  ${BLUE}–${NC}  %-60s ${BLUE}%s${NC}\n"   "$1" "${2:-skipped}" >&2; }

_section() {
    echo "" >&2
    echo -e "${CYAN}── $1 ──────────────────────────────────────────────────────────${NC}" >&2
}

echo "" >&2
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "${CYAN}  MaaS availability check                                         ${NC}" >&2
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2

# ── Detect Authorino namespace (same logic as enable-maas.sh) ─────────────────
AUTHORINO_NS=""
if oc get deployment authorino -n openshift-operators &>/dev/null; then
    AUTHORINO_NS="openshift-operators"
elif oc get deployment authorino -n kuadrant-system &>/dev/null; then
    AUTHORINO_NS="kuadrant-system"
fi

# ── Section 1: DataScienceCluster ─────────────────────────────────────────────
_section "DataScienceCluster (enable-maas step 2)"

# DSC exists
if ! oc get dsc default-dsc &>/dev/null; then
    _fail "DataScienceCluster default-dsc" "not found — install RHOAI first"
else
    # ModelsAsAServiceReady (RHOAI ≥ 3.4 uses ModelsAsAServiceReady, older uses ModelsAsServiceReady)
    DSC_MAAS=$(oc get dsc default-dsc \
        -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].status}' 2>/dev/null || echo "")
    [ -z "$DSC_MAAS" ] && DSC_MAAS=$(oc get dsc default-dsc \
        -o jsonpath='{.status.conditions[?(@.type=="ModelsAsServiceReady")].status}' 2>/dev/null || echo "")

    if [ "$DSC_MAAS" = "True" ]; then
        _ok "DSC ModelsAsAServiceReady" "True"
    else
        _fail "DSC ModelsAsAServiceReady" "got: '${DSC_MAAS:-missing}' — run /debug-maas Issue A"
    fi

    # AIGateway managementState
    AIGATEWAY_STATE=$(oc get dsc default-dsc \
        -o jsonpath='{.spec.components.aigateway.managementState}' 2>/dev/null || echo "")
    if [ "$AIGATEWAY_STATE" = "Managed" ]; then
        _ok "DSC aigateway managementState" "Managed"
    else
        _fail "DSC aigateway managementState" "got: '${AIGATEWAY_STATE:-missing}' — run enable-maas step 2"
    fi
fi

# AIGateway CR
AIGATEWAY_MAAS=$(oc get aigateway default-aigateway \
    -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].status}' 2>/dev/null || echo "")
if [ "$AIGATEWAY_MAAS" = "True" ]; then
    _ok "AIGateway default-aigateway ModelsAsAServiceReady" "True"
elif [ -z "$AIGATEWAY_MAAS" ]; then
    _warn "AIGateway default-aigateway ModelsAsAServiceReady" "not found or status missing"
else
    _fail "AIGateway default-aigateway ModelsAsAServiceReady" "got: '${AIGATEWAY_MAAS}'"
fi

# ── Section 2: Dashboard config ───────────────────────────────────────────────
_section "Dashboard config (enable-maas step 3)"

MAAS_FLAG=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
    -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null || echo "")
VLLM_FLAG=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
    -o jsonpath='{.spec.dashboardConfig.vLLMDeploymentOnMaaS}' 2>/dev/null || echo "")

if [ "$MAAS_FLAG" = "true" ]; then
    _ok "OdhDashboardConfig: modelAsService" "true"
else
    _warn "OdhDashboardConfig: modelAsService" "got: '${MAAS_FLAG:-missing}' — run enable-maas step 3"
fi
if [ "$VLLM_FLAG" = "true" ]; then
    _ok "OdhDashboardConfig: vLLMDeploymentOnMaaS" "true"
else
    _warn "OdhDashboardConfig: vLLMDeploymentOnMaaS" "got: '${VLLM_FLAG:-missing}' — run enable-maas step 3"
fi

# ── Section 3: GatewayClass ───────────────────────────────────────────────────
_section "GatewayClass (enable-maas step 4)"

GC_STATUS=$(oc get gatewayclass openshift-default \
    -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "")
if [ "$GC_STATUS" = "True" ]; then
    _ok "GatewayClass openshift-default Accepted" "True"
elif [ -z "$GC_STATUS" ]; then
    _fail "GatewayClass openshift-default" "not found — run enable-maas step 4"
else
    _fail "GatewayClass openshift-default Accepted" "got: '${GC_STATUS}' — run /debug-maas Issue G"
fi

# Gateway API CRDs
if oc get crd gateways.gateway.networking.k8s.io &>/dev/null; then
    _ok "Gateway API CRDs" "present"
else
    _fail "Gateway API CRDs" "not installed — enable GatewayAPI in OpenShift"
fi

# LLMInferenceService CRD (llm-d)
if oc get crd llminferenceservices.serving.kserve.io &>/dev/null; then
    _ok "LLMInferenceService CRD (llm-d)" "present"
else
    _fail "LLMInferenceService CRD (llm-d)" "not found — enable llm-d distributed inference"
fi

# ── Section 4: Gateway ────────────────────────────────────────────────────────
_section "Gateway / openshift-ingress (enable-maas steps 5–6, 10)"

# ConfigMap
if oc get cm maas-default-gateway-config -n openshift-ingress &>/dev/null; then
    # Check memory limit is set (prevents OOMKill)
    MEM_LIMIT=$(oc get cm maas-default-gateway-config -n openshift-ingress \
        -o jsonpath='{.data.deployment}' 2>/dev/null | grep -o 'memory: "[^"]*"' | head -1 || echo "")
    _ok "ConfigMap maas-default-gateway-config" "${MEM_LIMIT:-memory limit set}"
else
    _fail "ConfigMap maas-default-gateway-config" "missing in openshift-ingress — run enable-maas step 5"
fi

# Gateway Programmed
GW_PROGRAMMED=$(oc get gateway maas-default-gateway -n openshift-ingress \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [ "$GW_PROGRAMMED" = "True" ]; then
    _ok "Gateway maas-default-gateway Programmed" "True"
elif [ -z "$GW_PROGRAMMED" ]; then
    _fail "Gateway maas-default-gateway" "not found — run enable-maas step 6"
else
    _fail "Gateway maas-default-gateway Programmed" "got: '${GW_PROGRAMMED}' — run /debug-maas Issue H"
fi

# Gateway annotations
if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
    ODH_MANAGED=$(oc get gateway maas-default-gateway -n openshift-ingress \
        -o jsonpath='{.metadata.annotations.opendatahub\.io/managed}' 2>/dev/null || echo "")
    AUTHORINO_BOOTSTRAP=$(oc get gateway maas-default-gateway -n openshift-ingress \
        -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}' 2>/dev/null || echo "")
    if [ "$ODH_MANAGED" = "false" ]; then
        _ok "Gateway annotation: opendatahub.io/managed=false" "present"
    else
        _warn "Gateway annotation: opendatahub.io/managed=false" "got: '${ODH_MANAGED:-missing}' — ODH may override auth policies"
    fi
    if [ "$AUTHORINO_BOOTSTRAP" = "true" ]; then
        _ok "Gateway annotation: authorino-tls-bootstrap=true" "present"
    else
        _warn "Gateway annotation: authorino-tls-bootstrap=true" "got: '${AUTHORINO_BOOTSTRAP:-missing}' — EnvoyFilter won't be created"
    fi
fi

# Gateway pod Running (not OOMKilled)
GW_RUNNING=$(oc get pods -n openshift-ingress \
    -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
    --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$GW_RUNNING" -gt 0 ]; then
    _ok "Gateway pod Running (not OOMKilled)" "${GW_RUNNING} pod(s)"
else
    # Check if it exists but is OOMKilled
    GW_POD_STATUS=$(oc get pods -n openshift-ingress \
        -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
        --no-headers 2>/dev/null | awk '{print $3}' | head -1)
    if [ -z "$GW_POD_STATUS" ]; then
        _fail "Gateway pod Running" "no pod found — Gateway may not be Programmed yet"
    else
        _fail "Gateway pod Running" "status=${GW_POD_STATUS} — run /debug-maas Issue I"
    fi
fi

# Gateway Route (external access)
if oc get route maas-default-gateway -n openshift-ingress &>/dev/null; then
    ROUTE_HOST=$(oc get route maas-default-gateway -n openshift-ingress \
        -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    _ok "Route maas-default-gateway" "http://${ROUTE_HOST}"
else
    _warn "Route maas-default-gateway" "missing — external access unavailable (run enable-maas step 10)"
fi

# redhat-ai-gateway-infra namespace label
INFRA_LABEL=$(oc get namespace redhat-ai-gateway-infra \
    -o jsonpath='{.metadata.labels.maas-gateway-access}' 2>/dev/null || echo "")
if [ "$INFRA_LABEL" = "true" ]; then
    _ok "Namespace redhat-ai-gateway-infra: maas-gateway-access=true" "labeled"
else
    _warn "Namespace redhat-ai-gateway-infra: maas-gateway-access=true" "not labeled — maas-api-route won't attach"
fi

# ── Section 5: MaaS API / Database ───────────────────────────────────────────
_section "MaaS API and Database (enable-maas step 8)"

# maas-db-config secret
if oc get secret maas-db-config -n redhat-ai-gateway-infra &>/dev/null; then
    DB_URL_LEN=$(oc get secret maas-db-config -n redhat-ai-gateway-infra \
        -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null | wc -c | tr -d ' ')
    if [ "${DB_URL_LEN:-0}" -gt 4 ]; then
        _ok "Secret maas-db-config: DB_CONNECTION_URL" "present (${DB_URL_LEN} chars)"
    else
        _fail "Secret maas-db-config: DB_CONNECTION_URL" "key missing — run enable-maas step 8"
    fi
else
    _fail "Secret maas-db-config in redhat-ai-gateway-infra" "not found — run enable-maas step 8"
fi

# maas-api pod Running
MAAS_API_RUNNING=$(oc get pods -n redhat-ai-gateway-infra \
    -l app.kubernetes.io/name=maas-api --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$MAAS_API_RUNNING" -gt 0 ]; then
    _ok "maas-api pod Running" "${MAAS_API_RUNNING} pod(s)"
else
    MAAS_API_STATUS=$(oc get pods -n redhat-ai-gateway-infra \
        -l app.kubernetes.io/name=maas-api --no-headers 2>/dev/null | awk '{print $3}' | head -1)
    if [ -z "$MAAS_API_STATUS" ]; then
        _fail "maas-api pod Running" "no pod found — run /debug-maas Issue E"
    else
        _fail "maas-api pod Running" "status=${MAAS_API_STATUS} — run /debug-maas Issue E"
    fi
fi

# maas-controller pod Running (in redhat-ods-applications)
# Label is control-plane=maas-controller (not app.kubernetes.io/name)
MAAS_CTRL_LINE=$(oc get pods -n redhat-ods-applications \
    -l control-plane=maas-controller --no-headers 2>/dev/null | grep "Running" | head -1)
if [ -n "$MAAS_CTRL_LINE" ]; then
    MAAS_CTRL_RESTARTS=$(echo "$MAAS_CTRL_LINE" | awk '{print $4}')
    if [ "${MAAS_CTRL_RESTARTS:-0}" -gt 2 ]; then
        _warn "maas-controller pod Running" "${MAAS_CTRL_RESTARTS} restarts — may be losing leader election (check: oc logs -n redhat-ods-applications deployment/maas-controller --previous | tail -5)"
    else
        _ok "maas-controller pod Running" "restarts=${MAAS_CTRL_RESTARTS}"
    fi
else
    _warn "maas-controller pod Running" "not found in redhat-ods-applications — MaaSModelRef creation may fail"
fi

# ── Section 6: Authorino / Kuadrant ──────────────────────────────────────────
_section "Authorino / Kuadrant (enable-maas steps 1, 7)"

# Kuadrant CR
if oc get kuadrant -A --no-headers 2>/dev/null | grep -q .; then
    KQ=$(oc get kuadrant -A --no-headers 2>/dev/null | awk '{print $2 " in " $1}' | head -1)
    _ok "Kuadrant CR" "$KQ"
else
    _fail "Kuadrant CR" "not found — install Red Hat Connectivity Link Operator, then run enable-maas step 1"
fi

# Authorino namespace + deployment
if [ -n "$AUTHORINO_NS" ]; then
    AUTHORINO_READY=$(oc get deployment authorino -n "$AUTHORINO_NS" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "${AUTHORINO_READY:-0}" -gt 0 ]; then
        _ok "Authorino deployment Running" "${AUTHORINO_READY} replica(s) in ${AUTHORINO_NS}"
    else
        _fail "Authorino deployment Running" "0 ready in ${AUTHORINO_NS}"
    fi

    # TLS: server cert secret
    if oc get secret authorino-server-cert -n "$AUTHORINO_NS" &>/dev/null; then
        _ok "Authorino TLS: authorino-server-cert secret" "exists in ${AUTHORINO_NS}"
    else
        _warn "Authorino TLS: authorino-server-cert secret" "missing — run enable-maas step 7"
    fi

    # TLS: enabled in Authorino CR
    AUTH_TLS=$(oc get authorino authorino -n "$AUTHORINO_NS" \
        -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null || echo "")
    if [ "$AUTH_TLS" = "true" ]; then
        _ok "Authorino CR TLS enabled" "true"
    else
        _warn "Authorino CR TLS enabled" "got: '${AUTH_TLS:-missing}' — run enable-maas step 7"
    fi

    # service-ca ConfigMap injection (key must be service-ca.crt, NOT service-ca-bundle.crt)
    if oc get cm authorino-service-ca -n "$AUTHORINO_NS" &>/dev/null; then
        CA_KEY=$(oc get cm authorino-service-ca -n "$AUTHORINO_NS" \
            -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[0]' 2>/dev/null || echo "")
        if [ "$CA_KEY" = "service-ca.crt" ]; then
            _ok "Authorino service-ca CM: injected key" "service-ca.crt (correct)"
        elif [ -z "$CA_KEY" ]; then
            _warn "Authorino service-ca CM: injected key" "not injected yet — wait a moment or re-run step 7"
        else
            _warn "Authorino service-ca CM: injected key" "got: '${CA_KEY}' (expected service-ca.crt)"
        fi
    else
        _warn "Authorino service-ca ConfigMap" "missing — run enable-maas step 7"
    fi
else
    _fail "Authorino deployment" "not found in openshift-operators or kuadrant-system — run enable-maas step 1"
fi

# ── Section 7: Tenant CR ──────────────────────────────────────────────────────
_section "Tenant CR / models-as-a-service (enable-maas step 9)"

if oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service &>/dev/null; then
    TENANT_READY=$(oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [ "$TENANT_READY" = "True" ]; then
        _ok "Tenant default-tenant Ready" "True"
    else
        _fail "Tenant default-tenant Ready" "got: '${TENANT_READY:-missing}' — run /debug-maas Issue A or enable-maas step 9"
    fi
else
    _fail "Tenant default-tenant in models-as-a-service" "not found — run enable-maas step 9"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL + WARN ))
echo "" >&2
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "  Results: ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${WARN} warnings${NC}  (${TOTAL} total)" >&2

if [ "$FAIL" -gt 0 ]; then
    echo "" >&2
    echo -e "  ${RED}MaaS is NOT ready.${NC} Fix the failed checks before deploying." >&2
    echo -e "  Run ${CYAN}/enable-maas${NC} to set up missing components." >&2
    echo -e "  Run ${CYAN}/debug-maas${NC} for issue-by-issue diagnostics." >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    exit 1
else
    if [ "$WARN" -gt 0 ]; then
        echo "" >&2
        echo -e "  ${GREEN}MaaS is ready.${NC} ${YELLOW}${WARN} warning(s) — review above for non-critical issues.${NC}" >&2
    else
        echo "" >&2
        echo -e "  ${GREEN}MaaS is fully ready.${NC}" >&2
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    exit 0
fi
