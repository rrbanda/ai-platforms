#!/usr/bin/env bash
# Enable Models-as-a-Service (MaaS) on OpenShift AI.
#
# Based on real-cluster testing; deviations from official docs are noted below.
# ⚠ Real-cluster deviations from official docs:
#   - maas-db-config secret → redhat-ai-gateway-infra (docs say redhat-ods-applications)
#   - Authorino + Kuadrant  → openshift-operators     (docs say kuadrant-system)
#   - AIGateway enabled via spec.components.aigateway  (not kserve.modelsAsService)
#   - Gateway ConfigMap must set 3Gi memory to prevent OOMKill (not in docs)
#   - Service-CA key is service-ca.crt, not service-ca-bundle.crt (docs are wrong)
#
# Usage:
#   ./enable-maas.sh [OPTIONS]
#
# Options:
#   --apps-domain <domain>    Cluster apps domain (auto-detected if omitted)
#   --tls-secret  <name>      TLS cert secret for HTTPS listener (default: router-certs-default)
#   --authorino-ns <ns>       Override Authorino namespace (default: auto-detect)
#   --db-url <url>            External PostgreSQL URL; omit to deploy internal postgres
#   --db-password <pass>      Password for the internal postgres (required — no default)
#   --postgres-image <image>  Container image for internal postgres (default: docker.io/library/postgres:16-alpine)
#   --step <N>                Run only step N (1-11); useful for retrying individual steps
#   --dry-run                 Print manifests without applying anything
#   --no-wait                 Skip readiness waiting after DSC patch
#   --skip-prereqs            Skip prerequisite checks
#   --auto-create             Auto-create missing prerequisites (Kuadrant CR) without prompting

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $1" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC}      $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}    $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1" >&2; }
log_step()    { echo -e "\n${CYAN}━━━ Step $1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2; }
log_dry()     { echo -e "${YELLOW}[DRY-RUN]${NC} Would apply:" >&2; echo "$1" >&2; }

# ── Defaults ──────────────────────────────────────────────────────────────────
APPS_DOMAIN=""
TLS_SECRET="router-certs-default"
AUTHORINO_NS=""
DB_URL=""
DB_PASSWORD="<user-password>"
POSTGRES_IMAGE="docker.io/library/postgres:16-alpine"
ONLY_STEP=""
DRY_RUN=false
NO_WAIT=false
SKIP_PREREQS=false
AUTO_CREATE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apps-domain)  APPS_DOMAIN="$2";  shift 2 ;;
        --tls-secret)   TLS_SECRET="$2";   shift 2 ;;
        --authorino-ns) AUTHORINO_NS="$2"; shift 2 ;;
        --db-url)         DB_URL="$2";           shift 2 ;;
        --db-password)    DB_PASSWORD="$2";    shift 2 ;;
        --postgres-image) POSTGRES_IMAGE="$2"; shift 2 ;;
        --step)         ONLY_STEP="$2";    shift 2 ;;
        --dry-run)      DRY_RUN=true;      shift ;;
        --no-wait)      NO_WAIT=true;      shift ;;
        --skip-prereqs) SKIP_PREREQS=true; shift ;;
        --auto-create)  AUTO_CREATE=true;  shift ;;
        -h|--help)
            grep "^#" "$0" | head -30 | sed 's/^# \?//'
            exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

_should_run() { [ -z "$ONLY_STEP" ] || [ "$ONLY_STEP" = "$1" ]; }
_apply() {
    if [ "$DRY_RUN" = true ]; then
        log_dry "$1"
    else
        echo "$1" | oc apply -f -
    fi
}
_patch() {
    if [ "$DRY_RUN" = true ]; then
        log_dry "oc $*"
    else
        oc "$@"
    fi
}

# ── Step 0: Detect cluster info ───────────────────────────────────────────────
detect_cluster_info() {
    log_info "Detecting cluster info..."

    if [ -z "$APPS_DOMAIN" ]; then
        APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster \
            -o jsonpath='{.spec.domain}' 2>/dev/null) || {
            log_error "Cannot detect apps domain. Pass --apps-domain <domain>"
            exit 1
        }
        log_info "  Apps domain: $APPS_DOMAIN"
    fi

    MAAS_HOSTNAME="maas.${APPS_DOMAIN}"

    if [ -z "$AUTHORINO_NS" ]; then
        if oc get deployment authorino -n openshift-operators &>/dev/null; then
            AUTHORINO_NS="openshift-operators"
        elif oc get deployment authorino -n kuadrant-system &>/dev/null; then
            AUTHORINO_NS="kuadrant-system"
        else
            log_warning "Authorino not found in openshift-operators or kuadrant-system"
            log_warning "TLS configuration step will be skipped — set --authorino-ns to override"
            AUTHORINO_NS=""
        fi
        [ -n "$AUTHORINO_NS" ] && log_info "  Authorino namespace: $AUTHORINO_NS"
    fi

    log_info "  MaaS hostname: $MAAS_HOSTNAME"
}

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
step_prereqs() {
    log_step "1 — Prerequisites"
    local ERRORS=0

    # OpenShift version >= 4.19
    OCP_VERSION=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion // "unknown"')
    MAJOR=$(echo "$OCP_VERSION" | cut -d. -f1)
    MINOR=$(echo "$OCP_VERSION" | cut -d. -f2)
    if [ "${MAJOR:-0}" -gt 4 ] || { [ "${MAJOR:-0}" -eq 4 ] && [ "${MINOR:-0}" -ge 19 ]; }; then
        log_success "OpenShift $OCP_VERSION (≥ 4.19)"
    else
        log_error "OpenShift $OCP_VERSION — MaaS requires 4.19 or later"
        ((ERRORS++))
    fi

    # RHOAI / DataScienceCluster
    if oc get dsc default-dsc &>/dev/null; then
        RHOAI_VER=$(oc get dsc default-dsc \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | head -c 40 || echo "")
        log_success "DataScienceCluster default-dsc exists"
    else
        log_error "DataScienceCluster default-dsc not found — install RHOAI first"
        ((ERRORS++))
    fi

    # Kuadrant / Connectivity Link operator + CR
    _check_kuadrant() {
        if oc get kuadrant -A --no-headers 2>/dev/null | grep -q .; then
            KQ_NAME=$(oc get kuadrant -A --no-headers 2>/dev/null | awk '{print $2, "(ns: "$1")"}')
            log_success "Kuadrant CR found: $KQ_NAME"
            return 0
        fi

        # Check if the operator itself is present before offering to create the CR
        if ! oc get csv -n openshift-operators --no-headers 2>/dev/null | grep -qiE "kuadrant|rhcl"; then
            log_error "Red Hat Connectivity Link Operator not installed"
            log_error "  Install it from OperatorHub, then re-run"
            return 1
        fi

        log_warning "Kuadrant CR not found — Red Hat Connectivity Link Operator is installed but no CR exists"
        log_warning "  Kuadrant is required: it deploys Authorino, which handles MaaS gateway authentication"
        echo "" >&2

        local DO_CREATE=false
        if [ "$AUTO_CREATE" = true ] || [ "$DRY_RUN" = true ]; then
            DO_CREATE=true
        else
            echo -e "${CYAN}Would you like me to create the Kuadrant CR now?${NC}" >&2
            echo    "  This will create: kuadrant/kuadrant-sample in openshift-operators" >&2
            echo    "  It will deploy: Authorino, Limitador, and the DNS/TLS operators" >&2
            echo    "  (To always auto-create, pass --auto-create)" >&2
            echo -n "  Create it? [y/N]: " >&2
            read -r REPLY </dev/tty
            [[ "$REPLY" =~ ^[Yy]$ ]] && DO_CREATE=true
        fi

        if [ "$DO_CREATE" = true ]; then
            log_info "Creating Kuadrant CR (kuadrant-sample) in openshift-operators..."
            _apply "$(cat <<'KUADRANT_EOF'
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant-sample
  namespace: openshift-operators
spec:
  observability:
    enable: true
KUADRANT_EOF
)"
            if [ "$DRY_RUN" = false ]; then
                log_info "Waiting for Authorino deployment (up to 3 minutes)..."
                for i in $(seq 1 36); do
                    if oc get deployment authorino -n openshift-operators &>/dev/null; then
                        oc rollout status deployment/authorino -n openshift-operators --timeout=60s && break
                    fi
                    sleep 5
                done
                if oc get deployment authorino -n openshift-operators &>/dev/null; then
                    AUTHORINO_NS="openshift-operators"
                    log_success "Authorino is running in openshift-operators"
                else
                    log_warning "Authorino not yet ready — re-run step 1 to recheck once it comes up"
                    return 1
                fi
            fi
            return 0
        else
            echo "" >&2
            log_error "Kuadrant CR is required. Create it manually and re-run:"
            log_error "  cat <<'EOF' | oc apply -f -"
            log_error "  apiVersion: kuadrant.io/v1beta1"
            log_error "  kind: Kuadrant"
            log_error "  metadata:"
            log_error "    name: kuadrant-sample"
            log_error "    namespace: openshift-operators"
            log_error "  spec:"
            log_error "    observability:"
            log_error "      enable: true"
            log_error "  EOF"
            return 1
        fi
    }
    _check_kuadrant || ((ERRORS++))

    # Authorino — hard requirement: MaaS gateway auth depends on it
    # Re-detect after possible Kuadrant CR creation above
    if [ -z "$AUTHORINO_NS" ]; then
        if oc get deployment authorino -n openshift-operators &>/dev/null; then
            AUTHORINO_NS="openshift-operators"
        elif oc get deployment authorino -n kuadrant-system &>/dev/null; then
            AUTHORINO_NS="kuadrant-system"
        fi
    fi

    if [ -n "$AUTHORINO_NS" ]; then
        log_success "Authorino deployment found in: $AUTHORINO_NS"
    else
        log_error "Authorino not found — it is deployed automatically once Kuadrant CR exists"
        log_error "  Check: oc get deployment -A | grep authorino"
        log_error "  Then re-run with: --authorino-ns <namespace>"
        ((ERRORS++))
    fi

    # Gateway API CRDs
    if oc get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        log_success "Gateway API CRDs present"
    else
        log_error "Gateway API CRDs not installed — enable GatewayAPI in OpenShift first"
        ((ERRORS++))
    fi

    # llm-d / distributed inference
    if oc get crd llminferenceservices.serving.kserve.io &>/dev/null; then
        log_success "LLMInferenceService CRD present (llm-d enabled)"
    else
        log_warning "LLMInferenceService CRD not found — enable llm-d distributed inference before deploying models"
    fi

    if [ "$ERRORS" -gt 0 ]; then
        log_error "Prerequisites not met ($ERRORS failure(s)). Fix the above and re-run."
        exit 1
    fi
    log_success "All prerequisites met."
}

# ── Step 2: Enable AIGateway in DSC ──────────────────────────────────────────
step_enable_dsc() {
    log_step "2 — Enable AIGateway + MaaS in DataScienceCluster"

    CURRENT_AIGATEWAY=$(oc get dsc default-dsc \
        -o jsonpath='{.spec.components.aigateway.managementState}' 2>/dev/null || echo "")
    CURRENT_MAAS=$(oc get dsc default-dsc \
        -o jsonpath='{.spec.components.aigateway.modelsAsAService.managementState}' 2>/dev/null || echo "")

    if [ "$CURRENT_AIGATEWAY" = "Managed" ] && [ "$CURRENT_MAAS" = "Managed" ]; then
        log_success "DSC already has aigateway=Managed + modelsAsAService=Managed — skipping patch"
        return
    fi

    log_info "Patching DSC: aigateway → Managed, modelsAsAService → Managed"
    _patch patch dsc default-dsc --type=merge -p '{
      "spec": {
        "components": {
          "aigateway": {
            "managementState": "Managed",
            "modelsAsAService": {
              "managementState": "Managed"
            }
          }
        }
      }
    }'

    log_success "DSC patched."
    log_info "  The RHOAI operator will now reconcile and create/update the AIGateway component."
    log_info "  oc get aigateway default-aigateway -w   # watch status"
}

# ── Step 3: Enable Dashboard feature flags ────────────────────────────────────
step_dashboard_config() {
    log_step "3 — Enable Dashboard feature flags (OdhDashboardConfig)"

    # Check current values
    CURRENT=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
        -o jsonpath='{.spec.dashboardConfig}' 2>/dev/null | jq '{
            modelAsService,genAiStudio,vLLMDeploymentOnMaaS,observabilityDashboard,disableTracking
        }' 2>/dev/null || echo "{}")

    log_info "Current dashboardConfig relevant flags:"
    echo "$CURRENT" | jq . >&2

    log_info "Patching OdhDashboardConfig to enable MaaS + vLLM flags..."
    _patch patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
      "spec": {
        "dashboardConfig": {
          "disableTracking":        false,
          "genAiStudio":            true,
          "modelAsService":         true,
          "observabilityDashboard": true,
          "vLLMDeploymentOnMaaS":   true
        }
      }
    }'

    log_success "Dashboard config updated."
}

# ── Step 4: GatewayClass ──────────────────────────────────────────────────────
step_gatewayclass() {
    log_step "4 — Create GatewayClass (openshift-default)"

    if oc get gatewayclass openshift-default &>/dev/null; then
        STATUS=$(oc get gatewayclass openshift-default \
            -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "Unknown")
        log_success "GatewayClass openshift-default already exists (Accepted=$STATUS) — skipping"
        return
    fi

    log_info "Creating GatewayClass openshift-default..."
    _apply "$(cat <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-default
spec:
  controllerName: openshift.io/gateway-controller/v1
EOF
)"
    log_success "GatewayClass created."

    if [ "$DRY_RUN" = false ]; then
        log_info "Waiting for GatewayClass to be Accepted..."
        for i in $(seq 1 20); do
            STATUS=$(oc get gatewayclass openshift-default \
                -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "")
            [ "$STATUS" = "True" ] && { log_success "GatewayClass Accepted."; return; }
            sleep 3
        done
        log_warning "GatewayClass not yet Accepted after 60s — check Istio configuration"
    fi
}

# ── Step 5: Gateway ConfigMap ─────────────────────────────────────────────────
step_gateway_configmap() {
    log_step "5 — Create maas-default-gateway-config ConfigMap"

    if oc get cm maas-default-gateway-config -n openshift-ingress &>/dev/null; then
        log_success "ConfigMap maas-default-gateway-config already exists — skipping"
        log_info "  To update memory limits: oc patch cm maas-default-gateway-config -n openshift-ingress --type=merge -p '{...}'"
        return
    fi

    log_info "Creating maas-default-gateway-config (with 3Gi memory limit to prevent OOMKill)..."
    _apply "$(cat <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: maas-default-gateway-config
  namespace: openshift-ingress
  labels:
    app.kubernetes.io/component: gateway
    app.kubernetes.io/name: maas
data:
  service: |
    metadata:
      annotations:
        service.beta.openshift.io/serving-cert-secret-name: "maas-default-gateway-service-tls"
    spec:
      type: ClusterIP
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests:
                cpu: "100m"
                memory: "512Mi"
              limits:
                cpu: "2"
                memory: "3Gi"
EOF
)"
    log_success "ConfigMap created."
    log_info "  Memory set to 3Gi to prevent Kuadrant Wasm filter OOMKill (see /debug-maas Issue I)"
}

# ── Step 6: Gateway ────────────────────────────────────────────────────────────
step_gateway() {
    log_step "6 — Create Gateway (maas-default-gateway in openshift-ingress)"

    if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
        STATUS=$(oc get gateway maas-default-gateway -n openshift-ingress \
            -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "Unknown")
        log_success "Gateway maas-default-gateway already exists (Programmed=$STATUS) — skipping"
        log_info "  Required annotations must be present:"
        oc get gateway maas-default-gateway -n openshift-ingress \
            -o jsonpath='{.metadata.annotations}' 2>/dev/null | jq '{
                "opendatahub.io/managed": .["opendatahub.io/managed"],
                "security.opendatahub.io/authorino-tls-bootstrap": .["security.opendatahub.io/authorino-tls-bootstrap"]
            }' >&2 || true
        return
    fi

    log_info "Creating Gateway maas-default-gateway (hostname: $MAAS_HOSTNAME)..."
    _apply "$(cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
  annotations:
    opendatahub.io/managed: "false"
    security.opendatahub.io/authorino-tls-bootstrap: "true"
  labels:
    app.kubernetes.io/component: gateway
    app.kubernetes.io/instance: maas-default-gateway
    app.kubernetes.io/name: maas
    opendatahub.io/managed: "false"
    security.opendatahub.io/authorino-tls-bootstrap: "true"
spec:
  gatewayClassName: openshift-default
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: maas-default-gateway-config
  listeners:
  - name: http
    hostname: "${MAAS_HOSTNAME}"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            maas-gateway-access: "true"
  - name: https
    hostname: "${MAAS_HOSTNAME}"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - group: ""
        kind: Secret
        name: ${TLS_SECRET}
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            maas-gateway-access: "true"
EOF
)"
    log_success "Gateway created."

    if [ "$DRY_RUN" = false ]; then
        log_info "Waiting for Gateway to be Programmed (Istio provisions Deployment + Service)..."
        for i in $(seq 1 30); do
            STATUS=$(oc get gateway maas-default-gateway -n openshift-ingress \
                -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
            [ "$STATUS" = "True" ] && { log_success "Gateway Programmed."; return; }
            sleep 5
        done
        log_warning "Gateway not Programmed after 150s."
        log_warning "  Likely cause: maas-default-gateway-config ConfigMap missing (run step 5 first)"
        log_warning "  Debug: /debug-maas Issue H"
    fi
}

# ── Step 7: Authorino TLS ──────────────────────────────────────────────────────
step_authorino_tls() {
    log_step "7 — Configure Authorino TLS"

    if [ -z "$AUTHORINO_NS" ]; then
        log_error "Authorino namespace is not set — cannot configure TLS"
        log_error "  Authorino is required for MaaS authentication. Install Red Hat Connectivity Link Operator first."
        log_error "  Find it with: oc get deployment -A | grep authorino"
        log_error "  Then re-run: --step 7 --authorino-ns <namespace>"
        exit 1
    fi

    # 7a. Annotate the Authorino authorization service to trigger cert generation
    log_info "Annotating authorino-authorino-authorization service (serving cert → authorino-server-cert)..."
    if [ "$DRY_RUN" = true ]; then
        log_dry "oc annotate service authorino-authorino-authorization -n $AUTHORINO_NS service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert --overwrite"
    else
        oc annotate service authorino-authorino-authorization \
            -n "$AUTHORINO_NS" \
            service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
            --overwrite
    fi

    # 7b. Patch Authorino CR to enable TLS listener
    log_info "Patching Authorino CR to enable TLS listener (cert: authorino-server-cert)..."
    _patch patch authorino authorino -n "$AUTHORINO_NS" --type=merge -p '{
      "spec": {
        "listener": {
          "tls": {
            "enabled": true,
            "certSecretRef": {
              "name": "authorino-server-cert"
            }
          }
        }
      }
    }'

    # 7c. Inject service-ca ConfigMap (if not already present) for CA bundle
    log_info "Ensuring service-ca ConfigMap is available for TLS validation..."
    if ! oc get cm authorino-service-ca -n "$AUTHORINO_NS" &>/dev/null; then
        _apply "$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: authorino-service-ca
  namespace: ${AUTHORINO_NS}
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF
)"
        log_info "  Created authorino-service-ca CM — OpenShift will inject service-ca.crt into it"
    else
        log_success "  authorino-service-ca CM already exists"
    fi

    # 7d. Wait for cert secret to appear
    if [ "$DRY_RUN" = false ]; then
        log_info "Waiting for authorino-server-cert secret..."
        for i in $(seq 1 20); do
            oc get secret authorino-server-cert -n "$AUTHORINO_NS" &>/dev/null && break
            sleep 3
        done
        if ! oc get secret authorino-server-cert -n "$AUTHORINO_NS" &>/dev/null; then
            log_warning "authorino-server-cert not generated yet. The service-ca-operator may take a moment."
            log_warning "  Check: oc get secret authorino-server-cert -n $AUTHORINO_NS"
        else
            log_success "authorino-server-cert secret exists."
        fi

        # Wait for the injected CA key to appear
        log_info "Waiting for service-ca injection into authorino-service-ca CM..."
        for i in $(seq 1 20); do
            KEY=$(oc get cm authorino-service-ca -n "$AUTHORINO_NS" \
                -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[0]' 2>/dev/null || echo "")
            [ -n "$KEY" ] && [ "$KEY" != "null" ] && break
            sleep 3
        done
        CA_KEY=$(oc get cm authorino-service-ca -n "$AUTHORINO_NS" \
            -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[0]' 2>/dev/null || echo "service-ca.crt")
        log_info "  Injected CA key: $CA_KEY"
    else
        CA_KEY="service-ca.crt"
    fi

    # 7e. Patch Authorino deployment with CA volume + env vars
    log_info "Patching Authorino deployment with CA volume mount and TLS env vars..."
    CA_MOUNT_PATH="/etc/ssl/certs/openshift-service-ca"
    CA_CERT_PATH="${CA_MOUNT_PATH}/${CA_KEY:-service-ca.crt}"

    _patch -n "$AUTHORINO_NS" set env deployment/authorino \
        SSL_CERT_FILE="$CA_CERT_PATH" \
        REQUESTS_CA_BUNDLE="$CA_CERT_PATH"

    # Only add the volume mount if not already present
    if [ "$DRY_RUN" = false ]; then
        EXISTING_VOL=$(oc get deployment authorino -n "$AUTHORINO_NS" \
            -o json 2>/dev/null | jq -r '.spec.template.spec.volumes[] | select(.name=="service-ca") | .name' 2>/dev/null || echo "")
        if [ -z "$EXISTING_VOL" ]; then
            oc patch deployment authorino -n "$AUTHORINO_NS" --type=json -p="$(cat <<EOF
[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "service-ca",
      "configMap": { "name": "authorino-service-ca" }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "service-ca",
      "mountPath": "${CA_MOUNT_PATH}",
      "readOnly": true
    }
  }
]
EOF
)"
        else
            log_success "  service-ca volume already mounted in Authorino deployment"
        fi
    fi

    # 7f. Annotate Gateway for TLS bootstrap
    log_info "Annotating Gateway maas-default-gateway for Authorino TLS bootstrap..."
    if [ "$DRY_RUN" = true ]; then
        log_dry "oc annotate gateway maas-default-gateway -n openshift-ingress security.opendatahub.io/authorino-tls-bootstrap=true --overwrite"
    else
        oc annotate gateway maas-default-gateway -n openshift-ingress \
            security.opendatahub.io/authorino-tls-bootstrap="true" \
            --overwrite 2>/dev/null || log_warning "Gateway not found yet — run step 6 first"
    fi

    log_success "Authorino TLS configured."
    log_info "  The MaaS controller will create an EnvoyFilter in openshift-ingress to enforce TLS to Authorino."
}

# ── Step 8: PostgreSQL + DB secret ────────────────────────────────────────────
step_postgres() {
    log_step "8 — Deploy PostgreSQL and maas-db-config secret (redhat-ai-gateway-infra)"

    DB_NS="redhat-ai-gateway-infra"

    # Ensure namespace exists and is labeled for MaaS gateway access
    if ! oc get namespace "$DB_NS" &>/dev/null; then
        log_info "Creating namespace $DB_NS..."
        _patch create namespace "$DB_NS" || true
    fi
    if [ "$DRY_RUN" = false ]; then
        oc label namespace "$DB_NS" maas-gateway-access=true --overwrite &>/dev/null \
            && log_info "Namespace $DB_NS labeled with maas-gateway-access=true (required for maas-api-route)"
    fi

    if [ -n "$DB_URL" ]; then
        # Use external DB — only create the secret
        log_info "Using external PostgreSQL: $DB_URL"
        if oc get secret maas-db-config -n "$DB_NS" &>/dev/null; then
            log_success "maas-db-config secret already exists in $DB_NS — skipping"
        else
            if [ "$DRY_RUN" = true ]; then
                log_dry "oc create secret generic maas-db-config -n $DB_NS --from-literal=DB_CONNECTION_URL='<provided>'"
            else
                oc create secret generic maas-db-config \
                    -n "$DB_NS" \
                    --from-literal="DB_CONNECTION_URL=${DB_URL}"
                log_success "maas-db-config secret created in $DB_NS"
            fi
        fi
        return
    fi

    # Deploy internal postgres (using the provided quay image)
    if oc get deployment maas-postgres-deployment -n "$DB_NS" &>/dev/null; then
        log_success "maas-postgres-deployment already exists in $DB_NS — skipping"
    else
        log_info "Deploying internal PostgreSQL (${POSTGRES_IMAGE})..."
        _apply "$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: maas-db-config
  namespace: ${DB_NS}
  labels:
    app: maas-postgres
type: Opaque
stringData:
  POSTGRES_HOST: maas-postgres-service
  POSTGRES_PORT: "5432"
  POSTGRES_DB: maas
  POSTGRES_USER: maas
  POSTGRES_PASSWORD: "${DB_PASSWORD}"
  DB_CONNECTION_URL: "postgresql://maas:${DB_PASSWORD}@maas-postgres-service:5432/maas"
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: maas-postgres-pvc
  namespace: ${DB_NS}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  volumeMode: Filesystem
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: maas-postgres-deployment
  namespace: ${DB_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: maas-postgres
  template:
    metadata:
      labels:
        app: maas-postgres
    spec:
      containers:
      - name: postgres
        image: ${POSTGRES_IMAGE}
        env:
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: maas-db-config
              key: POSTGRES_DB
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: maas-db-config
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: maas-db-config
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: maas-postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: maas-postgres-storage
        persistentVolumeClaim:
          claimName: maas-postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: maas-postgres-service
  namespace: ${DB_NS}
spec:
  selector:
    app: maas-postgres
  ports:
  - protocol: TCP
    port: 5432
    targetPort: 5432
EOF
)"
        log_success "PostgreSQL deployed."
    fi

    if [ "$DRY_RUN" = false ]; then
        log_info "Waiting for postgres pod to be Running..."
        oc rollout status deployment/maas-postgres-deployment -n "$DB_NS" --timeout=120s || \
            log_warning "Postgres not ready — check: oc get pods -n $DB_NS -l app=maas-postgres"

        # Restart maas-api so it picks up the secret (only if already deployed)
        if oc get deployment maas-api -n "$DB_NS" &>/dev/null; then
            log_info "Restarting maas-api to pick up maas-db-config..."
            oc rollout restart deployment/maas-api -n "$DB_NS"
            oc rollout status deployment/maas-api -n "$DB_NS" --timeout=120s || \
                log_warning "maas-api not ready — check: oc logs -n $DB_NS deployment/maas-api"
        fi
    fi

    log_success "DB secret (maas-db-config) ready in $DB_NS"
    log_info "  ⚠ Note: official docs say redhat-ods-applications — the correct namespace is redhat-ai-gateway-infra"
}

# ── Step 9: Tenant CR ────────────────────────────────────────────────────────
step_tenant() {
    log_step "9 — Create Tenant CR"
    # The Tenant CR must exist BEFORE models are deployed.
    # Without it, llmisvc-controller skips reconcileMonitoring and never creates MaaSModelRef.

    if oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service &>/dev/null; then
        log_info "Tenant 'default-tenant' already exists — skipping"
    elif [ "$DRY_RUN" = true ]; then
        log_info "[dry-run] Would create Tenant default-tenant in models-as-a-service"
    else
        cat <<'TENANT_EOF' | oc apply -f -
apiVersion: maas.opendatahub.io/v1alpha1
kind: Tenant
metadata:
  name: default-tenant
  namespace: models-as-a-service
spec:
  telemetry:
    enabled: true
    metrics:
      captureGroup: false
      captureModelUsage: true
      captureOrganization: true
      captureUser: false
TENANT_EOF
        log_success "Tenant created"
    fi

    # No controller auto-sets Tenant status on AITenant-managed clusters — patch it manually
    TENANT_READY=$(oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [ "$TENANT_READY" != "True" ] && [ "$DRY_RUN" != true ]; then
        log_info "Patching Tenant status to Ready..."
        oc patch tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
            --type=merge --subresource=status \
            -p "{\"status\":{\"conditions\":[{\"lastTransitionTime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"message\":\"MaaS platform manifests applied and maas-api deployment is available\",\"observedGeneration\":1,\"reason\":\"Reconciled\",\"status\":\"True\",\"type\":\"Ready\"}]}}" \
            &>/dev/null && log_success "Tenant status set to Ready"
    fi
}

# ── Step 10: Gateway Route ───────────────────────────────────────────────────
step_gateway_route() {
    log_step "10 — Create Gateway Route"
    # The gateway Service is ClusterIP — an OpenShift Route is required for external access.

    if oc get route maas-default-gateway -n openshift-ingress &>/dev/null; then
        log_info "Route 'maas-default-gateway' already exists — skipping"
    elif [ "$DRY_RUN" = true ]; then
        log_info "[dry-run] Would create Route maas-default-gateway → maas-default-gateway-openshift-default:http"
    else
        cat <<ROUTE_EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
  labels:
    app.kubernetes.io/component: gateway
    app.kubernetes.io/name: maas
spec:
  host: ${MAAS_HOSTNAME}
  port:
    targetPort: http
  to:
    kind: Service
    name: maas-default-gateway-openshift-default
    weight: 100
  wildcardPolicy: None
ROUTE_EOF
        log_success "Route created: http://${MAAS_HOSTNAME}"
    fi
}

# ── Step 11: Wait for readiness ────────────────────────────────────────────────
step_wait() {
    log_step "11 — Wait for MaaS readiness"

    if [ "$NO_WAIT" = true ] || [ "$DRY_RUN" = true ]; then
        log_info "Skipping wait (--no-wait or --dry-run)"
        return
    fi

    log_info "Waiting for ModelsAsAServiceReady in DSC (up to 5 minutes)..."
    for i in $(seq 1 60); do
        STATUS=$(oc get dsc default-dsc \
            -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].status}' 2>/dev/null || echo "")
        [ "$STATUS" = "True" ] && { log_success "DSC ModelsAsAServiceReady: True"; break; }
        if [ "$i" -eq 30 ]; then
            log_warning "Still waiting after 2.5 minutes..."
            log_warning "  Check: oc get dsc default-dsc -o jsonpath='{.status.conditions}' | jq ."
        fi
        sleep 5
    done

    if [ "$STATUS" != "True" ]; then
        log_warning "ModelsAsAServiceReady not reached. Common fix:"
        log_warning "  oc patch tenant default-tenant -n models-as-a-service --subresource=status --type=merge \\"
        log_warning "    -p '{\"status\":{\"conditions\":[{\"type\":\"Ready\",\"status\":\"True\",\"reason\":\"Reconciled\",\"message\":\"MaaS platform ready\",\"lastTransitionTime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"observedGeneration\":1}]}}'"
        log_warning "  See /debug-maas Issue A"
    fi
}

# ── Step 10: Verify ────────────────────────────────────────────────────────────
step_verify() {
    log_step "Final — Verification"

    echo "" >&2
    printf "%-55s %s\n" "Check" "Status" >&2
    printf "%-55s %s\n" "─────────────────────────────────────────────────────" "────────" >&2

    _check() {
        local LABEL="$1"; local CMD="$2"; local EXPECT="$3"
        local ACTUAL; ACTUAL=$(eval "$CMD" 2>/dev/null || echo "ERROR")
        if [ "$ACTUAL" = "$EXPECT" ]; then
            printf "%-55s ${GREEN}%s${NC}\n" "$LABEL" "✓ $ACTUAL" >&2
        else
            printf "%-55s ${RED}%s${NC}\n" "$LABEL" "✗ got: ${ACTUAL:-missing}" >&2
        fi
    }

    _check "DSC ModelsAsAServiceReady" \
        "oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type==\"ModelsAsAServiceReady\")].status}'" \
        "True"

    _check "AIGateway ModelsAsAServiceReady" \
        "oc get aigateway default-aigateway -o jsonpath='{.status.conditions[?(@.type==\"ModelsAsAServiceReady\")].status}'" \
        "True"

    _check "GatewayClass openshift-default Accepted" \
        "oc get gatewayclass openshift-default -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}'" \
        "True"

    _check "Gateway maas-default-gateway Programmed" \
        "oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type==\"Programmed\")].status}'" \
        "True"

    _check "maas-db-config secret present" \
        "oc get secret maas-db-config -n redhat-ai-gateway-infra -o jsonpath='{.metadata.name}'" \
        "maas-db-config"

    # DB_CONNECTION_URL: just check the key is present and non-empty
    DB_URL_LEN=$(oc get secret maas-db-config -n redhat-ai-gateway-infra \
        -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null | wc -c | tr -d ' ')
    if [ "${DB_URL_LEN:-0}" -gt 4 ]; then
        printf "%-55s ${GREEN}%s${NC}\n" "maas-db-config has DB_CONNECTION_URL" "✓ key present (${DB_URL_LEN} chars)" >&2
    else
        printf "%-55s ${RED}%s${NC}\n" "maas-db-config has DB_CONNECTION_URL" "✗ missing or empty" >&2
    fi

    # maas-api
    MAAS_API_RUNNING=$(oc get pods -n redhat-ai-gateway-infra \
        -l app.kubernetes.io/name=maas-api --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [ "$MAAS_API_RUNNING" -gt 0 ]; then
        printf "%-55s ${GREEN}%s${NC}\n" "maas-api pod Running" "✓ $MAAS_API_RUNNING pod(s)" >&2
    else
        printf "%-55s ${RED}%s${NC}\n" "maas-api pod Running" "✗ none Running" >&2
    fi

    # Gateway pod
    GW_POD=$(oc get pods -n openshift-ingress \
        -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
        --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [ "$GW_POD" -gt 0 ]; then
        printf "%-55s ${GREEN}%s${NC}\n" "Gateway pod Running (not OOMKilled)" "✓ $GW_POD pod(s)" >&2
    else
        printf "%-55s ${YELLOW}%s${NC}\n" "Gateway pod Running (not OOMKilled)" "⚡ not yet (may take a moment)" >&2
    fi

    # Authorino TLS
    if [ -n "$AUTHORINO_NS" ]; then
        _check "authorino-server-cert secret exists" \
            "oc get secret authorino-server-cert -n $AUTHORINO_NS -o jsonpath='{.metadata.name}'" \
            "authorino-server-cert"
        _check "Authorino CR TLS enabled" \
            "oc get authorino authorino -n $AUTHORINO_NS -o jsonpath='{.spec.listener.tls.enabled}'" \
            "true"
    fi

    # Dashboard flags
    MAAS_FLAG=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
        -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null || echo "")
    VLLM_FLAG=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
        -o jsonpath='{.spec.dashboardConfig.vLLMDeploymentOnMaaS}' 2>/dev/null || echo "")
    if [ "$MAAS_FLAG" = "true" ] && [ "$VLLM_FLAG" = "true" ]; then
        printf "%-55s ${GREEN}%s${NC}\n" "Dashboard: modelAsService + vLLMDeploymentOnMaaS" "✓ both true" >&2
    else
        printf "%-55s ${RED}%s${NC}\n" "Dashboard: modelAsService + vLLMDeploymentOnMaaS" "✗ modelAsService=$MAAS_FLAG vLLMDeploymentOnMaaS=$VLLM_FLAG" >&2
    fi

    echo "" >&2
    log_info "MaaS hostname: http://${MAAS_HOSTNAME}/maas-api/v1/models   (use Bearer API key)"
    log_info "Next step: /deploy-maas-model to deploy a model"
    log_info "If checks failed: /debug-maas for issue-by-issue fixes"
}

# ── Main ──────────────────────────────────────────────────────────────────────
detect_cluster_info

if _should_run 1; then $SKIP_PREREQS && log_info "Skipping prerequisites (--skip-prereqs)" || step_prereqs; fi
_should_run 2 && step_enable_dsc
_should_run 3 && step_dashboard_config
_should_run 4 && step_gatewayclass
_should_run 5 && step_gateway_configmap
_should_run 6 && step_gateway
_should_run 7 && step_authorino_tls
_should_run 8 && step_postgres
_should_run 9 && step_tenant
_should_run 10 && step_gateway_route
_should_run 11 && step_wait
[ -z "$ONLY_STEP" ] && step_verify
