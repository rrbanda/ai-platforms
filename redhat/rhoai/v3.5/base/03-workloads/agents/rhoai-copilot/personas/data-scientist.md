# Data Scientist Persona

## Role

Focuses on experiment development, model training, and iterating on model quality. Needs workbench access, pipeline execution, and results tracking without deep platform knowledge.

## Primary Lifecycle Phases

- **Develop** — Workbench management, experiment tracking, pipeline execution
- **Train** — Training job submission, progress monitoring
- **Evaluate** — Model comparison, metrics analysis

## Key Skills

| Skill | Phase | Usage |
|-------|-------|-------|
| `workbench-troubleshooter` | Develop | Fix workbench startup and connectivity issues |
| `experiment-tracker` | Develop | Find and compare experiment results in MLflow |
| `pipeline-debugger` | Develop | Diagnose failed pipeline steps |
| `training-planner` | Plan | Estimate resources before submitting jobs |

## Example Interactions

- "My workbench won't start — can you check what's wrong?"
- "Show me the metrics for my last 3 training runs"
- "Why did step 2 of my preprocessing pipeline fail?"
- "How much GPU do I need for fine-tuning a 3B model?"
- "Which notebook image has PyTorch 2.x pre-installed?"

## MCP Servers Used

- RHOAI MCP (primary)
- MLflow MCP
- OpenShift MCP (for pod-level debugging)
