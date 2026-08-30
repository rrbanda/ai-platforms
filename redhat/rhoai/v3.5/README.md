# RHOAI 3.5 -- GitOps Deployment

Deploy Red Hat OpenShift AI **3.5** on OpenShift using the official Helm chart,
managed entirely through OpenShift GitOps (ArgoCD).

| | Details |
|---|---|
| **RHOAI version** | 3.5 (chart v3.5.0) |
| **Chart source** | `oci://registry.redhat.io/rhai/rhai-on-openshift-chart:v3.5` |
| **OCP requirement** | 4.19+ |
| **Repo** | `https://github.com/rrbanda/ai-platforms.git` (branch: `main`) |

---

## Architecture

```
oc apply -f base/app-of-apps.yaml
    |
    +-- Wave 0: Prerequisite operators
    |       Service Mesh 3.x + MCP Gateway operator
    |
    +-- Wave 1: RHOAI platform (Helm chart)
    |       RHOAI operator + DSC with 17 components + Gateways
    |
    +-- Wave 2: Cluster config
    |       Dashboard features, EvalHub, MLflow, NemoGuardrails,
    |       MaaS PostgreSQL, MCP Gateway, vector stores
    |
    +-- Wave 3: Application workloads
            OGXServer + Milvus + DSPA (AutoRAG stack)
```

### ArgoCD Applications

| Wave | App | Project | Source |
|------|-----|---------|--------|
| 0 | `rhoai-servicemesh` | rhoai-platform | `base/00-operators/servicemesh` |
| 0 | `rhoai-mcp-gateway-operator` | rhoai-platform | `base/00-operators/mcp-gateway` |
| 1 | `rhoai-platform` | rhoai-platform | `chart/` (Helm) |
| 2 | `rhoai-cluster-config` | rhoai-config | `overlays/<cluster>/config/` |
| 3 | `autorag-workload` | rhoai-workloads | `overlays/<cluster>/workloads/` |
| -- | `rhoai-deploy` (parent) | default | `base/applications/` |

### What the Helm chart deploys

17 DSC components: Dashboard, KServe (NIM, WVA), AI Gateway (MaaS, BatchGateway),
AIPipelines (Argo Workflows), Kueue, Ray, Trainer, TrainingOperator, Workbenches,
ModelRegistry, TrustyAI, MLflow Operator, Feast Operator, OGX, Spark Operator,
MCP Lifecycle Operator. Plus 11+ dependency operators, DSCInitialization, Gateways.

### What cluster-config adds

OdhDashboardConfig (27 DP/TP feature flags), EvalHub, MLflow, NemoGuardrails,
User Workload Monitoring, MaaS PostgreSQL, MCP Gateway, MCP server registry,
vector stores for Playground RAG.

### What the workload layer adds

OGXServer (RAG backbone), Milvus vector database + etcd, DSPA pipeline server
with built-in MinIO.

---

## Prerequisites

| Requirement | Details |
|---|---|
| OpenShift | 4.19+ with cluster-admin access |
| `oc` CLI | Installed and authenticated |
| `kubeseal` CLI | `brew install kubeseal` |
| Helm | 3.17+ (optional, for local testing) |
| RHACM | Required for hub-spoke (optional for single cluster) |

---

## Deploy to a New Cluster

### Step 0: Pre-deployment cleanup (shared clusters only)

If the cluster had a previous RHOAI installation, clean up stale CRs:

```bash
./scripts/cluster-cleanup.sh        # Detect stale resources
./scripts/cluster-cleanup.sh --fix  # Auto-remediate
```

### Step 1: Bootstrap (one-time)

```bash
oc apply -k setup/bootstrap/
until oc apply -f setup/bootstrap/argocd-instance.yaml; do sleep 10; done
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
oc apply -f setup/argocd-projects.yaml
```

### Step 2: Wire RHACM (if installed)

```bash
oc apply -k setup/rhacm/
```

### Step 3: Set up per-cluster overlay

Each cluster needs its own sealed secrets. The `cluster-setup.sh` script
creates the overlay directory, seals secrets, and patches ArgoCD apps:

```bash
# Set environment variables for secrets (or leave blank to be prompted)
export LLM_API_KEY="your-api-key"
export MAAS_DB_PASSWORD="your-db-password"

# Run setup
./scripts/cluster-setup.sh my-cluster-name

# Commit and push
git add overlays/my-cluster-name/
git commit -m "Add overlay for my-cluster-name"
git push
```

### Step 4: Deploy

```bash
oc apply -f base/app-of-apps.yaml
```

ArgoCD discovers child Applications and deploys in wave order.
DSC takes ~15-30 minutes to fully reconcile.

### Step 5: Verify

```bash
# All 6 apps should be Synced/Healthy
oc get applications.argoproj.io -n openshift-gitops

# DSC should be Ready
oc get datasciencecluster -o jsonpath='{.items[0].status.phase}'

# AutoRAG pods should be running
oc get pods -n autorag
```

---

## Multi-Cluster Architecture

One Git repo serves all clusters. Secrets are isolated per cluster via overlays:

```
base/                          # Shared (cluster-agnostic, no secrets)
overlays/
├── cluster-a/                 # Sealed with cluster-a's cert
│   ├── config/
│   └── workloads/
├── cluster-b/                 # Sealed with cluster-b's cert
│   ├── config/
│   └── workloads/
```

### Onboard a new cluster

```bash
./scripts/cluster-setup.sh new-cluster
git add overlays/new-cluster/ && git commit -m "Add new-cluster" && git push
```

### Hub-spoke at scale

For 20+ clusters, use RHACM Pull Model:

```bash
oc apply -k clusters/hubs/primary/
```

Then label spoke clusters:

```bash
oc label managedcluster spoke-1 rhoai.io/platform=true rhoai.io/gpu=true
```

See [clusters/hubs/primary/](clusters/hubs/primary/) for ApplicationSets,
Placements, and Policies.

---

## Deployment Profiles

| Profile | Description | How to activate |
|---|---|---|
| Full platform (default) | All 17 DSC components | Already in `base/applications/rhoai-platform.yaml` |
| Inference only | KServe + deps only | Copy `profiles/connected/inference-only.yaml` |
| Disconnected | Full platform with mirrored catalog | Copy `profiles/disconnected/platform.yaml` |

---

## Optional Components

### Loki-based MaaS showback

Requires the Cluster Logging operator (not part of RHOAI). If installed:

```bash
oc apply -k base/04-optional/loki-showback/
```

---

## File Structure

```
v3.5/
├── base/                              # Cluster-agnostic (ArgoCD-managed)
│   ├── app-of-apps.yaml              # Entry point
│   ├── applications/                  # Child app manifests
│   ├── 00-operators/                  # Wave 0: SM3 + MCP Gateway
│   │   ├── servicemesh/
│   │   └── mcp-gateway/
│   ├── 02-config/                     # Wave 2: Dashboard, EvalHub, MLflow, etc.
│   │   └── templates/                 # Secret templates (safe to commit)
│   ├── 03-workloads/autorag/          # Wave 3: OGX, Milvus, DSPA
│   │   └── templates/                 # Secret templates
│   └── 04-optional/loki-showback/     # Optional: Loki log forwarding
│
├── chart/                              # Official RHOAI 3.5 Helm chart (unmodified)
│
├── overlays/                           # Per-cluster sealed secrets
│   ├── <cluster-name>/config/         # MaaS DB credentials (sealed)
│   └── <cluster-name>/workloads/      # LLM API key, S3 creds (sealed)
│
├── setup/                              # One-time setup (not ArgoCD-managed)
│   ├── bootstrap/                     # GitOps + SealedSecrets operators
│   │   ├── argocd-instance.yaml       # ArgoCD with 9 custom health checks
│   │   └── argocd-notifications.yaml  # Webhook notification scaffolding
│   ├── argocd-projects.yaml           # 4 AppProjects (platform, config, workloads, spokes)
│   ├── rhacm/                         # RHACM hub registration
│   └── kuadrant-restart/              # One-time Kuadrant fix
│
├── clusters/                           # Hub-spoke management
│   ├── hubs/primary/                  # Pull Model ApplicationSets + Placements + Policies
│   └── spokes/overlays/               # Per-capability spoke profiles
│
├── profiles/                           # Deployment variants
│   ├── connected/                     # Full platform + inference-only
│   └── disconnected/                  # Air-gapped variants
│
├── scripts/
│   ├── cluster-setup.sh               # Onboard a new cluster (overlay + seal + patch)
│   ├── cluster-cleanup.sh             # Pre-deployment cleanup for shared clusters
│   ├── reseal-all.sh                  # Manual secret re-sealing
│   └── spoke-onboard.sh              # Onboard a spoke cluster
│
├── values/                             # Standalone Helm values for CLI use
├── secrets/                            # Registry credential template
├── disconnected/                       # Image mirror config
├── DESIGN.md                           # 18 architecture decisions
└── README.md                           # This file
```

---

## Troubleshooting

**Stale CRs from previous tenant:**
```bash
./scripts/cluster-cleanup.sh --fix
```

**DSC stuck Not Ready:**
```bash
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[?(@.status!="True")]}{.type}: {.message}{"\n"}{end}'
```

**SealedSecret won't decrypt:**
The secret was sealed for a different cluster. Re-seal:
```bash
./scripts/cluster-setup.sh <your-cluster-name>
```

**ArgoCD "upload-pack: not our ref":**
Stale git cache. Restart repo-server:
```bash
oc rollout restart deployment/openshift-gitops-repo-server -n openshift-gitops
```

---

## Chart Source

Extracted from the official Red Hat OCI registry:

```bash
helm registry login registry.redhat.io
helm pull oci://registry.redhat.io/rhai/rhai-on-openshift-chart --version v3.5 --untar
```
