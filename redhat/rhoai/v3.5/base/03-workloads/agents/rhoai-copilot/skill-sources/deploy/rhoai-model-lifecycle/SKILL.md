---
name: rhoai-model-lifecycle
description: "Track AI model deployments through the RHOAI serving pipeline — from InferenceService to GPU allocation and readiness."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, Models, KServe, InferenceService, GPU, Serving]
---

# RHOAI Model Lifecycle Tracker

Track model deployments managed by the GitOps model ApplicationSet through the full lifecycle.

## Trigger Conditions

- "Show me all deployed models"
- "What's the status of my model deployments?"
- "Which models are serving and which are stuck?"
- "GPU usage across model deployments"
- "Is model X healthy?"
- "Why is my model stuck in Pending?"
- "Model deployment report"
- "Kueue queue status for models"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_argocd` | `list_applications` | Discover model applications managed by ArgoCD |
| `mcp_argocd` | `get_application` | Check health and sync status per model app |
| `mcp_argocd` | `get_application_resource_tree` | Find InferenceService and related resources |
| `mcp_rhoai` | `list_inference_services` | List all InferenceServices across namespaces |
| `mcp_rhoai` | `get_inference_service` | Get detailed status of a specific model deployment |
| `mcp_rhoai` | `get_cluster_resources` | Check GPU and resource availability |
| `mcp_openshift` | `resources_list` | List Kueue ClusterQueues, ResourceFlavors, HardwareProfiles |
| `mcp_openshift` | `resources_get` | Inspect individual Kueue or KServe resources |

## Model Deployment Architecture in this Repo

Models are deployed via:
1. `usecases/models/<model-name>/profiles/tier1-minimal/config.json` — toggle enabled/disabled
2. A `cluster-models` ApplicationSet auto-discovers enabled models
3. Each model creates an InferenceService CR → KServe reconciles it
4. KServe creates: Deployment + Service + Route + (optionally) model cache PV
5. Kueue admits the workload based on ClusterQueue quotas and GPU availability

## Procedure

1. Call `mcp_argocd_list_applications` — identify model applications (not operator-* or instance-*)
2. For each model application:
   - Call `mcp_argocd_get_application` to check health and sync
   - Call `mcp_argocd_get_application_resource_tree` to find InferenceService resources
3. For each InferenceService found:
   - Note its `health.status` from the resource tree
   - Check if there's a corresponding Deployment and its readiness
   - Check for PersistentVolumeClaims (model cache)
4. Cross-reference with Kueue:
   - Check `instance-kueue-config` resource tree for ClusterQueue admission status
   - Note available GPU quota vs. used
5. Produce the model lifecycle report

## Output Format

```
# Model Deployment Report — {timestamp}

## Summary
- Total models deployed: {n}
- Serving (Ready): {n}
- Progressing: {n}
- Failed: {n}
- Queued (Kueue): {n}

## Model Details
| Model | Namespace | Health | GPU Allocated | Endpoint |
|-------|-----------|--------|---------------|----------|
| gpt-oss-120b | model-ns | Healthy | 4x A100 | Ready |
| ... | ... | ... | ... | ... |

## GPU Capacity (from Kueue)
- ClusterQueue: {name}
- Total GPU quota: {n}
- Used: {n}
- Available: {n}

## Issues
{Any models stuck in Pending, ImagePullBackOff, or InsufficientGPU}

## Recommendations
{Scaling suggestions, cache optimization, queue priority adjustments}
```

## RHOAI-Specific Knowledge

- Models in this repo: gpt-oss-120b, orchestrator-8b, qwen-math-7b (check usecases/models/)
- Services: guardrails-gateway, toolorchestra-app (check usecases/services/)
- HardwareProfiles define GPU types and quantities for model serving
- ResourceFlavor `default-gpu` matches nodes with label `nvidia.com/gpu.present: true`
- Model cache uses `kserve-localmodelnode-pv` PersistentVolumes for fast loading
- If a model is stuck in Pending, check: (1) Kueue quota, (2) GPU node availability, (3) model cache PV

## Safety Constraints

- Never delete or scale down a model InferenceService without confirming no active traffic is routed to it
- Do not modify Kueue ClusterQueue quotas without understanding impact on other queued workloads — reducing quota may preempt running models
- All model lifecycle changes must go through Git (PR) — never apply InferenceService or HardwareProfile changes directly with `oc apply` in production
- Verify model cache PersistentVolumes are not shared across models before deleting — shared PVs could break other deployments
- GPU resource reporting is informational — do not over-provision beyond ClusterQueue limits as it can cause workload preemption

## Disconnected Environment Notes

- Model container images and serving runtime images must be pre-mirrored to the internal registry — verify with `oc get imagestream` or check `ImageDigestMirrorSet` resources
- Model weights referenced by `storageUri` must be stored on internally accessible S3 or PVC — external model repositories are unreachable
- Kueue and KServe controller images must be mirrored as part of the RHOAI operator deployment
- Prometheus metrics for GPU usage and model health require the local monitoring stack — no external telemetry endpoints are needed
- `kserve-localmodelnode-pv` model cache volumes are node-local and do not require network access

## Related Skills

- `model-promotion-workflow` — Promote models across environments with GitOps validation gates
- `maas-subscription-manager` — Manage MaaS subscriptions and governance for served models
- `maas-external-models` — Route inference to external cloud model providers through the MaaS gateway
