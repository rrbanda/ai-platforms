---
name: rhoai-dsc-inspector
description: "Inspect the RHOAI DataScienceCluster CR — report component management states, detected resources, and drift from desired configuration."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, DSC, DataScienceCluster, Components, Inspection]
---

# RHOAI DataScienceCluster Inspector

Inspect the DataScienceCluster (DSC) custom resource that controls which RHOAI components are active.

## DSC Components Reference

The DSC CR (`default-dsc`) has these components, each with a `managementState`:

| Component | Purpose | Dependencies |
|-----------|---------|--------------|
| aigateway | API gateway for model serving | ServiceMesh |
| aipipelines | ML pipelines (Argo Workflows) | — |
| dashboard | RHOAI web console | — |
| feastoperator | Feature store | — |
| kserve | Model serving (single/multi) | ServiceMesh, cert-manager |
| kueue | Job admission control | kueue-operator |
| llamastackoperator | LlamaStack integration | — |
| mlflowoperator | Experiment tracking | — |
| modelregistry | Model version registry | — |
| ogx | OGX components | — |
| ray | Distributed computing | — |
| sparkoperator | Spark jobs | — |
| trainer | Training orchestration | — |
| trainingoperator | Kubeflow Training Operator | — |
| trustyai | Model explainability + eval | — |
| workbenches | Jupyter notebooks | — |

## Procedure

1. Call `mcp_argocd_get_application` with name `rhoai-dsc` to get the application status
2. Call `mcp_argocd_get_application_resource_tree` with name `rhoai-dsc` to see all managed resources
3. Call `mcp_argocd_get_application_managed_resources` with name `rhoai-dsc` to get resource details
4. From the resource tree, identify:
   - The DataScienceCluster CR itself (kind: DataScienceCluster)
   - Child resources grouped by component (use naming patterns)
   - Any resources in non-Healthy state
5. Report component status based on resource tree evidence:
   - If component has visible Deployments/Pods → Active
   - If component has no resources → Likely Removed or not yet reconciled
   - If component has resources in Degraded state → Investigate

## Output Format

```
# DataScienceCluster Inspection — {timestamp}

## DSC Application Status
- Health: {status}
- Sync: {status}
- Last sync: {timestamp}
- Target revision: {branch/tag}

## Component Analysis
| Component | Expected State | Evidence | Status |
|-----------|---------------|----------|--------|
| kserve | Managed | InferenceService CRD, webhooks present | Active |
| ray | Managed | RayCluster controller detected | Active |
| workbenches | Managed | Notebook controller present | Active |
| llamastackoperator | Removed | No resources found | Correctly removed |
| ... | ... | ... | ... |

## Drift Detection
{Any discrepancies between expected managementState and observed resources}

## Recommendations
{Actions needed to align actual state with desired state}
```

## Notes

- The DSC is deployed by a dedicated Application (not the cluster-instances ApplicationSet)
- DSC uses sync-wave "4" — it deploys after all operators are ready
- The `ignoreDifferences` for DSC should include `/status` to avoid spurious OutOfSync
- If targetRevision is unreachable, ArgoCD shows ComparisonError but existing resources remain running
- Components with `managementState: Unmanaged` are installed but not reconciled by RHOAI operator
