# 02 — Infrastructure

ArgoCD Application `rfp-infra` deploys `platform/gitops/infra/`:

| Component | Namespace / location | Role |
|-----------|----------------------|------|
| MinIO | `minio` | Object storage for corpus and pipelines |
| Milvus + etcd | `milvus` | Vector store |
| OGX | `rfp-agent` | Embeddings and vector store API |
| DSPA | `rfp-agent` | Data Science Pipelines (AutoRAG) |
| Ingest Job | `rfp-agent` (PostSync) | Uploads `agents/rfp-agent/corpus/` and indexes via OGX |
| OpenShell SA | per agent namespace | Sandbox identity + privileged SCC |

OpenShell itself is Application `openshell` (Helm). Secrets are Application `rfp-secrets` (sync wave -5).

## MCP servers (GitOps)

| Application | Path | DNS used by agents |
|-------------|------|--------------------|
| `openshift-mcp` | `platform/mcp-servers/openshift` | `http://openshift-mcp-v2.openshift-mcp-server.svc.cluster.local:8080/mcp` |
| `rhoai-mcp` | `platform/mcp-servers/rhoai` | `http://rhoai-mcp.rhoai-copilot.svc:8000/mcp` |

ArgoCD MCP and GitHub MCP are **stdio in the agent image** (no separate Deployment). MLflow MCP remains optional: apply `platform/mcp-servers/mlflow/deployment.yaml` only when MLflow is running in `redhat-ods-applications`.

Do not `oc apply` MCP manifests by hand on a GitOps cluster. Push to git.

## Ingest path

The ingest Job clones this repo and reads:

```
agents/rfp-agent/corpus/
```

`platform/corpus/` does not exist. See [07-corpus-management.md](07-corpus-management.md).
