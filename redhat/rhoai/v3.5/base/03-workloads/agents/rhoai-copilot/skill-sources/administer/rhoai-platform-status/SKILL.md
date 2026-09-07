---
name: rhoai-platform-status
description: "Comprehensive RHOAI platform readiness report — aggregates health of all operators, instances, DSC, and models with dependency-aware analysis."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform, Health, GitOps]
---

# RHOAI Platform Status Report

Produce a comprehensive platform readiness report for Red Hat OpenShift AI deployed via GitOps.

## RHOAI Dependency Graph

The platform has a strict dependency order. Report issues in dependency order:

```
Layer 1 (Operators):     cert-manager → nfd → gpu-operator → servicemesh → rhoai-operator
Layer 2 (Platform):      kueue-operator, jobset-operator, lws, external-secrets, rhcl, rhdh
Layer 3 (DSC):           DataScienceCluster (depends on rhoai-operator being Healthy)
Layer 4 (Instances):     kueue-config, hardware-profiles, mlflow, observability, mcp-servers
Layer 5 (Models):        InferenceServices (depend on KServe in DSC + Kueue + GPU)
```

## Procedure

1. Call `mcp_argocd_list_applications` to get all applications
2. Classify each application:
   - **Operators**: apps named `operator-*` (Layer 1-2)
   - **DSC**: app named `rhoai-dsc` (Layer 3)
   - **Instances**: apps named `instance-*` (Layer 4)
   - **Models**: any apps with InferenceService resources (Layer 5)
3. For each layer, report:
   - Total count, healthy count, degraded count
   - Any blocking issues that prevent the next layer from functioning
4. For degraded operators:
   - Call `mcp_argocd_get_application` to get status details
   - Identify if the issue is: ResolutionFailed, CatalogSourcesUnhealthy, DiskPressure, ImagePullBackOff, or ComparisonError
5. For the DSC:
   - Call `mcp_argocd_get_application_resource_tree` on rhoai-dsc
   - Report which components have visible resources (KServe, Ray, Workbenches, etc.)
6. Produce the final report

## Output Format

```
# RHOAI Platform Readiness Report — {timestamp}

## Overall Status: {READY | DEGRADED | NOT READY}

## Layer 1-2: Operators ({healthy}/{total})
| Operator | Health | Issue |
|----------|--------|-------|
| cert-manager | Healthy | — |
| nfd | Healthy | — |
| ... | ... | ... |

## Layer 3: DataScienceCluster
- Status: {Healthy/Degraded/Missing}
- Components detected: {list of visible components}
- Missing/Degraded components: {list}

## Layer 4: Instances ({healthy}/{total})
| Instance | Health | Issue |
|----------|--------|-------|
| kueue-config | Healthy | — |
| ... | ... | ... |

## Layer 5: Models
- Deployed: {count}
- Serving: {count healthy}
- Pending: {count progressing or waiting for GPU}

## Blocking Issues
{List of issues in Layer N that prevent Layer N+1 from functioning}

## Recommendations
{Prioritized list of actions to restore full platform health}
```

## RHOAI-Specific Knowledge

- `operator-rhoai-operator` Degraded often means the RHOAI CSV failed to install — check Subscription
- `rhoai-dsc` with ComparisonError means the Git branch/revision is unreachable
- If all operators are Healthy but DSC shows no resources, the DSC CR may have all components set to `Removed`
- KServe requires ServiceMesh and cert-manager — if those operators are degraded, KServe won't function
- GPU workloads (models, training) require: nfd + gpu-operator + kueue-config all Healthy
