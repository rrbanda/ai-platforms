# OpenShift MCP Server

Shared cluster MCP for AgentHive ops agents (pod-health-watcher, stale-image-finder, pr-review-bot, rhoai-copilot).

## Transport

`streamable-http` at `/mcp`.

## GitOps

ArgoCD Application `openshift-mcp` deploys this directory. Do not `oc apply` by hand on a GitOps cluster.

## DNS (must match agent `OPENSHIFT_MCP_URL`)

```
http://openshift-mcp-v2.openshift-mcp-server.svc.cluster.local:8080/mcp
```

Service `openshift-mcp-v2` in namespace `openshift-mcp-server`. NetworkPolicy allows ingress from `rhoai-copilot`, `pod-health-watcher`, `stale-image-finder`, and `pr-review-bot`. Add new agent namespaces there when you onboard them ([docs/04](../../docs/04-agent-deployment.md)).

## RBAC

The server ServiceAccount is bound to `cluster-reader` (read-only cluster access). Agent sandbox privileged SCC is unrelated and must stay as documented in [01-cluster-prerequisites.md](../../docs/01-cluster-prerequisites.md).

## Tool catalog

- `pods_list` / `pods_get` / `pods_log`
- `events_list`
- `nodes_list` / `nodes_get`
- `namespaces_list`
- `resources_get` / `resources_list`
