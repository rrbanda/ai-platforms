# MLflow MCP Server

## Overview

The MLflow MCP server exposes experiment tracking, model registry, and run management capabilities via MCP.

## Source

Built-in to MLflow SDK: `mlflow mcp run`

## Transport

`streamable-http` at `/mcp` endpoint, configured via `FASTMCP_*` environment variables.

## Deployment

Deploy as an `MCPServer` CR or standalone:

```yaml
apiVersion: mcp.opendatahub.io/v1alpha1
kind: MCPServer
metadata:
  name: mlflow-mcp
  namespace: redhat-ods-applications
spec:
  source:
    containerImage:
      ref: quay.io/rbrhssa/mlflow-mcp:3.15.0-v2
  config:
    transport: streamable-http
  env:
    - name: MLFLOW_TRACKING_URI
      value: "http://mlflow.redhat-ods-applications.svc:5000"
```

### Environment Variables (baked into image)

| Variable | Value | Purpose |
|----------|-------|---------|
| `FASTMCP_TRANSPORT` | `streamable-http` | MCP transport protocol |
| `FASTMCP_HOST` | `0.0.0.0` | Bind address |
| `FASTMCP_PORT` | `8080` | Listen port |
| `FASTMCP_STREAMABLE_HTTP_PATH` | `/mcp` | MCP endpoint path |

### Authentication

The MLflow MCP pod uses a `sitecustomize.py` script (mounted via ConfigMap) that auto-injects the ServiceAccount token as `MLFLOW_TRACKING_TOKEN` at Python startup.

## Tool Catalog

- Experiment listing and search
- Run creation and logging
- Metric querying and comparison
- Model version management
- Artifact access
