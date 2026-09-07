# Workflows

Workflows are multi-step autonomous procedures that compose skills into end-to-end operations. They can be triggered on a schedule (cron), by an event, or manually.

## Structure

Each workflow is a YAML file describing:
- **trigger**: When the workflow runs (cron, event, manual)
- **steps**: Ordered list of skills to invoke with parameters
- **escalation**: What to do when a step fails or needs human input

## Available Workflows

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `daily-health-report.yaml` | Cron (08:00 UTC) | Full platform health check across all ArgoCD apps |
| `drift-detection.yaml` | Cron (every 4h) | Compare cluster state against Git desired state |
| `incident-response.yaml` | Manual | Guided troubleshooting for platform degradation |
| `model-promotion.yaml` | Manual | End-to-end model promotion from dev to production |

## Creating a Workflow

See the template in `_template/workflow.yaml.template`.
