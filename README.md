# AI Platforms -- GitOps Deployment

Production-grade GitOps deployments for enterprise AI platforms on OpenShift,
managed through ArgoCD with RHACM hub-spoke multi-cluster support.

## Supported Platforms

| Vendor | Product | Versions | Status |
|--------|---------|----------|--------|
| **Red Hat** | [OpenShift AI (RHOAI)](redhat/rhoai/) | [v3.5](redhat/rhoai/v3.5/), [v3.4](redhat/rhoai/v3.4/) | Production |

## Quick Start

### RHOAI 3.5

```bash
# 0. Pre-deployment cleanup (shared/reused clusters only)
./redhat/rhoai/v3.5/scripts/cluster-cleanup.sh --fix

# 1. Bootstrap (one-time)
oc apply -k redhat/rhoai/v3.5/setup/bootstrap/

# 2. Seal secrets for this cluster
./redhat/rhoai/v3.5/scripts/reseal-all.sh
git add redhat/rhoai/v3.5/base/*/sealed-*.yaml && git commit -m "Seal secrets" && git push

# 3. Deploy
oc apply -f redhat/rhoai/v3.5/base/app-of-apps.yaml

# 3. Enable spoke management (optional)
oc apply -k redhat/rhoai/v3.5/clusters/hubs/primary/
```

See [redhat/rhoai/v3.5/README.md](redhat/rhoai/v3.5/README.md) for full documentation.

## Repository Structure

```
ai-platforms/
├── redhat/                     # Red Hat products
│   ├── rhoai/                  # Red Hat OpenShift AI
│   │   ├── v3.5/              # Latest (17 DSC components, hub-spoke, all DP/TP features)
│   │   └── v3.4/              # Previous release
│   ├── rhelai/                 # Red Hat Enterprise Linux AI (planned)
│   └── shared/                 # Shared across Red Hat AI products (planned)
├── nvidia/                     # NVIDIA AI products (planned)
├── ibm/                        # IBM AI products (planned)
└── upstream/                   # Open source projects (planned)
```

## Architecture Highlights

- **Official Helm chart** extracted from Red Hat OCI registry, committed to Git
- **App-of-apps pattern** with sync-wave ordering (operators -> platform -> config -> workloads)
- **Hub-spoke multi-cluster** via RHACM Pull Model with label-driven capability selection
- **SealedSecrets** for encrypted secrets safe in Git
- **ArgoCD AppProjects** for RBAC isolation (platform, config, workloads, spokes)
- **Progressive rollout** for fleet-scale spoke management (canary -> fleet)

See [redhat/rhoai/v3.5/DESIGN.md](redhat/rhoai/v3.5/DESIGN.md) for all 18 architecture decisions.

## Adding a New Platform

1. Create `<vendor>/<product>/v<version>/` directory
2. Add `base/`, `setup/`, `chart/` following the RHOAI pattern
3. Write `README.md` and `DESIGN.md`
4. All platforms share the same `.gitignore`, `.gitleaks.toml`, and `.pre-commit-config.yaml`

## License

See [LICENSE](LICENSE).
