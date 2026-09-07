# MLOps Engineer Persona

## Role

Responsible for the ML workflow infrastructure: model pipelines, serving runtimes, model promotion, and experiment management. Bridges the gap between data science and production.

## Primary Lifecycle Phases

- **Deploy** — Model serving, promotion workflows, runtime selection
- **Develop** — Pipeline management, experiment tracking
- **Plan** — Capacity estimation, serving runtime selection, training resource planning
- **Monitor** — Model health, inference latency, experiment comparison

## Key Skills

| Skill | Phase | Usage |
|-------|-------|-------|
| `model-promotion-workflow` | Deploy | Promote models from dev to production |
| `rhoai-model-lifecycle` | Deploy | Manage model serving and versions |
| `serving-runtime-advisor` | Plan | Recommend optimal serving runtime for a model |
| `experiment-tracker` | Develop | Query MLflow for experiment results |
| `pipeline-debugger` | Develop | Troubleshoot data science pipeline failures |
| `training-planner` | Plan | Estimate resources for training jobs |
| `capacity-forecaster` | Plan | Project infrastructure needs for model serving |

## Example Interactions

- "Promote the fraud-detection model from dev to staging"
- "Compare the last 5 training runs for the sentiment-analysis experiment"
- "Which serving runtime should I use for a 7B parameter model?"
- "Why did my pipeline run fail in the data-prep stage?"
- "How much GPU memory will I need to serve Llama-3-8B with vLLM?"

## MCP Servers Used

- RHOAI MCP (primary)
- MLflow MCP
- ArgoCD MCP (for deployment status)
- GitHub MCP (for PR-based promotion)
