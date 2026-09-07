---
name: model-registry-manager
description: "Register, version, and manage models in the RHOAI Model Registry — govern model lifecycle from experimentation through production serving."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Model Registry, Versioning, Governance, MLOps]
---

# Model Registry Manager

Register, version, and manage models in the RHOAI Model Registry for lifecycle governance. The Model Registry bridges experimentation and serving by providing a centralized catalog of versioned model artifacts with metadata, labels, and deployment history.

## Trigger Conditions

- "Register this model in the registry"
- "Create a new version for my model"
- "List models in the registry"
- "How do I deploy a model from the registry?"
- "Tag this model version for production"
- "Archive old model versions"
- "Set up model registry for my project"
- "Compare model versions"
- "Add metadata to my model"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | list_registered_models | List all registered models |
| mcp_rhoai | get_registered_model | Get model details and metadata |
| mcp_rhoai | list_model_versions | List versions for a model |
| mcp_rhoai | get_model_artifacts | Get artifact URIs and format info |
| mcp_rhoai | list_inference_services | Check deployments from registry |
| mcp_rhoai | cluster_summary | Cluster and namespace context |
| mcp_openshift | resources_list | List ModelRegistry CRs and related resources |

## Procedure

### Phase 1: Registry Status Assessment

1. Call `mcp_rhoai` → `cluster_summary` to determine:
   - DSC component `modelregistry` management state (must be Managed)
   - Available Model Registry instances
   - User's current namespace context
2. Call `mcp_openshift` → `resources_list` with kind=`ModelRegistry` to enumerate registry instances:
   - Registry name and namespace
   - Database backend (MySQL or PostgreSQL)
   - REST API endpoint
   - Health status
3. If no registry exists or the component is not Managed, advise the user on prerequisites:
   - DSC must have `modelregistry: managementState: Managed`
   - An admin must create the ModelRegistry CR
   - External database must be provisioned for production use

### Phase 2: Model Registration

4. To register a new model, gather required information:
   - **Model name**: unique identifier within the registry
   - **Description**: purpose and capabilities
   - **Owner**: team or individual responsible
   - **Labels**: key-value pairs for categorization (e.g., `task=text-generation`, `env=staging`)
   - **Custom properties**: framework, architecture, base model
5. Generate the registration API call:
   ```
   POST /api/model_registry/v1alpha3/registered_models
   {
     "name": "{model_name}",
     "description": "{description}",
     "owner": "{owner}",
     "customProperties": {
       "task": { "string_value": "{task}" },
       "framework": { "string_value": "{framework}" },
       "base_model": { "string_value": "{base_model}" }
     }
   }
   ```
6. Alternatively, guide the user through Dashboard registration:
   - Navigate to: **AI Hub → Model Registry → {registry_name}**
   - Click **Register model**
   - Fill in name, description, and custom properties

### Phase 3: Version Management

7. To create a new model version, collect:
   - **Version name**: semantic version or descriptive label (e.g., `v1.2.0`, `finetuned-2024-q4`)
   - **Description**: what changed from previous version
   - **Author**: who created this version
   - **State**: LIVE (active) or ARCHIVED
8. Generate the version creation API call:
   ```
   POST /api/model_registry/v1alpha3/registered_models/{model_id}/versions
   {
     "name": "{version_name}",
     "description": "{changes}",
     "author": "{author}",
     "state": "LIVE",
     "customProperties": {
       "training_dataset": { "string_value": "{dataset}" },
       "metrics_accuracy": { "double_value": {accuracy} },
       "quantization": { "string_value": "{quant_method}" }
     }
   }
   ```
9. Call `mcp_rhoai` → `list_model_versions` to verify creation and list all versions

### Phase 4: Artifact Management

10. Add model artifacts to a version:
    - **URI**: S3 path, OCI image, or PVC path to model weights
    - **Model format**: safetensors, ONNX, pytorch, GGUF
    - **Storage type**: S3, OCI, PVC
11. Generate the artifact creation API call:
    ```
    POST /api/model_registry/v1alpha3/model_versions/{version_id}/artifacts
    {
      "name": "{artifact_name}",
      "uri": "s3://{bucket}/{path}",
      "modelFormatName": "{format}",
      "modelFormatVersion": "{version}",
      "storageKey": "{data_connection_name}",
      "storagePath": "{path_within_bucket}"
    }
    ```
12. Call `mcp_rhoai` → `get_model_artifacts` to verify the artifact is accessible

### Phase 5: Deploy from Registry

13. To deploy a model from the registry:
    - Call `mcp_rhoai` → `get_registered_model` to get the model ID
    - Call `mcp_rhoai` → `list_model_versions` to select the target version
    - Call `mcp_rhoai` → `get_model_artifacts` to get the artifact URI
14. Guide deployment via Dashboard:
    - Navigate to: **AI Hub → Model Registry → {registry_name} → {model_name}**
    - Select version → Click **Deploy**
    - Choose serving runtime, hardware profile, and target namespace
15. Or generate the InferenceService manifest referencing the registry artifact:
    ```yaml
    apiVersion: serving.kserve.io/v1beta1
    kind: InferenceService
    metadata:
      name: {model_name}
      labels:
        modelregistry.opendatahub.io/registered-model-id: "{model_id}"
        modelregistry.opendatahub.io/model-version-id: "{version_id}"
    spec:
      predictor:
        model:
          modelFormat:
            name: {format}
          storageUri: "{artifact_uri}"
    ```

### Phase 6: Lifecycle Operations

16. **Archive a version**: Set state to ARCHIVED to prevent new deployments
    ```
    PATCH /api/model_registry/v1alpha3/model_versions/{version_id}
    { "state": "ARCHIVED" }
    ```
17. **Label for A/B testing**: Add labels to identify canary/baseline versions
    ```
    PATCH /api/model_registry/v1alpha3/model_versions/{version_id}
    {
      "customProperties": {
        "deployment_role": { "string_value": "canary" },
        "traffic_percentage": { "int_value": 10 }
      }
    }
    ```
18. **Environment tagging**: Use labels to track promotion stages
    - `env=dev` → `env=staging` → `env=production`
19. Call `mcp_rhoai` → `list_inference_services` to verify active deployments match registry state

## Output Format

```
# Model Registry Report — {timestamp}

## Registry Instance
- Name: {registry_name}
- Namespace: {namespace}
- Database: {mysql|postgresql}
- API endpoint: {url}
- Status: {Healthy|Degraded}

## Registered Models
| Model | Owner | Versions | Latest | State | Deployments |
|-------|-------|----------|--------|-------|-------------|
| {name} | {owner} | {count} | {version} | {LIVE/ARCHIVED} | {count} |

## Model Detail: {model_name}
### Versions
| Version | Author | State | Created | Artifacts | Deployed |
|---------|--------|-------|---------|-----------|----------|
| {version} | {author} | {state} | {date} | {count} | {yes/no} |

### Artifacts (latest version)
| Artifact | Format | URI | Storage |
|----------|--------|-----|---------|
| {name} | {format} | {uri} | {type} |

### Labels
| Key | Value |
|-----|-------|
| {key} | {value} |

## Actions Performed
- {action description and result}

## Recommendations
- {suggestions for version hygiene, archival, or deployment}
```

## Safety Constraints

- Never delete registered models or versions without explicit user confirmation
- Do not expose storage credentials or secret keys in output
- Validate that artifact URIs are accessible before confirming registration
- Warn before archiving a version that has active InferenceService deployments
- RBAC enforcement: verify the user has appropriate permissions before write operations
- Never modify registry instances owned by other teams without confirmation
- All registry mutations must go through Git (PR with manifest changes) — do not apply directly via kubectl

## Disconnected Environment Notes

- Model artifacts must reference internal S3-compatible storage (MinIO, ODF) — external URIs will fail
- The Model Registry REST API is cluster-internal; access via OpenShift Route or port-forward
- Database (MySQL/PostgreSQL) must be pre-provisioned within the cluster
- OCI-based model storage works well in disconnected environments — models stored as OCI artifacts in the mirrored registry
- Ensure the `storageKey` references a DataConnection (Secret) with credentials for the internal object store
- Model format validation happens at deploy time — pre-validate in disconnected environments to avoid runtime failures
