# AI Platforms -- GitOps Deployment

Production-grade GitOps deployments for enterprise AI platforms on OpenShift,
managed through ArgoCD with RHACM hub-spoke multi-cluster support.

## Supported Platforms

| Vendor | Product | Versions | Status |
|--------|---------|----------|--------|
| **Red Hat** | [OpenShift AI (RHOAI)](redhat/rhoai/) | [v3.5](redhat/rhoai/v3.5/), [v3.4](redhat/rhoai/v3.4/) | Production |

## Quick Start -- RHOAI 3.5

### Prerequisites

- OpenShift 4.19+ with cluster-admin access
- `oc` CLI installed and authenticated
- `kubeseal` CLI installed (`brew install kubeseal`)
- RHACM installed (for hub-spoke; optional for single cluster)

### Deploy on a New Cluster

```bash
# 0. Pre-deployment cleanup (shared/reused clusters only)
./redhat/rhoai/v3.5/scripts/cluster-cleanup.sh --fix

# 1. Bootstrap GitOps + Sealed Secrets operators (one-time)
oc apply -k redhat/rhoai/v3.5/setup/bootstrap/
until oc apply -f redhat/rhoai/v3.5/setup/bootstrap/argocd-instance.yaml; do sleep 10; done
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s

# 2. Apply ArgoCD projects
oc apply -f redhat/rhoai/v3.5/setup/argocd-projects.yaml

# 3. Wire RHACM (if installed)
oc apply -k redhat/rhoai/v3.5/setup/rhacm/

# 4. Set up per-cluster overlay (creates overlay dir, seals secrets, patches apps)
./redhat/rhoai/v3.5/scripts/cluster-setup.sh <your-cluster-name>
git add redhat/rhoai/v3.5/overlays/<your-cluster-name>/
git commit -m "Add overlay for <your-cluster-name>"
git push

# 5. Deploy RHOAI
oc apply -f redhat/rhoai/v3.5/base/app-of-apps.yaml

# 6. Enable spoke management (optional, for hub clusters)
oc apply -k redhat/rhoai/v3.5/clusters/hubs/primary/
```

ArgoCD deploys in wave order: operators (wave 0) -> platform (wave 1) ->
cluster config (wave 2) -> workloads (wave 3). DSC takes ~15-30 min to
fully reconcile all 17 components.

See [redhat/rhoai/v3.5/README.md](redhat/rhoai/v3.5/README.md) for full documentation.

## Repository Structure

```
ai-platforms/
├── redhat/rhoai/
│   ├── v3.5/
│   │   ├── base/                  # Cluster-agnostic manifests (no secrets)
│   │   │   ├── app-of-apps.yaml   # Entry point: oc apply -f
│   │   │   ├── applications/      # ArgoCD child app manifests
│   │   │   ├── 00-operators/      # Wave 0: SM3 + MCP Gateway
│   │   │   ├── 02-config/         # Wave 2: Dashboard, EvalHub, MLflow, etc.
│   │   │   ├── 03-workloads/      # Wave 3: AutoRAG (OGX, Milvus, DSPA)
│   │   │   └── 04-optional/       # Optional: Loki showback
│   │   ├── chart/                  # Official RHOAI 3.5 Helm chart (unmodified)
│   │   ├── overlays/              # Per-cluster sealed secrets
│   │   │   ├── <cluster-a>/       # Each cluster gets its own overlay
│   │   │   └── <cluster-b>/
│   │   ├── setup/                  # One-time setup (not ArgoCD-managed)
│   │   │   ├── bootstrap/         # GitOps + SealedSecrets operators
│   │   │   ├── rhacm/             # RHACM hub registration
│   │   │   └── argocd-projects.yaml
│   │   ├── clusters/              # Hub-spoke management
│   │   │   ├── hubs/primary/      # ApplicationSets, Placements, Policies
│   │   │   └── spokes/overlays/   # Per-capability spoke profiles
│   │   ├── profiles/              # Deployment variants
│   │   │   ├── connected/         # Full platform + inference-only
│   │   │   └── disconnected/      # Air-gapped variants
│   │   ├── scripts/               # Automation
│   │   │   ├── cluster-setup.sh   # Onboard a new cluster
│   │   │   ├── cluster-cleanup.sh # Pre-deployment cleanup
│   │   │   ├── reseal-all.sh      # Re-seal secrets manually
│   │   │   └── spoke-onboard.sh   # Onboard a spoke cluster
│   │   ├── values/                # Standalone Helm values
│   │   ├── secrets/               # Secret templates
│   │   ├── disconnected/          # Mirror config
│   │   ├── DESIGN.md              # 18 architecture decisions
│   │   └── README.md              # Full deployment guide
│   └── v3.4/                      # Previous release (same structure)
│
├── nvidia/                         # NVIDIA AI products (planned)
├── ibm/                            # IBM AI products (planned)
└── upstream/                       # Open source projects (planned)
```

## Multi-Cluster Support

One repo serves multiple clusters. Each cluster gets its own `overlays/<name>/`
directory with cluster-specific sealed secrets. The `base/` manifests are shared.

```bash
# Onboard a new cluster:
./redhat/rhoai/v3.5/scripts/cluster-setup.sh my-new-cluster
git add redhat/rhoai/v3.5/overlays/my-new-cluster/
git commit -m "Add overlay for my-new-cluster" && git push
```

For hub-spoke at fleet scale (20+ clusters), see
[clusters/hubs/primary/](redhat/rhoai/v3.5/clusters/hubs/primary/) for
RHACM Pull Model ApplicationSets with label-driven capability selection.

## Architecture Highlights

- **Official Helm chart** extracted from Red Hat OCI registry, committed to Git
- **App-of-apps pattern** with sync-wave ordering (operators -> platform -> config -> workloads)
- **Per-cluster overlays** for secrets -- `base/` is cluster-agnostic, `overlays/` per cluster
- **Hub-spoke multi-cluster** via RHACM Pull Model with label-driven capability selection
- **ArgoCD AppProjects** for RBAC isolation (platform, config, workloads, spokes)
- **9 custom health checks** for RHOAI CRDs (DSC, KServe, OGX, EvalHub, MLflow, etc.)
- **Progressive rollout** for fleet-scale spoke management (canary -> fleet)

See [DESIGN.md](redhat/rhoai/v3.5/DESIGN.md) for all 18 architecture decisions.

## License

See [LICENSE](LICENSE).
