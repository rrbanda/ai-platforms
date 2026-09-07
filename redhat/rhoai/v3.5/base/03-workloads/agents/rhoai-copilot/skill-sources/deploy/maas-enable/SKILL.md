---
name: enable-maas
description: "Enable Models-as-a-Service (MaaS) on a fresh OpenShift AI cluster — patches DSC, creates GatewayClass/Gateway, configures Authorino TLS, deploys PostgreSQL, and verifies readiness."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, MaaS, DSC, Gateway, Kuadrant, Authorino, PostgreSQL, Enable, Setup]
---

# Enable Models-as-a-Service (MaaS)

Full setup of MaaS on an OpenShift AI cluster. Run this **once** on a fresh cluster before using `/deploy-maas-model`.

## Trigger Conditions

- "Enable MaaS on my cluster"
- "Set up Models-as-a-Service"
- "Configure the MaaS gateway"
- "Patch DSC to enable AIGateway"
- "Set up Kuadrant and Authorino for MaaS"
- "Prepare the cluster for model-as-a-service deployments"
- "How do I enable MaaS on OpenShift AI?"
- User has a fresh RHOAI cluster and wants to enable the MaaS stack
- User needs to configure GatewayClass, Gateway, Authorino TLS, or PostgreSQL for MaaS

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `cluster_summary` | Overall cluster and RHOAI component status |
| mcp_rhoai | `explore_cluster` | Discover installed operators and CRDs |
| mcp_rhoai | `diagnose_resource` | Debug failing DSC components or pods |
| mcp_rhoai | `get_cluster_resources` | Verify node capacity and readiness |
| mcp_openshift | `pods_list` | Check operator, gateway, and maas-api pod health |
| mcp_openshift | `events_list` | Surface issues during setup (TLS, scheduling) |
| mcp_argocd | `get_application` | Verify GitOps sync for managed infrastructure |

## Automation Script

All steps are automated by a single script:

```bash
cd ~/.claude/skills/enable-maas

# Full setup — auto-detects apps domain and Authorino namespace
./enable-maas.sh

# Preview all manifests without applying
./enable-maas.sh --dry-run

# External PostgreSQL instead of internal
./enable-maas.sh --db-url 'postgresql://user:pass@host:5432/maas'

# Retry a single step (e.g., after fixing a prerequisite)
./enable-maas.sh --step 6   # re-run Gateway creation only

# Override auto-detected values
./enable-maas.sh --apps-domain apps.mycluster.example.com \
                 --tls-secret my-wildcard-cert \
                 --authorino-ns kuadrant-system
```

**Options:**

| Flag | Default | Description |
|---|---|---|
| `--apps-domain <domain>` | auto-detected | Cluster wildcard domain |
| `--tls-secret <name>` | `router-certs-default` | TLS cert secret in `openshift-ingress` |
| `--authorino-ns <ns>` | auto-detected | Namespace where Authorino is deployed |
| `--db-url <url>` | *(deploys internal postgres)* | Use external PostgreSQL |
| `--db-password <pass>` | `P@ssw0rd123!` | Password for internal postgres |
| `--step <1-11>` | *(all)* | Run only one step |
| `--dry-run` | false | Print manifests, don't apply |
| `--no-wait` | false | Skip waiting for readiness |
| `--skip-prereqs` | false | Skip step 1 prerequisite checks |
| `--auto-create` | false | Auto-create missing prerequisites (Kuadrant CR) without prompting |

---

## Real-Cluster Deviations from Official Docs

> Official docs describe a "clean" reference setup. The following are confirmed discrepancies
> based on the working configuration on `ai-eng-prod`.

| What the docs say | What actually works |
|---|---|
| `maas-db-config` secret → `redhat-ods-applications` | Secret must be in **`redhat-ai-gateway-infra`** |
| Authorino + Kuadrant in `kuadrant-system` | They live in **`openshift-operators`** |
| Enable via `kserve.modelsAsService` | Enable via **`spec.components.aigateway`** in DSC |
| Gateway ConfigMap: only `service:` key | Must also set **3Gi memory in `deployment:` key** (prevents OOMKill) |
| Authorino CA bundle path: `service-ca-bundle.crt` | Injected key is **`service-ca.crt`** |
| No `Tenant` CR mentioned | Must create **`tenants.maas.opendatahub.io`** CR in `models-as-a-service` — without it the `llmisvc-controller` never creates `MaaSModelRef` |
| No Route mentioned | Must create an OpenShift **Route** in `openshift-ingress` pointing to the gateway service — gateway service is ClusterIP, not externally reachable otherwise |

---

## Namespace Reference

| Resource | Namespace |
|---|---|
| DataScienceCluster, OdhDashboardConfig | `redhat-ods-applications` |
| AIGateway CR (auto-created by DSC) | cluster-scoped |
| GatewayClass `openshift-default` | cluster-scoped |
| Gateway `maas-default-gateway`, ConfigMap | `openshift-ingress` |
| Authorino CR + deployment | `openshift-operators` *(or kuadrant-system — auto-detected)* |
| Kuadrant CR | `openshift-operators` *(named `kuadrant-sample`)* |
| `maas-db-config` secret, `maas-api` | **`redhat-ai-gateway-infra`** |
| `maas-controller`, `modelsasservice` | `redhat-ods-applications` |
| MaaSSubscription, MaaSAuthPolicy | `models-as-a-service` |

---

## Step-by-Step Reference

### Step 1 — Prerequisites

Before enabling MaaS, these must exist:

| Requirement | Check |
|---|---|
| OpenShift ≥ 4.19 | `oc version` |
| RHOAI ≥ 3.4 installed | `oc get dsc default-dsc` |
| Red Hat Connectivity Link Operator | `oc get kuadrant -A` |
| Kuadrant CR with ready status | `oc get kuadrant -A -o jsonpath='{.items[0].status.conditions}'` |
| Gateway API CRDs | `oc get crd gateways.gateway.networking.k8s.io` |
| llm-d distributed inference enabled | `oc get crd llminferenceservices.serving.kserve.io` |

```bash
# Quick prerequisite check
oc version -o json | jq -r '"OCP: " + .openshiftVersion'
oc get dsc default-dsc -o jsonpath='{.status.phase}' && echo
oc get kuadrant -A --no-headers | awk '{print "Kuadrant:", $2, "in", $1}'
```

---

### Step 2 — Enable AIGateway in DataScienceCluster

```bash
oc patch dsc default-dsc --type=merge -p '{
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
```

After patching, the RHOAI operator creates the `AIGateway` CR (`default-aigateway`) and begins reconciling. This may take a few minutes.

```bash
# Watch AIGateway status
oc get aigateway default-aigateway -o jsonpath='{.status.conditions}' | jq .
# Expect: ModelsAsAServiceReady=True, DeploymentsAvailable=True
```

> **vLLM on MaaS is a Technology Preview.** Ensure `vLLMDeploymentOnMaaS: true` is set (Step 3).

---

### Step 3 — Enable Dashboard Feature Flags

```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
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
```

---

### Step 4 — GatewayClass

```bash
cat <<'EOF' | oc apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-default
spec:
  controllerName: openshift.io/gateway-controller/v1
EOF

# Verify Istio accepts it (takes ~5s)
oc get gatewayclass openshift-default -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'
# Expected: True
```

> **Why it's needed:** Istio is configured with `PILOT_GATEWAY_API_DEFAULT_GATEWAYCLASS_NAME: openshift-default`
> but `PILOT_ENABLE_GATEWAY_API_GATEWAYCLASS_CONTROLLER: false` — Istio watches this class name but
> intentionally does NOT auto-create it. It must be created manually.

---

### Step 5 — Gateway ConfigMap (with memory limits)

```bash
# IMPORTANT: Include the deployment.memory limits here.
# Without 3Gi, the gateway pod OOMKills when loading Kuadrant Wasm filters.
# See: /debug-maas Issue I
cat <<'EOF' | oc apply -f -
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
```

If the gateway pod OOMKills later, patch this ConfigMap and restart the deployment:
```bash
# See /debug-maas Issue I for the full fix procedure
```

---

### Step 6 — Gateway

Replace `<APPS_DOMAIN>` with your cluster's domain (`oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'`).

```bash
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')

cat <<EOF | oc apply -f -
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
spec:
  gatewayClassName: openshift-default
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: maas-default-gateway-config
  listeners:
  - name: http
    hostname: "maas.\${APPS_DOMAIN}"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            maas-gateway-access: "true"
  - name: https
    hostname: "maas.\${APPS_DOMAIN}"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - group: ""
        kind: Secret
        name: router-certs-default
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            maas-gateway-access: "true"
EOF

# Wait for Istio to provision the Deployment + Service (~10s)
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# Expected: True
```

**Required annotations:**

| Annotation | Value | Effect |
|---|---|---|
| `opendatahub.io/managed: "false"` | `"false"` | Prevents ODH Model Controller from overriding MaaS auth policies |
| `security.opendatahub.io/authorino-tls-bootstrap: "true"` | `"true"` | MaaS controller creates EnvoyFilter for Authorino TLS |

> **Security:** The gateway uses `allowedRoutes.namespaces.from: Selector` — only namespaces labeled `maas-gateway-access=true` can attach HTTPRoutes. Two namespaces **must always** be labeled or the gateway breaks:
> - `redhat-ai-gateway-infra` — contains `maas-api-route` (API key management, model listing)
> - `<model-namespace>` (e.g. `ai-eng-cracow`) — contains model HTTPRoutes; labeled automatically by `deploy-llm.sh`
>
> `enable-maas.sh` Step 8 labels `redhat-ai-gateway-infra` automatically. For manual setup: `oc label namespace redhat-ai-gateway-infra maas-gateway-access=true`

---

### Step 7 — Authorino TLS

> **Namespace:** Authorino runs in `openshift-operators` on this cluster (docs say `kuadrant-system`).

```bash
AUTHORINO_NS="openshift-operators"  # or kuadrant-system — check: oc get deployment -A | grep authorino

# 7a. Trigger cert generation
oc annotate service authorino-authorino-authorization \
  -n $AUTHORINO_NS \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  --overwrite

# 7b. Enable TLS listener in Authorino CR
oc patch authorino authorino -n $AUTHORINO_NS --type=merge -p '{
  "spec": {
    "listener": {
      "tls": {
        "enabled": true,
        "certSecretRef": { "name": "authorino-server-cert" }
      }
    }
  }
}'

# 7c. Create an auto-injected service-CA ConfigMap
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: authorino-service-ca
  namespace: ${AUTHORINO_NS}
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF

# Wait for injection (the key is service-ca.crt — not service-ca-bundle.crt as docs say)
oc get cm authorino-service-ca -n $AUTHORINO_NS -o jsonpath='{.data}' | jq 'keys'
# Expected: ["service-ca.crt"]

# 7d. Set CA env vars and mount the bundle
oc -n $AUTHORINO_NS set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca.crt

oc patch deployment authorino -n $AUTHORINO_NS --type=json -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-",
   "value":{"name":"service-ca","configMap":{"name":"authorino-service-ca"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-",
   "value":{"name":"service-ca","mountPath":"/etc/ssl/certs/openshift-service-ca","readOnly":true}}
]'

# 7e. Annotate Gateway (if not already done in Step 6)
oc annotate gateway maas-default-gateway -n openshift-ingress \
  security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite

# Verify
oc get secret authorino-server-cert -n $AUTHORINO_NS
oc get authorino authorino -n $AUTHORINO_NS -o jsonpath='{.spec.listener.tls.enabled}'
# Expected: true
```

---

### Step 8 — PostgreSQL and DB Secret

> **⚠ Namespace:** `redhat-ai-gateway-infra` — NOT `redhat-ods-applications` as the docs state.

```bash
# Option A: Deploy internal PostgreSQL (uses quay.io/rh-ee-msteczko/postgres:16-alpine)
oc apply -f /Users/msteczko/nightly/ogx_defs/maas_postgres.yaml

# Verify postgres is running
oc rollout status deployment/maas-postgres-deployment -n redhat-ai-gateway-infra
oc get secret maas-db-config -n redhat-ai-gateway-infra \
  -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d && echo
```

```bash
# Option B: External PostgreSQL
oc create secret generic maas-db-config \
  -n redhat-ai-gateway-infra \
  --from-literal=DB_CONNECTION_URL='postgresql://<user>:<pass>@<host>:5432/<db>?sslmode=require'
```

If `maas-api` is already deployed, restart it to pick up the secret:
```bash
oc rollout restart deployment/maas-api -n redhat-ai-gateway-infra
oc rollout status deployment/maas-api -n redhat-ai-gateway-infra
```

---

### Step 9 — Tenant CR

The `Tenant` CR (`tenants.maas.opendatahub.io`) must exist in `models-as-a-service` **before any models are deployed**. Without it, the `llmisvc-controller` skips the `reconcileMonitoring` phase and never creates `MaaSModelRef` objects for newly deployed `LLMInferenceService` resources.

> **Note:** For AITenant-managed clusters, `externalOIDC` and `gatewayRef` fields are ignored — use telemetry-only spec.

```bash
cat <<'EOF' | oc apply -f -
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
EOF

# Patch status to Ready (no controller auto-sets it on AITenant-managed clusters)
oc patch tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
  --type=merge --subresource=status \
  -p '{"status":{"conditions":[{"lastTransitionTime":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","message":"MaaS platform manifests applied and maas-api deployment is available","observedGeneration":1,"reason":"Reconciled","status":"True","type":"Ready"}]}}'
```

Verify:
```bash
oc get tenants.maas.opendatahub.io -n models-as-a-service
# Expected: READY=True
```

---

### Step 10 — Gateway Route

The gateway `Service` is `ClusterIP` — not reachable externally without a Route. Create one in `openshift-ingress`:

```bash
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')

cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
  labels:
    app.kubernetes.io/component: gateway
    app.kubernetes.io/name: maas
spec:
  host: maas.${APPS_DOMAIN}
  port:
    targetPort: http
  to:
    kind: Service
    name: maas-default-gateway-openshift-default
    weight: 100
  wildcardPolicy: None
EOF

# Verify
curl -s "http://maas.${APPS_DOMAIN}/v1/health" | head -5
```

> **Note:** HTTP (port 80) via this Route works. HTTPS (port 443) requires TLS passthrough configuration.

---

## Verification

```bash
# Full status in one shot
echo "=== DSC ===" && \
oc get dsc default-dsc -o json | jq -r '
  .status.conditions[] |
  (if .status == "True" then "  ✓" else "  ✗") +
  " \(.type): \(.status)"'

echo "=== AIGateway ===" && \
oc get aigateway default-aigateway \
  -o jsonpath='{.status.phase}' && echo

echo "=== GatewayClass ===" && \
oc get gatewayclass openshift-default \
  -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' && echo

echo "=== Gateway ===" && \
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' && echo

echo "=== maas-api pods ===" && \
oc get pods -n redhat-ai-gateway-infra -l app.kubernetes.io/name=maas-api \
  --no-headers | awk '{print "  " $3, $1}'

echo "=== Gateway pod ===" && \
oc get pods -n openshift-ingress \
  -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
  --no-headers | awk '{print "  " $3, $1}'

echo "=== DB secret ===" && \
oc get secret maas-db-config -n redhat-ai-gateway-infra \
  -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d && echo
```

---

## Common Failures After Setup

| Symptom | Cause | Fix |
|---|---|---|
| `ModelsAsAServiceReady: False` — "Tenant CR has no ready condition" | maas-controller doesn't mirror status | `/debug-maas` Issue A — manually patch Tenant CR status |
| `maas-api` CrashLoopBackOff | `maas-db-config` missing or wrong namespace | Ensure secret is in `redhat-ai-gateway-infra` (not `redhat-ods-applications`) |
| Gateway pod OOMKilled | Kuadrant Wasm filter memory | Add 3Gi limit to `maas-default-gateway-config` ConfigMap — `/debug-maas` Issue I |
| Gateway `Programmed: False` | `maas-default-gateway-config` CM missing | Create the ConfigMap (Step 5), then Istio auto-provisions the Service + Deployment |
| `GatewayClass not found` error in HTTPRoute | GatewayClass not created manually | Create it (Step 4) — Istio intentionally does not auto-create it |
| Authorino TLS failing | Wrong cert path or namespace | Check `AUTHORINO_NS`, re-run Step 7 |
| `MaaSModelRef` not auto-created after model deployment | `Tenant` CR was missing when model was deployed | Create `Tenant` (Step 9), then manually create MaaSModelRef: `oc apply -f` with `spec.modelRef.kind: LLMInferenceService` + ownerReference to the LLMISVC |
| Gateway returns "Application is not available" | Route in `openshift-ingress` missing | Create the Route (Step 10) |
| Model HTTPRoute not attached / requests not routed | Namespace missing `maas-gateway-access=true` label | `oc label namespace <ns> maas-gateway-access=true` — required for gateway `Selector` policy |

Run `/debug-maas` for detailed diagnostics on any of the above.

---

## Idempotency

All steps in `enable-maas.sh` check for existing resources before applying. Safe to re-run at any point.
To force-recreate a resource: `oc delete <resource>` then re-run the step.

Next: `/deploy-maas-model` to deploy your first model.

## Output Format

```
# MaaS Enable Report — {timestamp}

## Prerequisites
| Requirement | Status |
|-------------|--------|
| OpenShift ≥ 4.19 | ✓/✗ |
| RHOAI ≥ 3.4 | ✓/✗ |
| Connectivity Link Operator | ✓/✗ |
| Kuadrant CR ready | ✓/✗ |
| Gateway API CRDs | ✓/✗ |

## Components
| Step | Resource | Status |
|------|----------|--------|
| 2 | DSC AIGateway patch | {Applied/Skipped} |
| 3 | Dashboard feature flags | {Applied/Skipped} |
| 4 | GatewayClass | {Accepted/Pending} |
| 5 | Gateway ConfigMap | {Created/Exists} |
| 6 | Gateway | {Programmed/Pending} |
| 7 | Authorino TLS | {Configured/Failed} |
| 8 | PostgreSQL + DB secret | {Running/Failed} |
| 9 | Tenant CR | {Ready/Pending} |
| 10 | Gateway Route | {Created/Exists} |

## Verification
- AIGateway phase: {Ready/Progressing/Failed}
- maas-api pods: {running}/{desired}
- Gateway pod: {Running/Pending}
- DB connection: {verified/failed}
```

## Safety Constraints

- Never run on a production cluster without first reviewing the dry-run output (`--dry-run`)
- Do not modify the DSC `aigateway` component if MaaS is already enabled — re-patching can trigger an operator reconciliation that disrupts running models
- Authorino TLS configuration is cluster-wide — changes affect all Authorino-protected services, not just MaaS
- The Gateway ConfigMap memory limit (3Gi) is essential — do not reduce it or the gateway pod will OOMKill when loading Kuadrant Wasm filters
- Do not use the default PostgreSQL password (`P@ssw0rd123!`) in production — always pass `--db-password` or use an external managed database
- The Tenant CR status must be manually patched to Ready on AITenant-managed clusters — no controller auto-sets it
- All setup changes must go through Git (PR) — never apply infrastructure manifests directly with `oc apply` in production

## Disconnected Environment Notes

- The internal PostgreSQL image (`quay.io/rh-ee-msteczko/postgres:16-alpine`) must be mirrored to the internal registry; update the deployment manifest image reference accordingly
- RHOAI operator images (maas-controller, maas-api, modelsasservice) are deployed via OLM — ensure the operator catalog is mirrored
- Istio/Envoy gateway images are managed by the OpenShift Service Mesh operator — mirror those catalogs as well
- Authorino images come from the Connectivity Link operator catalog — must be mirrored for disconnected environments
- GatewayClass, Gateway, and Route resources are cluster-internal and do not require external connectivity
- If using an external PostgreSQL, ensure the database endpoint is reachable from the `redhat-ai-gateway-infra` namespace (no external DNS required if using internal addresses)

## Related Skills

- `maas-deploy-model` — deploy a model to MaaS after setup (next step)
- `llmd-deployment-manager` — deploy with llm-d distributed inference
- `kserve-model-deployer` — deploy via standard KServe InferenceService (non-MaaS path)
