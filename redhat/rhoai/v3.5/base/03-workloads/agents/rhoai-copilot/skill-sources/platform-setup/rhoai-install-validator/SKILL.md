---
name: rhoai-install-validator
description: "Post-install validation for RHOAI — verifies mirror configuration, operator health, DSC/DSCI readiness, networking, and disconnected integrity across both GitOps and direct deployment methods."
version: 3.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, Installation, Validation, Disconnected]
---

# RHOAI Installation Validator

Validates that a Red Hat OpenShift AI installation is complete, healthy, and properly configured. Supports both ArgoCD-managed (GitOps) and direct Kubernetes deployments. Includes comprehensive disconnected environment integrity checks derived from battle-tested deployment verification scripts.

## Trigger Conditions

- "Validate my RHOAI installation"
- "Is OpenShift AI installed correctly?"
- "Post-install validation"
- "Check RHOAI health"
- "Verify my disconnected RHOAI deployment"

## Required MCP Tools

| MCP Server | Tool | Purpose |
|------------|------|---------|
| RHOAI | `cluster_summary` | Get DSC component status overview |
| ArgoCD | `list_applications` | Detect GitOps deployment mode |
| ArgoCD | `get_application` | Check operator sync/health status |
| ArgoCD | `get_application_resource_tree` | Verify DSC managed resources |
| OpenShift | *(various)* | Retrieve Subscriptions, CSVs, cluster config |

## Procedure

### Phase 0: Detect Deployment Method and Environment

1. Call `mcp_argocd_list_applications`:
   - **If ArgoCD responds with applications**: set validation mode to `gitops` — use ArgoCD-based validation (Phase 2a, 3a)
   - **If ArgoCD fails, times out, or returns empty**: set validation mode to `direct` — use direct Kubernetes resource validation (Phase 2b, 3b)
2. Detect disconnected environment:
   - Run: `oc get imagedigestmirrorset --no-headers 2>/dev/null | wc -l`
   - **If count > 0**: set `disconnected=true` — include Phase 4 (Mirror Configuration) and Phase 7 (Disconnected Integrity)
   - **If count == 0**: set `disconnected=false` — skip Phases 4 and 7
3. Report detected mode and environment type to user before proceeding

### Phase 1: Pre-Install Readiness

4. Verify required namespaces exist:
   - `redhat-ods-operator` (RHOAI operator namespace)
   - `redhat-ods-applications` (RHOAI applications namespace)
   - `redhat-ods-monitoring` (RHOAI monitoring namespace)
   - `istio-system` or `redhat-ods-applications-auth-provider` (ServiceMesh)
5. Verify CatalogSource in `openshift-marketplace`:
   - Verify `redhat-operators` or disconnected mirror catalog exists and is READY

### Phase 2a: Operator Installation Validation (GitOps Mode)

6. Call `mcp_argocd_get_application` for `operator-rhoai-operator`:
   - Verify sync status is `Synced`
   - Verify health status is `Healthy`
   - If `Degraded`: check for `ResolutionFailed` (missing CatalogSource) or `ConstraintsNotSatisfiable`
7. Call `mcp_openshift_resources_get` for the RHOAI Subscription:
   - Verify `currentCSV` is set and matches expected version
   - Verify `installPlanApproval` matches policy (Manual for prod, Automatic for dev)

### Phase 2b: Operator Installation Validation (Direct Mode)

6. Verify RHOAI subscription in `redhat-ods-operator`:
   - Check `status.currentCSV` is populated
   - Check `status.state` is `AtLatestKnown`
7. Verify RHOAI CSV:
   - Find the CSV with name containing `rhods-operator`
   - Verify `status.phase` is `Succeeded`
   - If `Failed` or `Pending`: check `status.reason` for resolution errors
8. Verify install plan is approved and complete

### Phase 3: Dependency Operator Checks

9. Verify each dependency operator CSV has `status.phase` == `Succeeded`:
   - `cert-manager` CSV
   - `nfd` (Node Feature Discovery) CSV
   - `gpu-operator-certified` CSV
10. Check for ANY CSV in a Failed phase cluster-wide:
    - Run: `oc get csv --all-namespaces -o json | jq '.items[] | select(.status.phase=="Failed") | .metadata.name'`
    - If any found: report as FAIL with CSV name and namespace

### Phase 4: Mirror Configuration Checks (Disconnected Only)

> Skip this phase if `disconnected=false`

11. Verify OperatorHub default sources are disabled:
    - Run: `oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}'`
    - Must return `true` — if not, default catalogs will conflict with mirrored content
12. Verify additionalTrustedCA is configured:
    - Run: `oc get image.config.openshift.io/cluster -o jsonpath='{.spec.additionalTrustedCA.name}'`
    - Must return a non-empty ConfigMap name (typically `registry-cas` or similar)
13. Verify at least one ImageDigestMirrorSet exists:
    - Run: `oc get imagedigestmirrorset --no-headers | wc -l`
    - Must be >= 1
14. Verify all MachineConfigPools are updated and not degraded:
    - Run: `oc get mcp -o json | jq '.items[] | {name: .metadata.name, updated: .status.conditions[] | select(.type=="Updated") | .status, degraded: .status.conditions[] | select(.type=="Degraded") | .status}'`
    - All pools must show `updated: "True"` and `degraded: "False"`
    - If any pool is degraded or updating: report as FAIL (mirror config changes trigger MCP rollout)
15. Verify all CatalogSources are READY:
    - Run: `oc get catalogsource -n openshift-marketplace -o json | jq '.items[] | {name: .metadata.name, state: .status.connectionState.lastObservedState}'`
    - All must show `READY` — any `TRANSIENT_FAILURE` means registry is unreachable or index image is invalid

### Phase 5a: DSC Configuration Validation (GitOps Mode)

16. Call `mcp_rhoai_cluster_summary` to get current DSC status
17. Call `mcp_argocd_get_application_resource_tree` for the DSC application:
    - Verify expected components are present and not `Removed`
18. For each enabled component, verify its managed resources exist

### Phase 5b: DSC Configuration Validation (Direct Mode)

16. **DSCInitialization check (CRITICAL)**:
    - Run: `oc get dsci -o jsonpath='{.items[0].status.phase}'`
    - Must return `Ready`
    - **WARNING**: Do NOT check `.status.conditions` for a Ready condition — RHOAI 3.4.2 uses `.status.phase` on DSCI, not conditions
17. **DataScienceCluster check**:
    - Run: `oc get dsc -o json | jq '.items[0].status.conditions[] | select(.type=="Ready")'`
    - `.status` must be `"True"`
    - If not Ready: report the condition's `.reason` and `.message`
18. Call `mcp_rhoai_cluster_summary` to get detailed component status
19. For each component in the DSC spec, verify:
    - If `managementState: Managed` → corresponding pods are running in `redhat-ods-applications`
    - If any component shows errors in status conditions, report them

### Phase 6: Networking & Access Validation

20. Verify `odh-trusted-ca-bundle` ConfigMap exists in `redhat-ods-applications`:
    - Run: `oc get configmap odh-trusted-ca-bundle -n redhat-ods-applications`
    - This ConfigMap is critical for disconnected workbenches to trust the mirror registry CA
21. Verify GatewayClass for Data Science Gateway:
    - Run: `oc get gatewayclass data-science-gateway-class -o json | jq '.status.conditions[] | select(.type=="Accepted")'`
    - `.status` must be `"True"`
22. Verify data-science-gateway Gateway is programmed:
    - Run: `oc get gateway data-science-gateway -n openshift-ingress -o json | jq '.status.conditions[] | select(.type=="Programmed")'`
    - `.status` must be `"True"`
23. Verify Dashboard route exists:
    - Run: `oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'`
    - Must return a non-empty hostname

### Phase 7: Disconnected Integrity (Disconnected Only)

> Skip this phase if `disconnected=false`

24. Check for ImagePullBackOff or ErrImagePull pods GLOBALLY (not just RHOAI namespaces):
    - Run: `oc get pods --all-namespaces --field-selector=status.phase!=Succeeded,status.phase!=Running -o json | jq '[.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "ImagePullBackOff" or .status.containerStatuses[]?.state.waiting.reason == "ErrImagePull") | {namespace: .metadata.namespace, name: .metadata.name, image: .status.containerStatuses[].image}]'`
    - Must return empty array — ANY image pull failure on a disconnected cluster indicates incomplete mirroring
25. Check for stuck pods in `openshift-marketplace`:
    - Run: `oc get pods -n openshift-marketplace --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers | wc -l`
    - Must be 0 — stuck marketplace pods indicate default catalogs are still enabled or catalog image is not mirrored
26. **IMPORTANT — Do NOT flag imageID showing quay.io or registry.redhat.io as a problem**:
    - On a mirrored cluster, `imageID` in pod status will show the canonical source digest (e.g., `quay.io/modh/...@sha256:...`) even though the image was pulled from the mirror
    - This is NORMAL CRI-O behavior — CRI-O records the original image reference, not the mirror location
    - Only flag actual pull failures (ImagePullBackOff, ErrImagePull), never the imageID field contents

## Output Format

```
# RHOAI Installation Validation Report — {timestamp}

## Overall: {PASS ✓ | PARTIAL ⚠ | FAIL ✗}
## Deployment Mode: {GitOps (ArgoCD) | Direct (Kubernetes)}
## Environment: {Connected | Disconnected}

## Operator Health
| Check | Status | Detail |
|-------|--------|--------|
| rhods-operator CSV | ✓/✗ | {phase} |
| cert-manager CSV | ✓/✗ | {phase} |
| nfd CSV | ✓/✗ | {phase} |
| gpu-operator-certified CSV | ✓/✗ | {phase} |
| Failed CSVs cluster-wide | ✓/✗ | {count or "none"} |

## Mirror Configuration (Disconnected Only)
| Check | Status | Detail |
|-------|--------|--------|
| Default sources disabled | ✓/✗ | disableAllDefaultSources={value} |
| additionalTrustedCA | ✓/✗ | ConfigMap: {name} |
| ImageDigestMirrorSet | ✓/✗ | {count} IDMS resources |
| MachineConfigPools | ✓/✗ | {updated}/{total} updated, {degraded} degraded |
| CatalogSources READY | ✓/✗ | {count ready}/{count total} |

## RHOAI Core
| Check | Status | Detail |
|-------|--------|--------|
| DSCInitialization phase | ✓/✗ | phase={value} |
| DataScienceCluster Ready | ✓/✗ | condition={value} |
| odh-trusted-ca-bundle | ✓/✗ | {exists/missing} |
| GatewayClass Accepted | ✓/✗ | {status} |
| Gateway Programmed | ✓/✗ | {status} |
| Dashboard route | ✓/✗ | {hostname} |

## DSC Components
| Component | Managed | Status | Pods |
|-----------|---------|--------|------|
| KServe | ✓/✗ | {status} | {count} |
| Dashboard | ✓/✗ | {status} | {count} |
| Workbenches | ✓/✗ | {status} | {count} |
| DataSciencePipelines | ✓/✗ | {status} | {count} |
| Ray | ✓/✗ | {status} | {count} |
| ModelMeshServing | ✓/✗ | {status} | {count} |
| Kueue | ✓/✗ | {status} | {count} |
| TrainingOperator | ✓/✗ | {status} | {count} |
| ModelRegistry | ✓/✗ | {status} | {count} |

## Disconnected Integrity (Disconnected Only)
| Check | Status | Detail |
|-------|--------|--------|
| ImagePullBackOff pods | ✓/✗ | {count} pods failing globally |
| Stuck marketplace pods | ✓/✗ | {count} pods not Running |
| imageID canonical refs | ℹ | NORMAL — CRI-O records source digest |

## Issues Found
{Numbered list of issues with severity and recommended fix}

## Next Steps
{Prioritized actions to fix or complete installation}
```

## Domain Knowledge

- RHOAI 2.x+ uses `DataScienceCluster` CR; RHOAI 1.x used `KfDef` — this skill targets 2.x+
- **DSCI uses `.status.phase` (not conditions)**: RHOAI 3.4.2 DSCInitialization reports readiness via `.status.phase == "Ready"`, NOT via `.status.conditions[].type=="Ready"`. Do not look for a Ready condition on DSCI.
- **DSC uses conditions**: DataScienceCluster reports readiness via `.status.conditions[?(@.type=="Ready")].status == "True"`
- Disconnected environments need `ImageDigestMirrorSet` (oc-mirror v2 generates IDMS + ITMS)
- Legacy `ImageContentSourcePolicy` (ICSP) is deprecated in OCP 4.14+ in favor of IDMS/ITMS
- If CatalogSource shows `TRANSIENT_FAILURE`, the mirror registry is likely unreachable or the index image digest is wrong
- **imageID on mirrored clusters**: CRI-O records the canonical source digest in `imageID` even when the image was pulled from a mirror. Seeing `quay.io/...` or `registry.redhat.io/...` in imageID is NORMAL and must NOT be flagged as a mirror failure.
- ServiceMesh version compatibility: RHOAI 2.16+ requires OSSM 2.6+ or ServiceMesh 3.0 (OCP 4.20 uses OSSM 3 via OLM)
- GPU operator requires NFD to label GPU nodes before it can schedule daemonsets
- Not all clusters use ArgoCD — many production deployments use direct `oc apply` or Helm
- The DSCInitialization CR must exist before the DSC can be created
- `odh-trusted-ca-bundle` ConfigMap in `redhat-ods-applications` injects the mirror CA into workbench pods; without it, pip/conda in notebooks cannot pull from internal PyPI mirrors
- MachineConfigPool rollouts are triggered by IDMS/ITMS changes and must complete before cluster is healthy
- Default OperatorHub sources must be disabled on disconnected clusters or pods in openshift-marketplace will crash-loop trying to reach external registries
- Data Science Gateway (GatewayClass + Gateway) is required for model inference routing in RHOAI 3.4+

## Safety Constraints

- Never directly modify cluster resources — this is a read-only validation skill
- Never interpret `imageID` showing external registries as a failure on mirrored clusters
- Never check DSCI readiness via `.status.conditions` — always use `.status.phase`
- Report findings accurately; do not suppress failures or inflate passing status

## Disconnected Environment Notes

- Phases 4 and 7 execute only when `ImageDigestMirrorSet` resources are detected on the cluster
- Mirror validation checks IDMS/ITMS (not legacy ICSP) — ICSP is deprecated on OCP 4.14+
- CRI-O records the canonical source digest in `imageID` even on mirrored clusters — `quay.io/...` in imageID is expected behavior and must NOT be flagged
- MachineConfigPool rollouts triggered by IDMS/ITMS changes must complete before the cluster is considered healthy
- If `disableAllDefaultSources` is not `true`, default CatalogSources will crash-loop trying to reach external registries

## Related Skills

- `platform-setup/rhoai-disconnected-helper` — deep-dive disconnected diagnostics (mirror gaps, pull secrets, CA trust)
- `platform-setup/rhoai-disconnected-deploy` — deploy RHOAI in a disconnected environment
- `platform-setup/rhoai-connected-deploy` — deploy RHOAI in a connected environment
- `platform-setup/gitops-config-generator` — generate DSC/DSCI patches and ArgoCD Applications
- `administer/rhoai-dsc-inspector` — inspect and explain DSC component status
- `monitor/argocd-health-check` — ArgoCD application health monitoring
