# RHOAI 3.4 -- GitOps Deployment

Deploy Red Hat OpenShift AI **3.4** on OpenShift using the official Helm chart,
managed entirely through OpenShift GitOps (ArgoCD).

| | Details |
|---|---|
| **RHOAI version** | 3.4 (chart v3.4.4) |
| **Chart source** | `oci://registry.redhat.io/rhai/rhai-on-openshift-chart:v3.4` |
| **OCP requirement** | 4.17+ |
| **Repo** | `https://github.com/rrbanda/ai-platforms.git` (branch: `main`) |
| **Path** | `redhat/rhoai/v3.4/` |
| **For RHOAI 3.5** | See `redhat/rhoai/v3.5/` |

---

## Architecture

```
oc apply -f redhat/rhoai/v3.4/base/app-of-apps.yaml
    |
    +-- Wave 0: Prerequisite operators
    |       Service Mesh 3.x + MCP Gateway operator
    |
    +-- Wave 1: RHOAI platform (Helm chart)
    |       RHOAI operator + DSC with 14 components + Gateways
    |
    +-- Wave 2: Cluster config
    |       Dashboard features, EvalHub, MLflow, NemoGuardrails,
    |       MaaS PostgreSQL, MCP Gateway, vector stores
    |
    +-- Wave 3: Application workloads
            LlamaStackDistribution + Milvus + DSPA (AutoRAG stack)
```

### ArgoCD Applications

| Wave | App | Project | Source |
|------|-----|---------|--------|
| 0 | `rhoai-servicemesh` | rhoai-platform | `base/00-operators/servicemesh` |
| 0 | `rhoai-mcp-gateway-operator` | rhoai-platform | `base/00-operators/mcp-gateway` |
| 1 | `rhoai-platform` | rhoai-platform | `chart/` (Helm) |
| 2 | `rhoai-cluster-config` | rhoai-config | `base/02-config/` |
| 3 | `autorag-workload` | rhoai-workloads | `base/03-workloads/autorag/` |
| -- | `rhoai-deploy` (parent) | default | `base/applications/` |

### What the Helm chart deploys

14 DSC components: Dashboard, KServe (KServe Models-as-a-Service, NIM, WVA),
AIPipelines (Argo Workflows), Kueue, Ray, Trainer, TrainingOperator,
Workbenches, ModelRegistry, TrustyAI, MLflow Operator, Feast Operator,
Llama Stack Operator, Spark Operator. Plus up to 12 dependency operators,
DSCInitialization, Gateways.

Dependency operators (tri-state `auto`/`true`/`false`): cert-manager,
RHCL/Kuadrant, Kueue, JobSet, LeaderWorkerSet, CMA, NFD, GPU Operator,
Cluster Observability, OpenTelemetry, Tempo.

### What cluster-config adds

OdhDashboardConfig (9 DP/TP feature flags), EvalHub, MLflow, NemoGuardrails,
User Workload Monitoring, MaaS PostgreSQL, MCP Gateway, MCP server registry,
vector stores for Playground RAG.

### What the workload layer adds

LlamaStackDistribution (RAG backbone), Milvus vector database + etcd,
DSPA pipeline server with built-in MinIO.

---

## Prerequisites

| Requirement | Details |
|---|---|
| OpenShift | 4.17+ with cluster-admin access |
| `oc` CLI | Installed and authenticated |
| `kubeseal` CLI | `brew install kubeseal` |
| Helm | 3.17+ (optional, for local testing) |
| RHACM | Required for hub-spoke (optional for single cluster) |

---

## Quick Start

### Step 0: Pre-deployment cleanup (shared clusters only)

If the cluster had a previous RHOAI installation, clean up stale CRs:

```bash
./redhat/rhoai/v3.4/scripts/cluster-cleanup.sh        # Detect stale resources
./redhat/rhoai/v3.4/scripts/cluster-cleanup.sh --fix   # Auto-remediate
```

### Step 1: Bootstrap (one-time)

```bash
oc apply -k redhat/rhoai/v3.4/setup/bootstrap/
until oc apply -f redhat/rhoai/v3.4/setup/bootstrap/argocd-instance.yaml; do sleep 10; done
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
oc apply -f redhat/rhoai/v3.4/setup/argocd-projects.yaml
```

### Step 2: Wire RHACM (if installed)

```bash
oc apply -k redhat/rhoai/v3.4/setup/rhacm/
```

This creates a ManagedClusterSetBinding, Placement, and GitOpsCluster to
register the cluster in ArgoCD via RHACM. Skip if RHACM is not installed.

### Step 3: Seal workload secrets

There are **4 SealedSecrets** that must be encrypted with your cluster's
Sealed Secrets certificate. Use the provided script:

```bash
# Wait for Sealed Secrets controller
oc wait --for=condition=Available deployment/sealed-secrets-controller \
  -n sealed-secrets --timeout=120s

# Set env vars (or leave blank to be prompted)
export LLM_API_KEY="your-gemini-or-openai-key"
export MAAS_DB_PASSWORD="your-db-password"
export S3_ACCESS_KEY="your-access-key"
export S3_SECRET_KEY="your-secret-key"
export S3_BUCKET="autorag"
export S3_ENDPOINT="https://s3.amazonaws.com"

./redhat/rhoai/v3.4/scripts/reseal-all.sh
```

The script seals these 4 secrets:

| Secret | Template | Sealed Output |
|---|---|---|
| LLM API key | `base/03-workloads/autorag/templates/llm-api-secret.yaml.template` | `base/03-workloads/autorag/sealed-llm-api-secret.yaml` |
| S3 connection | `base/03-workloads/autorag/templates/s3-connection-secret.yaml.template` | `base/03-workloads/autorag/sealed-s3-connection-secret.yaml` |
| MaaS DB creds | `base/02-config/templates/maas-postgres-credentials.yaml.template` | `base/02-config/sealed-maas-postgres-credentials.yaml` |
| MaaS DB URL | `base/02-config/templates/maas-db-config.yaml.template` | `base/02-config/sealed-maas-db-config.yaml` |

SealedSecrets are **cluster-specific** -- re-seal when deploying to a different cluster.

### Step 4: Deploy

```bash
oc apply -f redhat/rhoai/v3.4/base/app-of-apps.yaml
```

ArgoCD discovers child Applications and deploys in wave order:

1. **Wave 0**: Service Mesh 3.x + MCP Gateway operators (1-2 min)
2. **Wave 1**: Helm chart renders all RHOAI operators + DSC + Gateways
   (~5-10 min for all operators to reach Succeeded)
3. **Wave 2**: Cluster-config enables dashboard features, monitoring,
   MaaS DB, MCP Gateway, EvalHub, MLflow, NemoGuardrails
4. **Wave 3**: AutoRAG workload deploys (Milvus, DSPA, LlamaStackDistribution)

DSC takes ~15-30 minutes to fully reconcile all components.

### Step 5: Verify

```bash
# All 6 apps should be Synced/Healthy
oc get applications.argoproj.io -n openshift-gitops

# DSC should be Ready
oc get datasciencecluster -o jsonpath='{.items[0].status.phase}'

# AutoRAG pods should be running
oc get pods -n autorag

# Dashboard features enabled
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig}' | python3 -m json.tool
```

---

## Developer Endpoints

### Llama Stack Server (RAG backbone -- OpenAI-compatible API)

| | Value |
|---|---|
| **Internal URL** | `http://autorag-llamastack-service.autorag.svc:8321` |
| **Port** | 8321 (API), 9464 (metrics) |
| **API format** | OpenAI-compatible |

```bash
# List models
curl http://autorag-llamastack-service.autorag.svc:8321/v1/models

# Chat completion
curl -X POST http://autorag-llamastack-service.autorag.svc:8321/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemini-2.5-flash", "messages": [{"role": "user", "content": "What is RAG?"}]}'

# Embeddings
curl -X POST http://autorag-llamastack-service.autorag.svc:8321/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "sentence-transformers/nomic-ai/nomic-embed-text-v1.5", "input": "text to embed"}'
```

### Available models (default config)

| Type | Model ID | Provider |
|---|---|---|
| Embedding | `sentence-transformers/nomic-ai/nomic-embed-text-v1.5` | Local (CPU) |
| LLM | `gemini-2.5-flash` | Gemini API |

### Milvus vector database

| | Value |
|---|---|
| **Internal URL** | `http://milvus-service.autorag.svc:19530` |
| **Ports** | 19530 (gRPC/REST), 9091 (metrics) |

### Other endpoints

| Service | URL |
|---|---|
| RHOAI Dashboard | `https://rhods-dashboard-redhat-ods-applications.apps.<cluster-domain>` |
| AutoRAG UI | Dashboard > Gen AI Studio > AutoRAG |
| KServe Inference Gateway | `oc get gateway openshift-ai-inference -n openshift-ingress` |
| KServe MaaS Gateway | `oc get gateway maas-default-gateway -n openshift-ingress` |
| ArgoCD Console | `oc get route openshift-gitops-server -n openshift-gitops` |

### Local development (port-forwarding)

```bash
oc port-forward svc/autorag-llamastack-service -n autorag 8321:8321 &
oc port-forward svc/milvus-service -n autorag 19530:19530 &
```

---

## Dashboard Feature Flags (v3.4)

The cluster-config layer deploys an `OdhDashboardConfig` with these flags:

| Flag | Value | Description |
|------|-------|-------------|
| `genAiStudio` | `true` | Gen AI Studio / Playground |
| `mcpCatalog` | `true` | MCP server catalog |
| `modelAsService` | `true` | Models-as-a-Service |
| `maasAuthPolicies` | `true` | MaaS auth policy management |
| `promptManagement` | `true` | Prompt management |
| `vLLMDeploymentOnMaaS` | `true` | vLLM deployment on MaaS |
| `mlflow` | `true` | MLflow experiment tracking |
| `observabilityDashboard` | `true` | Observability dashboard |
| `trainingJobs` | `true` | Training job management |

---

## Deployment Profiles

| Profile | Description | How to activate |
|---|---|---|
| Full platform (default) | All 14 DSC components | Already in `base/applications/rhoai-platform.yaml` |
| Inference only | KServe + deps only | Copy `profiles/connected/inference-only.yaml` |
| Disconnected | Full platform with mirrored catalog | Copy `profiles/disconnected/platform.yaml` |

---

## Multi-Cluster Architecture

One Git repo serves all clusters. The `clusters/` directory provides RHACM
ApplicationSets for hub-spoke deployments at scale.

### Hub-spoke with RHACM Pull Model

```bash
oc apply -k redhat/rhoai/v3.4/clusters/hubs/primary/
```

Then label spoke clusters by capability:

```bash
oc label managedcluster spoke-1 rhoai.io/platform=true rhoai.io/gpu=true
```

Spoke profiles (in `clusters/spokes/overlays/`):

| Profile | Label selector |
|---|---|
| `inference-only` | `rhoai.io/platform=true` |
| `gpu-training` | `rhoai.io/gpu=true` |
| `rag-agentic` | `rhoai.io/rag=true` |

### Onboard a spoke cluster

```bash
./redhat/rhoai/v3.4/scripts/spoke-onboard.sh <spoke-name>
```

---

## Deploying to Another Cluster

### 1. Fork and update the repo URL

```bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git
cd YOUR_REPO

export REPO_URL=https://github.com/YOUR_ORG/YOUR_REPO.git
find redhat/rhoai/v3.4 -name '*.yaml' -exec \
  sed -i "s|https://github.com/rrbanda/ai-platforms.git|${REPO_URL}|g" {} +

git commit -am "Update repo URL for new cluster"
git push
```

### 2. Bootstrap the new cluster

```bash
oc apply -k redhat/rhoai/v3.4/setup/bootstrap/
until oc apply -f redhat/rhoai/v3.4/setup/bootstrap/argocd-instance.yaml; do sleep 10; done
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
oc apply -f redhat/rhoai/v3.4/setup/argocd-projects.yaml
```

### 3. Re-seal all secrets

SealedSecrets are cluster-specific. Re-seal with the new cluster's cert:

```bash
./redhat/rhoai/v3.4/scripts/reseal-all.sh
git add redhat/rhoai/v3.4/base/*/sealed-*.yaml
git commit -m "Re-seal secrets for new cluster"
git push
```

### 4. Deploy

```bash
oc apply -f redhat/rhoai/v3.4/base/app-of-apps.yaml
```

---

## Disconnected Deployment

### 1. Mirror images

```bash
# Edit imageset-config-template.yaml:
#   REPLACE_OCP_VERSION -> v4.17
#   REPLACE_RHOAI_CHANNEL -> stable-3.4
#   REPLACE_KUEUE_CHANNEL -> stable-v1.2

oc-mirror --config redhat/rhoai/v3.4/disconnected/imageset-config-template.yaml \
  docker://<mirror-registry> --v2
```

### 2. Apply mirror config

```bash
oc apply -f working-dir/cluster-resources/  # IDMS, CatalogSource
```

Note the generated CatalogSource name (e.g., `cs-redhat-operator-index-v4-17`).

### 3. Additional workload images to mirror

| Image | Used by |
|---|---|
| `milvusdb/milvus:v2.6.0` | Milvus vector database |
| `quay.io/coreos/etcd:v3.5.5` | etcd (Milvus dependency) |
| `quay.io/minio/minio:RELEASE.2023-09-04T19-57-37Z` | MinIO (DSPA built-in) |
| `registry.redhat.io/rhel9/postgresql-15:latest` | PostgreSQL (MaaS) |

### 4. Swap to disconnected profiles

```bash
cp profiles/disconnected/servicemesh.yaml base/applications/00-servicemesh.yaml
cp profiles/disconnected/platform.yaml base/applications/rhoai-platform.yaml
```

Edit both: replace `REPLACE_WITH_REDHAT_CATALOG_NAME` with your catalog name.
Commit, push, apply app-of-apps.

---

## Optional Components

### Loki-based MaaS showback

Requires the Cluster Logging operator (not part of RHOAI). If installed:

```bash
oc apply -k redhat/rhoai/v3.4/base/04-optional/loki-showback/
```

---

## Technical Notes

### Llama Stack ConfigMap requires watch label

The Llama Stack operator uses a label-selector informer. ConfigMaps referenced
by the LlamaStackDistribution MUST have these labels:

```yaml
metadata:
  labels:
    app: llama-stack
    llamastack.io/watch: "true"
```

Without these labels, LlamaStackDistribution fails with:
`failed to find referenced ConfigMap <namespace>/<name>`

### Llama Stack config uses `.llama` paths

Storage paths in the Llama Stack config use `.llama` (not `.ogx`):

```yaml
db_path: /opt/app-root/src/.llama/kvstore.db
storage_dir: /opt/app-root/src/.llama/files
```

### KServe Models-as-a-Service (MaaS)

In v3.4, Models-as-a-Service is a sub-component of KServe (`kserve.dsc.modelsAsService`),
not a separate AI Gateway component. The MaaS gateway is configured under
`kserve.modelsAsService.gateway`.

### DSPA API version is v1

```yaml
apiVersion: datasciencepipelinesapplications.opendatahub.io/v1
```

### DSPA requires explicit MinIO image

```yaml
minio:
  deploy: true
  image: "quay.io/minio/minio:RELEASE.2023-09-04T19-57-37Z"
```

### SealedSecrets are cluster-specific

Each cluster has a unique sealing key pair. When deploying to a new cluster:

1. Fetch that cluster's cert: `kubeseal --fetch-cert --controller-namespace sealed-secrets`
2. Re-seal all secrets: `./redhat/rhoai/v3.4/scripts/reseal-all.sh`
3. Commit and push the new sealed files

### Helm chart sets DISABLE_DSC_CONFIG=true

The chart adds `DISABLE_DSC_CONFIG=true` on the rhods-operator Subscription,
preventing auto-creation of a default DSC. The chart manages the DSC directly.

### ArgoCD sync options explained

| Option | Why |
|---|---|
| `skipCrdCheck: true` | ArgoCD renders templates without cluster access; `lookup` always returns empty |
| `SkipDryRunOnMissingResource=true` | CRs fail dry-run if CRDs don't exist yet |
| `ServerSideApply=true` | Avoids field ownership conflicts with operators |
| `skipSchemaValidation: true` | v3.4 chart schema requires all managementState fields even when using profiles |

---

## Troubleshooting

**Stale CRs from previous tenant:**
```bash
./redhat/rhoai/v3.4/scripts/cluster-cleanup.sh --fix
```

**All apps OutOfSync after deploy**: Expected on first sync. ArgoCD retries
(limit=10, 30s backoff). Operators need 2-5 min to register CRDs.

**DSC stuck Not Ready:**
```bash
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[?(@.status!="True")]}{.type}: {.message}{"\n"}{end}'
```

**LlamaStackDistribution shows "Failed"**: Check if the ConfigMap has the required labels:
```bash
oc get configmap autorag-llamastack-config -n autorag -o jsonpath='{.metadata.labels}'
# Must include: app=llama-stack and llamastack.io/watch=true
```

**SealedSecret won't decrypt:**
The secret was sealed for a different cluster. Re-seal:
```bash
./redhat/rhoai/v3.4/scripts/reseal-all.sh
```

**Stuck KServe finalizer** (clusters with prior RHOAI):
```bash
oc patch kserve default-kserve --type merge -p '{"metadata":{"finalizers":null}}'
```

**ArgoCD "upload-pack: not our ref":**
Stale git cache. Restart repo-server:
```bash
oc rollout restart deployment/openshift-gitops-repo-server -n openshift-gitops
```

**Force re-sync:**
```bash
oc annotate applications.argoproj.io <app-name> -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite
```

**ArgoCD admin password:**
```bash
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d
```

---

## File Structure

```
v3.4/
├── base/                              # Cluster-agnostic (ArgoCD-managed)
│   ├── app-of-apps.yaml              # Entry point
│   ├── applications/                  # Child app manifests
│   │   ├── 00-servicemesh.yaml       #   Wave 0: SM3 operator
│   │   ├── 00-mcp-gateway-operator.yaml  #   Wave 0: MCP Gateway operator
│   │   ├── 01-cluster-config.yaml    #   Wave 2: Dashboard, EvalHub, MLflow, etc.
│   │   ├── 02-autorag-workload.yaml  #   Wave 3: AutoRAG stack
│   │   └── rhoai-platform.yaml       #   Wave 1: RHOAI Helm chart
│   ├── 00-operators/                  # Wave 0: prerequisite operators
│   │   ├── servicemesh/               #   SM3 Subscription
│   │   └── mcp-gateway/              #   MCP Gateway Subscription
│   ├── 02-config/                     # Wave 2: cluster config
│   │   ├── dashboard-features.yaml   #   OdhDashboardConfig (9 DP/TP flags)
│   │   ├── evalhub.yaml              #   EvalHub
│   │   ├── mlflow.yaml               #   MLflow instance
│   │   ├── nemo-guardrails.yaml      #   NemoGuardrails instance
│   │   ├── nemo-guardrails-config.yaml  #   NemoGuardrails config
│   │   ├── user-workload-monitoring.yaml  #   Enable User Workload Monitoring
│   │   ├── maas-postgres.yaml        #   PostgreSQL for MaaS
│   │   ├── mcp-gateway.yaml          #   MCP Gateway
│   │   ├── mcp-studio-config.yaml    #   MCP servers for Gen AI Playground
│   │   ├── vector-stores-config.yaml #   Vector stores for Playground RAG
│   │   ├── sealed-maas-postgres-credentials.yaml
│   │   ├── sealed-maas-db-config.yaml
│   │   ├── kustomization.yaml
│   │   └── templates/                 #   Secret templates (safe to commit)
│   ├── 03-workloads/autorag/          # Wave 3: AutoRAG workload
│   │   ├── namespace.yaml            #   autorag namespace
│   │   ├── llamastack.yaml           #   LlamaStackDistribution instance
│   │   ├── llamastack-config.yaml    #   Llama Stack config (llamastack.io/watch label)
│   │   ├── milvus.yaml              #   Milvus standalone + etcd
│   │   ├── dspa.yaml                 #   Pipeline server with built-in MinIO
│   │   ├── sealed-llm-api-secret.yaml
│   │   ├── sealed-s3-connection-secret.yaml
│   │   ├── kustomization.yaml
│   │   └── templates/                 #   Secret templates
│   └── 04-optional/loki-showback/     # Optional: Loki log forwarding
│
├── chart/                              # Official RHOAI 3.4 Helm chart (v3.4.4, unmodified)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.schema.json
│   ├── profiles/                      #   default, rhaii
│   └── templates/                     #   Operator, DSC, DSCI, dependencies
│
├── setup/                              # One-time setup (not ArgoCD-managed)
│   ├── bootstrap/                     #   GitOps + SealedSecrets operators
│   │   ├── argocd-instance.yaml       #   ArgoCD with custom health checks
│   │   └── argocd-notifications.yaml  #   Webhook notification scaffolding
│   ├── argocd-projects.yaml           #   4 AppProjects (platform, config, workloads, spokes)
│   ├── rhacm/                         #   RHACM hub registration
│   └── kuadrant-restart/              #   One-time Kuadrant fix
│
├── clusters/                           # Hub-spoke management
│   ├── hubs/primary/                  #   Pull Model ApplicationSets + Placements + Policies
│   └── spokes/overlays/               #   Per-capability spoke profiles
│
├── profiles/                           # Deployment variants
│   ├── connected/                     #   Full platform + inference-only
│   └── disconnected/                  #   Air-gapped variants (platform, inference, servicemesh)
│
├── scripts/
│   ├── cluster-cleanup.sh             # Pre-deployment cleanup for shared clusters
│   ├── reseal-all.sh                  # Re-seal all 4 SealedSecrets
│   └── spoke-onboard.sh              # Onboard a spoke cluster
│
├── values/                             # Standalone Helm values for CLI use
│   ├── full-platform.yaml
│   └── inference-only.yaml
├── secrets/                            # Registry credential template
├── disconnected/                       # Image mirror config
├── DESIGN.md                           # Architecture decisions
└── README.md                           # This file
```

---

## Chart Source

Extracted from the official Red Hat OCI registry:

```bash
helm registry login registry.redhat.io
helm pull oci://registry.redhat.io/rhai/rhai-on-openshift-chart --version v3.4 --untar
```

- **Upstream**: [opendatahub-io/odh-gitops](https://github.com/opendatahub-io/odh-gitops)
- **Red Hat Developer article**: [Automating RHOAI installations with Helm and GitOps](https://developers.redhat.com/articles/2026/08/26/automating-red-hat-openshift-ai-installations-with-helm-and-gitops)
