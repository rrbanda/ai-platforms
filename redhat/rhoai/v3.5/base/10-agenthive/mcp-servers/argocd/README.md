# ArgoCD MCP Server

## Overview

The ArgoCD MCP server provides GitOps lifecycle management capabilities — application listing, sync, health checks, resource tree inspection, and event retrieval.

## Source

[argoproj-labs/mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd)

## Transport

`stdio` — The binary runs as a subprocess of the agent.

## Required Credentials

| Variable | Description |
|----------|-------------|
| `ARGOCD_BASE_URL` | ArgoCD server URL |
| `ARGOCD_API_TOKEN` | ArgoCD API token (created via ArgoCD CLI or UI) |
| `ARGOCD_INSECURE` | Set to `true` for self-signed certs |

## Tool Catalog

### Read Operations (Tier 1)
- `list_applications` — List all ArgoCD applications with health/sync status
- `get_application` — Get detailed application spec and status
- `get_application_resource_tree` — Show the resource hierarchy of an application
- `get_application_managed_resources` — List Kubernetes resources managed by an app
- `get_application_workload_logs` — Retrieve logs from application workloads
- `get_resource_events` — Get Kubernetes events for a managed resource
- `get_resource_actions` — List available actions for a resource
- `list_clusters` — List registered clusters
- `get_appproject` — Get AppProject details and RBAC

### Write Operations (Tier 2)
- `sync_application` — Trigger application sync (default: dry-run)

## Deployment

The ArgoCD MCP binary is embedded in the agent container image at build time. No separate deployment is needed.

## Creating an API Token

```bash
# Login to ArgoCD
argocd login <server> --username admin --password <password>

# Create a token for the agent
argocd account generate-token --account rhoai-copilot
```

Store the token in a Kubernetes Secret referenced by the agent deployment.
