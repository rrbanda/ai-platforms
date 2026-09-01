# Gemini External Models (MaaS)

Registers Google Gemini models as external models in RHOAI 3.5
Models-as-a-Service, providing OpenAI-compatible inference with
authentication, subscription-based access control, and token rate limiting.

## Models

| Model | Google name | Use case |
|---|---|---|
| gemini-3.7-flash | `gemini-3.7-flash` | Search, grounding, agentic |
| gemini-3.5-flash | `gemini-3.5-flash` | Coding, agentic tasks |
| gemini-2.5-flash | `gemini-2.5-flash` | General-purpose, fast |
| gemini-3.5-flash-lite | `gemini-3.5-flash-lite` | Cost-effective, at-scale |
| gemini-2.5-pro | `gemini-2.5-pro` | Deep reasoning (retiring Oct 2026) |

## Critical: Naming Convention

K8s `metadata.name` uses **dotted names** (e.g., `gemini-3.5-flash`), matching
Google's actual model identifiers. This is essential because the RHOAI MaaS auth
pipeline (Authorino OPA policy, MaaS API subscription validation) resolves models
by `metadata.name`. Using hyphenated names (e.g., `gemini-3-5-flash`) would cause
a mismatch between what the client sends, what the HTTPRoute matches, and what the
subscription validates against.

K8s accepts dots in resource names (DNS subdomain format, RFC 1123). Despite the
RHOAI docs suggesting `spec.modelName` for this scenario, that field's aliases are
**not propagated** to the auth policy or subscription validation in RHOAI 3.5 --
so dotted `metadata.name` is the correct approach.

## Architecture

```
Client  →  POST /v1/chat/completions {"model": "gemini-3.5-flash"}
        →  MaaS Gateway (Envoy + Istio)
        →  Pre-processing ext-proc (body-field-to-header + model-provider-resolver)
        →  Authorino (API key validation + OPA subscription check)
        →  HTTPRoute match (X-Gateway-Model-Name: gemini-3.5-flash)
        →  Main ext-proc (api-translation rewrites path, apikey-injection)
        →  Google AI Studio /v1beta/openai/chat/completions
```

## Multi-Cluster GitOps Structure

```
base/03-workloads/gemini-external/     ← Shared resources (ArgoCD-managed)
  kustomization.yaml                      All ExternalModels, MaaSModelRefs,
  namespace.yaml                          MaaSAuthPolicy, MaaSSubscription,
  external-provider.yaml                  ExternalProvider, namespace
  external-model.yaml                     NO secrets in base
  maas-model-ref.yaml
  maas-auth-policy.yaml
  maas-subscription.yaml
  templates/                           ← Secret template (for reference only)

overlays/<cluster>/gemini-external/    ← Per-cluster (secrets only)
  kustomization.yaml                      References the sealed secret
  sealed-gemini-api-key.yaml              Sealed with this cluster's cert
  argocd-app.yaml                         ArgoCD Application for this cluster
```

The base ArgoCD Application (`gemini-external`) deploys shared configs.
A separate per-cluster ArgoCD Application (`gemini-external-secrets`) deploys
the sealed secret from the overlay. Both sync from Git automatically.

For hub-spoke clusters, the `spoke-gemini-external` ApplicationSet in
`clusters/hubs/primary/applicationsets/` handles both layers automatically.

## Files

| File | Purpose |
|---|---|
| `namespace.yaml` | `gemini-external` namespace with MaaS gateway access label |
| `external-provider.yaml` | `google-ai-studio` provider config (endpoint, auth type) |
| `external-model.yaml` | 5 ExternalModel CRs with dotted names |
| `maas-model-ref.yaml` | 5 MaaSModelRef CRs registering models in the MaaS catalog |
| `maas-auth-policy.yaml` | Grants `system:authenticated` access to all Gemini models |
| `maas-subscription.yaml` | `gemini-external-standard` tier with per-model token rate limits |
| `templates/gemini-api-key.yaml.template` | Plaintext secret template (never apply directly) |
| `kustomization.yaml` | Kustomize entry point |

## Deploy on a New Cluster

### Prerequisites

- RHOAI 3.5 deployed with MaaS enabled (`aigateway.modelsAsAService: Managed` in DSC)
- MaaS gateway (`maas-default-gateway`) provisioned and healthy
- SealedSecrets controller installed
- A Google AI Studio API key (https://aistudio.google.com/apikey)

### Step 1: Create the overlay directory

```bash
CLUSTER=my-cluster
mkdir -p overlays/${CLUSTER}/gemini-external
```

### Step 2: Seal the Google API key

The sealed secret is cluster-specific. Seal for the target cluster:

```bash
oc create secret generic gemini-api-key \
  --namespace=gemini-external \
  --from-literal=api-key='YOUR_GOOGLE_AI_STUDIO_API_KEY' \
  --dry-run=client -o yaml | \
  kubeseal \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets \
    --format=yaml \
  > overlays/${CLUSTER}/gemini-external/sealed-gemini-api-key.yaml
```

Verify no plaintext leaked:

```bash
grep -c 'YOUR_GOOGLE' overlays/${CLUSTER}/gemini-external/sealed-gemini-api-key.yaml
# should be 0
```

### Step 3: Create the overlay kustomization

```bash
cat > overlays/${CLUSTER}/gemini-external/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - sealed-gemini-api-key.yaml
EOF
```

### Step 4: Create the per-cluster ArgoCD Application

```bash
cat > overlays/${CLUSTER}/gemini-external/argocd-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gemini-external-secrets
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: rhoai-workloads
  source:
    repoURL: https://github.com/rrbanda/ai-platforms.git
    targetRevision: main
    path: redhat/rhoai/v3.5/overlays/${CLUSTER}/gemini-external
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 10m
    syncOptions:
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
EOF
```

### Step 5: Commit, push, and apply

```bash
git add overlays/${CLUSTER}/gemini-external/
git commit -m "Add Gemini sealed secret for ${CLUSTER}"
git push

# Apply the secrets ArgoCD app (one-time bootstrap per cluster)
oc apply -f overlays/${CLUSTER}/gemini-external/argocd-app.yaml
```

The base `gemini-external` Application is deployed automatically by the
app-of-apps. Both apps sync from Git going forward.

### Step 6: Wait for reconciliation

```bash
oc get externalmodels.inference.opendatahub.io -n gemini-external
# All 5 should show PHASE=Ready

oc get maasmodelrefs -n gemini-external
# All 5 should show PHASE=Ready with the MaaS gateway endpoint
```

### Step 7: Create an API key and test

```bash
TOKEN=$(oc whoami -t)
MAAS_HOST="https://maas.apps.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"

curl -sk -X POST "${MAAS_HOST}/v1/api-keys" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"gemini-test","expiresIn":"24h","subscription":"gemini-external-standard"}'

MAAS_KEY="<key from above>"
curl -sk "${MAAS_HOST}/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-3.5-flash","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}'
```

## Adding a New Gemini Model

1. Add an `ExternalModel` entry to `external-model.yaml` with the **dotted** Google
   model name as `metadata.name` and `targetModel`
2. Add a `MaaSModelRef` entry to `maas-model-ref.yaml` referencing the new ExternalModel
3. Add the model to `maas-auth-policy.yaml` modelRefs
4. Add the model to `maas-subscription.yaml` modelRefs with a token rate limit
5. Commit and push -- ArgoCD syncs to all clusters automatically

## Adding a New Cluster

1. Create `overlays/<cluster>/gemini-external/` with the sealed secret and ArgoCD app
   (follow Steps 1-5 above)
2. For hub-spoke: ensure the cluster is in the `all-rhoai-spokes` placement and has
   an overlay directory; the `spoke-gemini-external` ApplicationSet handles the rest

## Troubleshooting

**`subscription does not include model`** (403):
The model name in the request body doesn't match the subscription's `modelRefs`.
Ensure `metadata.name` uses dotted names matching what clients send.

**`authType 'apikey' credentials not found`**:
The API key secret is missing the label `inference.llm-d.ai/ipp-managed: "true"`.
Check that the SealedSecret template includes this label. Restart the
`payload-processing` deployment in `openshift-ingress` after fixing.

**Google 404 `models/xxx is not found`**:
The `targetModel` value doesn't match a valid Google model name.
Verify at https://aistudio.google.com/apikey that the model is available
for your API key.

**TLS handshake failures from outside the cluster**:
The MaaS gateway uses a self-signed cert. Test from inside the cluster
or use `curl -k`. For production, configure a trusted cert on the Gateway.

**SealedSecret not decrypting on new cluster**:
The secret was sealed with a different cluster's certificate. Re-seal
using `kubeseal` while logged into the target cluster (Step 2 above).
