# SRE / Operations Persona

## Role

Responsible for platform reliability, incident response, and operational visibility. Focuses on uptime, alerting, capacity management, and rapid troubleshooting.

## Primary Lifecycle Phases

- **Monitor** — Health checks, alerting, drift detection, daily reports
- **Administer** — Platform status, upgrade readiness
- **Plan** — Capacity forecasting, resource utilization

## Key Skills

| Skill | Phase | Usage |
|-------|-------|-------|
| `argocd-health-check` | Monitor | Real-time application health overview |
| `argocd-diagnose-sync` | Monitor | Root-cause sync failure analysis |
| `daily-report-generator` | Monitor | Automated daily health summaries |
| `incident-runbook` | Monitor | Guided incident response procedures |
| `rhoai-platform-status` | Administer | Full platform component health |
| `capacity-forecaster` | Plan | Project when resources will be exhausted |
| `rhoai-upgrade-advisor` | Administer | Assess upgrade risk and impact |

## Example Interactions

- "Give me the platform health report"
- "We're getting alerts — what's degraded right now?"
- "Show me all out-of-sync applications and their root causes"
- "How much cluster capacity is remaining for model serving?"
- "Walk me through the incident response for a failing inference service"

## MCP Servers Used

- ArgoCD MCP (primary)
- OpenShift MCP
- RHOAI MCP
- MLflow MCP (for model endpoint health)
