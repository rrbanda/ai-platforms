# MCP Server Integrations

This directory contains deployment manifests and tool catalogs for each Model Context Protocol (MCP) server the agent connects to.

## Architecture

```
┌─────────────────┐     ┌────────────────────┐
│  RHOAI Copilot  │────▶│  ArgoCD MCP        │──▶ ArgoCD API
│  (Agent)        │────▶│  RHOAI MCP         │──▶ OpenShift AI APIs
│                 │────▶│  OpenShift MCP     │──▶ Kubernetes API
│                 │────▶│  MLflow MCP        │──▶ MLflow Server
│                 │────▶│  GitHub MCP        │──▶ GitHub API
└─────────────────┘     └────────────────────┘
```

## Server Summary

| Server | Transport | Tools | GitOps |
|--------|-----------|-------|--------|
| ArgoCD | stdio | 10 | In agent image (`argocd-mcp`). Token in `rhoai-copilot-auth`. |
| RHOAI | HTTP | 35+ | Application `rhoai-mcp` → `platform/mcp-servers/rhoai` |
| OpenShift | HTTP | 20+ | Application `openshift-mcp` → `platform/mcp-servers/openshift` |
| MLflow | HTTP | 15+ | Optional: `oc apply` `mlflow/deployment.yaml` when MLflow exists |
| GitHub | stdio | 26 | `npx` in the agent; PAT in `*-auth` `github-token` |

## Disconnected Environments

In air-gapped clusters:
- All HTTP-based MCP servers run as internal Services (no external egress)
- `ArgoCD MCP` binary is embedded in the agent container image
- `GitHub MCP` is typically replaced with a Gitea or GitLab MCP, or disabled
- Container images for MCP servers must be pre-mirrored to the internal registry
