# Platform Engineer Persona

## Role

Responsible for installing, configuring, and maintaining the RHOAI platform on OpenShift. Manages operator lifecycle, cluster resources, RBAC, and GitOps pipelines.

## Primary Lifecycle Phases

- **Install** — Deploy operators, configure disconnected environments, validate prerequisites
- **Administer** — Manage DSC configuration, operator upgrades, platform health
- **Monitor** — ArgoCD sync health, drift detection, cluster resource usage

## Key Skills

| Skill | Phase | Usage |
|-------|-------|-------|
| `rhoai-disconnected-deploy` | Install | End-to-end disconnected deployment guidance |
| `rhoai-install-validator` | Install | Pre/post-install validation checks |
| `gitops-config-generator` | Install | Generate Kustomize overlays for new environments |
| `rhoai-dsc-inspector` | Administer | Inspect and troubleshoot DataScienceCluster |
| `rhoai-platform-status` | Administer | Full platform health overview |
| `rhoai-upgrade-advisor` | Administer | Plan and validate operator upgrades |
| `argocd-health-check` | Monitor | Application sync and health status |
| `argocd-diagnose-sync` | Monitor | Root-cause analysis for sync failures |

## Example Interactions

- "Deploy RHOAI 2.19 on my disconnected cluster using the internal registry"
- "Why is the gpu-operator application out of sync?"
- "Generate the GitOps overlay for our new production cluster"
- "Is it safe to upgrade from RHOAI 2.18 to 2.19?"
- "Show me the current DSC configuration and any degraded components"

## MCP Servers Used

- ArgoCD MCP (primary)
- OpenShift MCP
- GitHub MCP (for PR-based config changes)
