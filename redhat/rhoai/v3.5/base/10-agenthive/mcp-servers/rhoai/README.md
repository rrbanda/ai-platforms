# RHOAI MCP Server

## Overview

The RHOAI MCP server provides direct access to Red Hat OpenShift AI platform operations — managing data science projects, workbenches, model serving, pipelines, and training jobs.

## Source

[opendatahub-io/rhoai-mcp](https://github.com/opendatahub-io/rhoai-mcp)

## Transport

`streamable-http` at `/mcp` endpoint.

## Deployment

GitOps: ArgoCD Application `rhoai-mcp` deploys this directory into `rhoai-copilot`.

```
http://rhoai-mcp.rhoai-copilot.svc:8000/mcp
```

## Tool Catalog (35+ tools)

### Projects and Cluster
- `list_data_science_projects`, `get_project_details`, `get_project_status`
- `get_cluster_resources`, `cluster_summary`, `project_summary`

### Workbenches
- `list_workbenches`, `get_workbench`, `get_workbench_url`, `list_notebook_images`
- `create_workbench` (Tier 2), `start_workbench`, `stop_workbench`

### Model Serving
- `list_inference_services`, `get_inference_service`, `list_serving_runtimes`
- `get_model_endpoint`, `prepare_model_deployment`, `check_deployment_prerequisites`
- `estimate_serving_resources`, `deploy_model` (Tier 2)

### Model Registry
- `list_registered_models`, `get_registered_model`, `list_model_versions`, `get_model_artifacts`

### Training
- `list_training_jobs`, `get_training_progress`, `list_training_runtimes`, `estimate_resources`

### Data and Storage
- `list_data_connections`, `list_storage`, `get_pipeline_server`
- `create_s3_data_connection` (Tier 2)

### Diagnostics
- `explore_cluster`, `diagnose_resource`, `multi_resource_status`, `resource_status`, `list_resource_names`
