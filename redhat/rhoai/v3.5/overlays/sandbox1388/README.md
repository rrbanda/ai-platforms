# sandbox1388 Overlay

Basic RHOAI deployment overlay. This cluster has:
- `config/` -- DSC/DSCI configuration with cluster-specific sealed secrets
- `workloads/` -- AutoRAG workload with sealed secrets for S3 and LLM API

This cluster does **not** have MCP Gateway, Keycloak, or the OCP Agent deployed.
To add MCP support, create a `mcp-auth/` overlay following the `afred-34-test` pattern
with the correct OIDC audience and Keycloak issuer URL for this cluster.
