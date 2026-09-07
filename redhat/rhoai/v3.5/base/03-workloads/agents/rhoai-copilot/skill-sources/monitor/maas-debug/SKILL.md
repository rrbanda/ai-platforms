---
skill: debug-maas
description: Debug and fix OpenShift AI Models-as-a-Service (MaaS) issues — stuck tenants, DSC conditions, bootstrap loops, missing DBs, CrashLoopBackOff pods, HTTPRoute gateway failures, leader election crashes
tags: [openshift, rhoai, maas, tenant, aitenant, dsc, gateway, httproute, debugging, kubernetes]
---

# MaaS Debugging Skill

Diagnose and resolve common Models-as-a-Service (MaaS) issues in OpenShift AI (RHOAI).

## Namespace Reference

| Resource | Namespace |
|---|---|
| Tenant CR, MaasTenantConfig | `models-as-a-service` |
| AITenant | `ai-tenants` |
| maas-api, maas-postgres, maas-db-config secret | `redhat-ai-gateway-infra` |
| maas-controller, modelsasservice | `redhat-ods-applications` |
| Config (cluster-scoped) | — |

## Key Resources

- **DataScienceCluster (DSC)**: `default-dsc` — top-level; `ModelsAsAServiceReady` condition gates DSC Ready
- **Config** (`maas.opendatahub.io/v1alpha1`): cluster-scoped `default` — owned by ModelsAsService; has bootstrap annotation
- **AITenant**: `models-as-a-service` in `ai-tenants` — finalizer `maas.opendatahub.io/aitenant-cleanup`
- **MaasTenantConfig**: `default-tenant` in `models-as-a-service` — reconciled by maas-controller
- **Tenant CR**: `default-tenant` in `models-as-a-service` — status mirrored from MaasTenantConfig; read by DSC controller
- **maas-api**: Deployment in `redhat-ai-gateway-infra` — requires `maas-db-config` secret
- **maas-db-config**: Secret in `redhat-ai-gateway-infra` — must have `DB_CONNECTION_URL` key
- **GatewayClass** `openshift-default`: cluster-scoped — Istio is configured to watch this name (`PILOT_GATEWAY_API_DEFAULT_GATEWAYCLASS_NAME`), but `PILOT_ENABLE_GATEWAY_API_GATEWAYCLASS_CONTROLLER: false` means Istio does NOT auto-create it; it must exist manually
- **Gateway** `maas-default-gateway` in `openshift-ingress`: routes model HTTPRoutes from any namespace to model pods; requires `maas-default-gateway-config` ConfigMap in `openshift-ingress` for Istio to provision its Service/Deployment
- **HTTPRoute** per model: in the model's namespace (e.g. `<model-namespace>`), `parentRefs` the `maas-default-gateway`
- **maas-controller**: Deployment in `redhat-ods-applications` — label is `control-plane=maas-controller` (NOT `app.kubernetes.io/name`); holds a leader election lease; crashes with exit code 1 when it loses the lease

## Step 1 — Full Status Snapshot

Run this first to get the full picture:

```bash
echo "=== DSC ==="
oc get dsc default-dsc -o json | python3 -c "
import json, sys
dsc = json.load(sys.stdin)
print('Phase:', dsc['status']['phase'])
for c in dsc['status']['conditions']:
    mark = '✓' if c['status'] == 'True' else '✗'
    print(f\"  {mark} {c['type']}: {c['status']} — {c.get('message','')}\")
"

echo "=== Tenant CR ==="
oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.status}' && echo

echo "=== MaasTenantConfig ==="
oc get maastenantconfig default-tenant -n models-as-a-service -o jsonpath='{.status}' && echo

echo "=== AITenant ==="
oc get aitenant models-as-a-service -n ai-tenants -o jsonpath='{.status}{"\n"}{.metadata.finalizers}' && echo

echo "=== Config ==="
oc get config.maas.opendatahub.io default -o jsonpath='{.metadata.annotations}{"\n"}{.metadata.uid}' && echo

echo "=== maas-api pod ==="
oc get pods -n redhat-ai-gateway-infra -l app.kubernetes.io/name=maas-api

echo "=== maas-controller pod (restarts matter) ==="
oc get pods -n redhat-ods-applications -l control-plane=maas-controller --no-headers

echo "=== maas-db-config secret ==="
oc get secret maas-db-config -n redhat-ai-gateway-infra -o jsonpath='{.data}' 2>&1 | python3 -c "
import json, sys, base64
try:
    d = json.load(sys.stdin)
    for k,v in d.items(): print(k, '=', base64.b64decode(v).decode()[:40])
except: print('Missing or unreadable')
"

echo "=== Gateway / HTTPRoute health ==="
oc get gatewayclass openshift-default 2>&1
oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' && echo
oc get cm maas-default-gateway-config -n openshift-ingress --no-headers 2>&1
```

## Step 2 — Common Issues and Fixes

### Issue A: DSC `ModelsAsAServiceReady: False` — "Tenant CR has no ready condition"

The maastenantconfig controller does not always mirror conditions to the Tenant CR. Patch it manually:

```bash
oc patch tenant default-tenant -n models-as-a-service --subresource=status --type=merge \
  -p '{"status":{"conditions":[{"type":"Ready","status":"True","reason":"Reconciled",
  "message":"MaaS platform manifests applied and maas-api deployment is available",
  "lastTransitionTime":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","observedGeneration":1}]}}'
```

Verify:

```bash
oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")]}'
```

---

### Issue B: AITenant stuck in Terminating (finalizer deadlock)

Symptom: `oc get aitenant models-as-a-service -n ai-tenants` shows `Terminating` for >5 min.

Root cause: the `maas-api-revoke-keys-*` job or the `maas-api-cleanup` SA is missing, so the finalizer controller never clears.

Fix — force remove finalizer:

```bash
oc patch aitenant models-as-a-service -n ai-tenants \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
```

Then check for stuck revocation job:

```bash
oc get jobs -n redhat-ai-gateway-infra | grep revoke
oc delete job maas-api-revoke-keys-models-as-a-service -n redhat-ai-gateway-infra 2>/dev/null || true
```

---

### Issue C: New AITenant not recreated after deletion (bootstrap annotation blocks it)

Symptom: AITenant deleted, nothing recreated, Config has annotation `default-aitenant-bootstrapped: "true"`.

Verify:

```bash
oc get config.maas.opendatahub.io default \
  -o jsonpath='{.metadata.annotations.maas\.opendatahub\.io/default-aitenant-bootstrapped}'
```

Fix — remove the one-shot bootstrap annotation so the controller re-runs:

```bash
oc annotate config.maas.opendatahub.io default \
  maas.opendatahub.io/default-aitenant-bootstrapped-
```

Watch maas-controller logs to confirm AITenant is recreated:

```bash
oc logs -n redhat-ods-applications deployment/maas-controller --follow --tail=50
```

---

### Issue D: Config cycling (UID changes, triggers AITenant GC loop)

Symptom: Config UID changes, AITenant keeps being garbage-collected and recreated.

Check Config UID stability:

```bash
oc get config.maas.opendatahub.io default -o jsonpath='{.metadata.uid}{"\n"}{.metadata.creationTimestamp}'
```

If the Config is being deleted/recreated by `ensureMaasClusterConfigControllerRef`, wait for ModelsAsService to settle. Check its status:

```bash
oc get modelsasservice default-modelsasservice -o jsonpath='{.status}' && echo
```

---

### Issue E: maas-api CrashLoopBackOff — missing `maas-db-config` secret

Symptom: `oc logs -n redhat-ai-gateway-infra deployment/maas-api` shows `database Secret 'maas-db-config' not found`.

Fix — create the secret and deploy postgres in `redhat-ai-gateway-infra`:

```bash
DB_PASSWORD=<your-password>

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: maas-db-config
  namespace: redhat-ai-gateway-infra
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
  namespace: redhat-ai-gateway-infra
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: maas-postgres-deployment
  namespace: redhat-ai-gateway-infra
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
        image: docker.io/library/postgres:16-alpine
        env:
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef: {name: maas-db-config, key: POSTGRES_DB}
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef: {name: maas-db-config, key: POSTGRES_USER}
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef: {name: maas-db-config, key: POSTGRES_PASSWORD}
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: maas-postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: maas-postgres-service
  namespace: redhat-ai-gateway-infra
spec:
  selector:
    app: maas-postgres
  ports:
  - port: 5432
    targetPort: 5432
EOF

oc rollout status deployment/maas-postgres-deployment -n redhat-ai-gateway-infra --timeout=120s
```

Then restart maas-api so it picks up the secret:

```bash
oc rollout restart deployment/maas-api -n redhat-ai-gateway-infra
oc rollout status deployment/maas-api -n redhat-ai-gateway-infra
```

---

### Issue F: `maas-api-cleanup` ServiceAccount missing (revocation job fails)

Symptom: Job `maas-api-revoke-keys-models-as-a-service` fails with "serviceaccount 'maas-api-cleanup' not found".

Root cause: SA was garbage-collected during Config recreation cycle. It's recreated when ModelsAsService re-provisions.

Workaround while waiting for re-provision:

```bash
# Delete the stuck job, remove AITenant finalizer, remove bootstrap annotation
oc delete job maas-api-revoke-keys-models-as-a-service -n redhat-ai-gateway-infra 2>/dev/null || true
oc patch aitenant models-as-a-service -n ai-tenants \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
oc annotate config.maas.opendatahub.io default \
  maas.opendatahub.io/default-aitenant-bootstrapped-
```

---

### Issue G: HTTPRoute fails — `GatewayClass "openshift-default" not found`

Symptom: Model deployment shows "Failed to reconcile HTTPRoute: failed to get GatewayClass 'openshift-default'".

Root cause: Istio is configured with `PILOT_GATEWAY_API_DEFAULT_GATEWAYCLASS_NAME: openshift-default` and controller name `openshift.io/gateway-controller/v1`, but `PILOT_ENABLE_GATEWAY_API_GATEWAYCLASS_CONTROLLER: false` — Istio intentionally does not auto-create this GatewayClass. It must exist manually.

Fix:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-default
spec:
  controllerName: openshift.io/gateway-controller/v1
EOF
```

Verify:

```bash
oc get gatewayclass openshift-default
# Should show: ACCEPTED=True
```

---

### Issue H: Gateway `maas-default-gateway` stuck `Programmed: Unknown/False` — Service not provisioned

Symptom: After GatewayClass exists, gateway status shows `Failed to assign to any requested addresses: hostname "maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local" not found`.

Root cause: The `maas-default-gateway` has `spec.infrastructure.parametersRef.name: maas-default-gateway-config` but that ConfigMap doesn't exist in `openshift-ingress`. Istio needs it to provision the gateway Service and Deployment.

Fix (must include `deployment:` key with 3Gi memory — omitting it causes Issue I):

```bash
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

Verify within ~10 seconds Istio provisions the gateway:

```bash
oc get deployment,svc -n openshift-ingress | grep maas
# Should show: maas-default-gateway-openshift-default  1/1  Running
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# Should show: True
```

Then verify the HTTPRoute is accepted:

```bash
oc get httproute <route-name> -n <model-namespace> \
  -o jsonpath='{.status.parents[?(@.controllerName=="openshift.io/gateway-controller/v1")].conditions}'
# Look for: Accepted=True, ResolvedRefs=True
```

---

### Issue I: Gateway pod `maas-default-gateway-openshift-default-*` OOMKilled

Symptom: All model endpoints return 503; gateway pod is in `CrashLoopBackOff` with exit code 137.

```bash
oc get pods -n openshift-ingress -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway"
# Shows: CrashLoopBackOff, RESTARTS climbing
oc describe pod -n openshift-ingress -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
  | grep -A 3 "Last State:"
# Shows: Reason: OOMKilled
```

Root cause: Istio/Envoy proxy loads Kuadrant Wasm filters for auth and rate limiting (`kuadrant-maas-default-gateway` EnvoyFilter). The combined memory footprint of Wasm code fetching exceeds the default 1Gi limit.

Fix — set memory via `maas-default-gateway-config` ConfigMap (Istio reads this; do NOT patch the Deployment directly — Istio will revert it):

```bash
oc patch configmap maas-default-gateway-config -n openshift-ingress --type=merge -p '
{
  "data": {
    "deployment": "spec:\n  template:\n    spec:\n      containers:\n      - name: istio-proxy\n        resources:\n          limits:\n            cpu: \"2\"\n            memory: \"3Gi\"\n          requests:\n            cpu: \"100m\"\n            memory: \"512Mi\"\n"
  }
}'

oc rollout restart deployment/maas-default-gateway-openshift-default -n openshift-ingress
oc rollout status deployment/maas-default-gateway-openshift-default -n openshift-ingress
```

Verify endpoint recovers:

```bash
MAAS_HOST=$(oc get route maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.spec.host}' 2>/dev/null || \
  oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.spec.listeners[0].hostname}')
curl -s "http://${MAAS_HOST}/maas-api/v1/models"
```

---

### Issue J: maas-controller repeated restarts — leader election lost (exit code 1)

Symptom: `maas-controller` pod shows RESTARTS > 2 in `redhat-ods-applications`; exit code is 1, not 137 (not OOMKilled). MaaSModelRef objects may stop being created for newly deployed models.

```bash
oc get pods -n redhat-ods-applications -l control-plane=maas-controller --no-headers
# Shows: RESTARTS climbing
```

Confirm the crash cause from the previous container:

```bash
oc logs -n redhat-ods-applications deployment/maas-controller --previous 2>/dev/null | tail -10
# Look for: "leader election lost" or "context deadline exceeded" on the lease URL
```

Root cause: The controller fails to renew its Kubernetes leader election lease (`redhat-ods-applications/maas-controller.models-as-a-service.opendatahub.io`) due to API server timeouts (`context deadline exceeded`). When the lease renewal deadline is missed, the controller exits with code 1 — this is intentional behaviour (rather than running as a non-leader). The pod is restarted by Kubernetes and re-wins the lease immediately if there is only one replica.

Check the lease directly:

```bash
oc get lease maas-controller.models-as-a-service.opendatahub.io \
  -n redhat-ods-applications \
  -o jsonpath='{.spec.holderIdentity}{" renewed: "}{.spec.renewTime}' && echo
```

Fixes:

1. **If restarts are infrequent (< 5 total, hours apart)**: transient API server blip — no action needed. The controller recovers automatically.

2. **If restarts are frequent or climbing**: API server is under load or the controller's lease duration is too short. Check API server health:

```bash
oc get pods -n openshift-kube-apiserver --no-headers | grep -v Running
oc get events -n redhat-ods-applications --sort-by='.lastTimestamp' \
  | grep -i "maas-controller\|lease\|timeout" | tail -10
```

3. **If MaaSModelRef is missing after a crash** (model deployed while controller was down): the `llmisvc-controller` only calls `reconcileMonitoring` once on create. Trigger re-reconcile by annotating the LLMInferenceService:

```bash
oc annotate llminferenceservice <model-name> -n <model-namespace> \
  debug.maas/force-reconcile="$(date -u +%s)" --overwrite
```

If that doesn't work, delete and recreate the LLMInferenceService (model will redeploy).

4. **Memory**: The controller has a 512Mi limit. If `oc describe pod` shows `OOMKilled` (exit 137) instead of exit 1, see Issue I pattern — increase the memory limit via the RHOAI operator's `DataScienceCluster` spec or open a support case.

---

## Step 3 — Verify Full Recovery

```bash
# All of these should return "True"
oc get dsc default-dsc -o jsonpath='{.status.phase}' && echo
oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="ModelsAsAServiceReady")].status}' && echo
oc get aitenant models-as-a-service -n ai-tenants -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' && echo
oc get maastenantconfig default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' && echo
oc get pods -n redhat-ai-gateway-infra -l app.kubernetes.io/name=maas-api --no-headers | awk '{print $3}'

# maas-controller: check restarts (label is control-plane=maas-controller)
oc get pods -n redhat-ods-applications -l control-plane=maas-controller \
  --no-headers | awk '{print "restarts=" $4, "status=" $3}'

# Gateway health
oc get gatewayclass openshift-default -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' && echo
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' && echo
oc get deployment maas-default-gateway-openshift-default -n openshift-ingress \
  -o jsonpath='{.status.readyReplicas}' && echo

oc get pods -n openshift-ingress -l "gateway.networking.k8s.io/gateway-name=maas-default-gateway" \
  --no-headers | awk '{print $3, $4}'
# Should show: Running 0 (or low restart count)
```

## Step 4 — Escalation Checks

If the above don't resolve it, gather full diagnostics:

```bash
# maas-controller recent events
oc logs -n redhat-ods-applications deployment/maas-controller --tail=100

# Previous crash logs
oc logs -n redhat-ods-applications deployment/maas-controller --previous 2>/dev/null | tail -20

# RHOAI operator events around MaaS
oc get events -n redhat-ods-applications --sort-by='.lastTimestamp' | grep -i maas | tail -20

# Tenant CR raw status
oc get tenant default-tenant -n models-as-a-service -o yaml | grep -A 30 "^status:"

# Check if RBAC allows status subresource update
oc auth can-i update tenants.maas.opendatahub.io/status -n models-as-a-service \
  --as=system:serviceaccount:redhat-ods-applications:maas-controller
```
