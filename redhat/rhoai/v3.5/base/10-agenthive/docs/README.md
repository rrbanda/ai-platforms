# Platform documentation

Start at the [root README](../../README.md) for architecture, quick start, and how agents are packaged.

GitOps is the only supported deploy path. Do not use `platform/deploy/` for AgentHive agents; that tree is leftover disconnected RHOAI examples.

| Doc | Topic |
|-----|--------|
| [01-cluster-prerequisites.md](01-cluster-prerequisites.md) | Cluster, operators, OpenShell TLS |
| [02-infrastructure.md](02-infrastructure.md) | MinIO, Milvus, OGX, DSPA, MCP |
| [03-autorag-pipeline.md](03-autorag-pipeline.md) | AutoRAG (RFP agent) |
| [04-agent-deployment.md](04-agent-deployment.md) | **Add a new agent** (required checklist) |
| [05-evaluation-mlflow.md](05-evaluation-mlflow.md) | EvalHub / RAGAS / MLflow traces |
| [06-troubleshooting.md](06-troubleshooting.md) | Common failures |
| [07-corpus-management.md](07-corpus-management.md) | Per-agent knowledge corpora |
| [08-open-webui.md](08-open-webui.md) | One Open WebUI in front of multiple Hermes agents |
| [09-rfp-agent-rhoai.md](09-rfp-agent-rhoai.md) | rfp-agent job spec: any OpenShift AI RFP / RFI |

Bootstrap: [../gitops/bootstrap/README.md](../gitops/bootstrap/README.md).
