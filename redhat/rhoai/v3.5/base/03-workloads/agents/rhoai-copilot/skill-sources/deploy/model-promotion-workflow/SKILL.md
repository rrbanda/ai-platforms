---
name: model-promotion-workflow
description: "Step-by-step GitOps model promotion across environments — from dev to staging to production with validation gates."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, MLOps, Model Promotion, GitOps, InferenceService]
---

# Model Promotion Workflow

Guides step-by-step GitOps model promotion across environments (dev → staging → production) with validation gates and ArgoCD sync tracking.

## Trigger Conditions

- "Promote model to prod"
- "Promote model X to staging"
- "What's the promotion status of model Y?"
- "Model promotion workflow for my InferenceService"
- "Move model from dev to production"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_rhoai` | `list_inference_services` | Find the model to promote |
| `mcp_rhoai` | `get_inference_service` | Verify model readiness and status |
| `mcp_rhoai` | `check_deployment_prerequisites` | Validate target environment prerequisites |
| `mcp_rhoai` | `estimate_serving_resources` | Confirm resource fit in target environment |
| `mcp_rhoai` | `list_registered_models` | Track model versions and lineage |
| `mcp_rhoai` | `get_model_artifacts` | Retrieve model artifact details for promotion |
| `mcp_argocd` | `list_applications` | Find target environment ArgoCD application |
| `mcp_argocd` | `get_application` | Monitor sync status after promotion |
| `mcp_argocd` | `get_application_resource_tree` | Check for degraded dependencies |
| `mcp_openshift` | `resources_list` | Verify target namespace readiness |

## Procedure

### Phase 1: Identify the Model and Current State

1. Call `mcp_rhoai_list_inference_services` to find the model:
   - Note the model name, runtime, current namespace/environment
   - Get the model format (vLLM, TGI, Caikit, custom)
2. Call `mcp_rhoai_get_inference_service` for detailed status:
   - Verify it's in `Ready` state with healthy replicas
   - Note the `storageUri` or model path
3. Call `mcp_rhoai_list_registered_models` and `mcp_rhoai_get_model_artifacts` to:
   - Identify the model version being promoted
   - Retrieve model metrics (accuracy, latency, throughput) from registered metadata

### Phase 2: Pre-Promotion Validation

4. Run promotion readiness checks:

| Check | Tool | Pass Criteria |
|-------|------|---------------|
| Model serving | `get_inference_service` | Status = Ready |
| Metrics baseline | `list_registered_models` | Accuracy ≥ threshold |
| Resource fit | `estimate_serving_resources` | GPU/memory within quota |
| Dependencies | `get_application_resource_tree` | No degraded deps |
| Namespace exists | `resources_list` | Target namespace ready |

5. Call `mcp_rhoai_check_deployment_prerequisites` for the target environment:
   - Verify serving runtime exists in target namespace
   - Verify storage/model path is accessible from target

### Phase 3: Generate Promotion Artifacts

6. Identify the GitOps path for the target environment:
   - Dev: `usecases/models/{model}/profiles/tier1-minimal/`
   - Staging: `usecases/models/{model}/profiles/tier2-standard/`
   - Production: `usecases/models/{model}/profiles/tier3-production/`

7. Generate or update `config.json` for the target tier:
```json
{
  "model_name": "{name}",
  "model_version": "{version}",
  "runtime": "{runtime}",
  "resources": {
    "gpu": {count},
    "memory": "{size}",
    "cpu": "{cores}"
  },
  "replicas": {min: X, max: Y},
  "canary_percent": {0-100},
  "promoted_from": "{source_env}",
  "promoted_at": "{timestamp}",
  "promotion_criteria": {
    "accuracy": "{threshold}",
    "p99_latency_ms": {threshold},
    "load_test_passed": true
  }
}
```

### Phase 4: Track Promotion in ArgoCD

8. Call `mcp_argocd_list_applications` to find the target environment's app:
   - Look for application managing the target namespace
9. After GitOps push (manual step), monitor sync:
   - Call `mcp_argocd_get_application` to verify sync starts
   - Verify health transitions to `Progressing` → `Healthy`
10. Post-promotion verification:
    - Call `mcp_rhoai_get_inference_service` in target namespace
    - Verify `Ready` state with expected replicas

## Output Format

```
# Model Promotion: {model_name} → {target_env}

## Current State
- Model: {name} v{version}
- Source: {source_namespace} ({source_env})
- Runtime: {runtime}
- Status: {Ready/NotReady}

## Pre-Promotion Checks
| Check | Status | Detail |
|-------|--------|--------|
| Model healthy | ✓/✗ | {status} |
| Metrics pass | ✓/✗ | accuracy={val}, p99={val}ms |
| Resource fit | ✓/✗ | {gpu}x GPU, {mem} RAM |
| Target ready | ✓/✗ | namespace={ns} |
| Dependencies | ✓/✗ | {detail} |

## Promotion Path
{source_env} → {target_env}
GitOps path: `usecases/models/{model}/profiles/{tier}/config.json`

## Generated Config
```json
{config content}
```

## Next Steps
1. Review and commit config to Git
2. Push to trigger ArgoCD sync
3. Monitor: `hermes ask "Status of {model_name} in {target_env}"`
4. Validate: Run smoke test against new endpoint

## Rollback Plan
Revert Git commit to restore previous config version.
ArgoCD will automatically sync to previous state.
```

## Domain Knowledge

- Promotion in GitOps means updating the config in the target environment's overlay — NOT copying pods
- InferenceService in RHOAI uses KServe — the model is pulled from storage, not transferred between clusters
- Canary deployments use `trafficPercent` field in InferenceService spec
- vLLM runtime may need different GPU types across tiers (T4 in dev, A100 in prod)
- Model Registry (`list_registered_models`) can track model lineage across promotions
- Always verify the serving runtime version matches between source and target

## Safety Constraints

- Never promote a model that is not in `Ready` state in the source environment
- Always run pre-promotion validation checks before generating promotion artifacts — skipping checks risks deploying a broken model
- Do not promote directly to production — require at least one intermediate environment (staging) with validation gates
- Canary deployments should start at ≤10% traffic — never route 100% to an untested model version
- All promotion changes must go through Git (PR) — never apply InferenceService changes directly with `oc apply` in production
- Verify GPU resource availability in the target environment before promotion — insufficient resources will leave the model stuck in `Pending`
- Rollback plan must be documented before promotion — revert the Git commit to restore the previous config version

## Disconnected Environment Notes

- Model storage URIs must reference internally accessible S3/PVC paths — external model registries are unreachable in air-gapped clusters
- ArgoCD sync requires the Git repository to be mirrored internally — configure ArgoCD to use the internal Git mirror URL
- Serving runtime container images must be pre-mirrored to the internal registry before promotion — verify with `oc get imagestream` in the target namespace
- If using Model Registry for lineage tracking, ensure the registry service is deployed locally — it does not require external connectivity
- HardwareProfile and ResourceFlavor configurations must match between source and target clusters in multi-cluster promotions

## Related Skills

- `rhoai-model-lifecycle` — Track model deployments through the RHOAI serving pipeline
- `maas-subscription-manager` — Manage MaaS subscriptions and governance for promoted models
- `maas-external-models` — Route inference to external cloud model providers through the MaaS gateway
