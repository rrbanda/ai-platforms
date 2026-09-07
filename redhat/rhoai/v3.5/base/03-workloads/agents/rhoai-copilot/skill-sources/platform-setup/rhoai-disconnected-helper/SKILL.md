---
name: rhoai-disconnected-helper
description: "Diagnose disconnected/air-gapped RHOAI environments — mirror config, image source auditing, pull secret validation, CA trust, and CatalogSource health."
version: 2.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, Disconnected, Air-gapped, Mirror, oc-mirror]
---

# RHOAI Disconnected Environment Helper

Diagnoses and validates RHOAI deployments in disconnected (air-gapped) environments by checking mirror configuration (IDMS + ITMS), pull secret validity, CA trust bundles, image sources, and CatalogSource health.

## Trigger Conditions

- "Check disconnected setup"
- "Why are images failing to pull?"
- "Validate mirror configuration"
- "CatalogSource is not healthy"
- "ImagePullBackOff in air-gapped cluster"
- "Verify oc-mirror results"
- "Check pull secret for private registry"

## Required MCP Tools

| MCP Server | Tool | Purpose |
|------------|------|---------|
| OpenShift | *(various)* | List/get IDMS, ITMS, ICSP, Secrets, Proxy, Image config, CatalogSources, Pods, Events |
| ArgoCD | `get_application` | Check GitOps-managed mirror config sync status |
| ArgoCD | `list_applications` | Detect operators with resolution failures |

## Procedure

### Phase 1: Mirror Configuration Audit

1. Call `mcp_openshift_resources_list` with kind=`ImageDigestMirrorSet`:
   - List all IDMS resources and their mirror mappings
   - Verify RHOAI required registries are mapped:
     - `registry.redhat.io` → local mirror
     - `quay.io/modh` → local mirror (for notebook images)
     - `registry.connect.redhat.com` → local mirror (for ISVs)
     - `registry.redhat.io/rhaiis` → local mirror (for runtime images)
2. Call `mcp_openshift_resources_list` with kind=`ImageTagMirrorSet`:
   - List all ITMS resources and their mirror mappings
   - oc-mirror v2 generates BOTH IDMS and ITMS — verify both exist
   - ITMS handles tag-based references that can't use digests
3. If no IDMS or ITMS found, check for legacy `ImageContentSourcePolicy`:
   - Call `mcp_openshift_resources_list` with kind=`ImageContentSourcePolicy`
   - Warn that ICSP is deprecated on OCP 4.14+ and should be migrated to IDMS/ITMS
4. Call `mcp_argocd_get_application` for `instance-registry-mirror` if it exists:
   - Verify the GitOps-managed IDMS/ITMS are synced

### Phase 2: Pull Secret Validation

5. Call `mcp_openshift_resources_get` for Secret `pull-secret` in namespace `openshift-config`:
   - Decode the `.dockerconfigjson` field
   - Verify it contains `auths` entries for the private mirror registry hostname
   - Check that credentials are present (non-empty `auth` field)
6. Identify the mirror registry hostname from IDMS/ITMS mirror entries
7. Confirm the pull secret covers ALL mirror hostnames found in step 1-2:
   - If multiple mirrors are used (e.g., separate registries for operators vs images), each must have credentials
   - Flag any mirror host that lacks a matching `auths` entry

### Phase 3: Registry CA Trust Bundle

8. Call `mcp_openshift_resources_get` for Proxy `cluster` (cluster-wide proxy config):
   - Check if `spec.trustedCA.name` references a ConfigMap
9. If trustedCA is configured, call `mcp_openshift_resources_get` for the referenced ConfigMap in `openshift-config`:
   - Verify `ca-bundle.crt` key exists and contains certificate data
10. Call `mcp_openshift_resources_list` with kind=`Image` (cluster config `image.config.openshift.io`):
    - Check `spec.additionalTrustedCA.name` for registry-specific CA bundles
11. If the mirror registry uses self-signed certificates and NO trust bundle is configured:
    - Flag as critical issue — image pulls will fail with x509 certificate errors
    - Recommend creating a ConfigMap with the registry CA and referencing it in the proxy or image config

### Phase 4: CatalogSource Health

12. Call `mcp_openshift_resources_list` with kind=`CatalogSource` namespace=`openshift-marketplace`:
    - For each CatalogSource, check:
      - `status.connectionState.lastObservedState` should be `READY`
      - If `TRANSIENT_FAILURE`: the mirror registry is unreachable or CA is missing
13. For RHOAI-specific catalog:
    - Look for a custom CatalogSource pointing to the disconnected index image
    - Verify the index image reference uses a mirrored path
14. Call `mcp_argocd_list_applications` and check if any operators show `ResolutionFailed`:
    - This often means the operator index can't resolve dependencies in the mirrored catalog

### Phase 5: additionalImages Cross-Reference

15. Compile the list of known RHOAI 3.5 platform images that must be mirrored:

    **Notebook Images** (from `quay.io/modh`):
    - `odh-notebook-jupyter-minimal-*`
    - `odh-notebook-jupyter-datascience-*`
    - `odh-notebook-code-server-*`
    - `odh-notebook-rstudio-*`
    - `cuda-notebooks` (GPU variants)

    **Runtime / Serving Images** (from `registry.redhat.io/rhaiis`):
    - `vllm-openai-rhel9` (vLLM runtime)
    - `text-generation-inference-rhel9` (TGI runtime)
    - `caikit-tgis-serving-rhel9`
    - `openvino-model-server-rhel9`
    - `odh-modelmesh-serving-rhel9`
    - `odh-modelmesh-runtime-adapter-rhel9`

    **Operator / Platform Images** (from `registry.redhat.io/rhoai`):
    - `rhods-operator-bundle`
    - `rhods-dashboard-rhel9`
    - `odh-data-science-pipelines-*`
    - `kuberay-operator-rhel9`
    - `kueue-operator-rhel9`
    - `training-operator-rhel9`

16. Cross-reference against IDMS mirror mappings:
    - Extract all `source` entries from IDMS resources
    - For each required image prefix, verify a matching source → mirror mapping exists
    - Flag any image category with no matching IDMS entry

17. Report gaps as a priority list — missing serving images are critical, missing notebook variants are warning-level

### Phase 6: Image Pull Validation

18. Call `mcp_openshift_pods_list_in_namespace` for `redhat-ods-applications`:
    - Look for pods in `ImagePullBackOff` or `ErrImagePull` state
19. For each failing pod:
    - Call `mcp_openshift_pods_get` to see the image reference
    - Check if the image uses a digest (required for IDMS mirroring) vs tag (requires ITMS)
    - Verify the image is in the IDMS or ITMS mapping
20. Call `mcp_openshift_events_list` with namespace=`redhat-ods-applications` filtering for image pull events
21. **IMPORTANT — Do NOT flag imageID showing quay.io or registry.redhat.io as a problem**:
    - On a mirrored cluster, `imageID` in pod status shows the canonical source digest (e.g., `quay.io/modh/...@sha256:...`) even though the image was pulled from the mirror
    - This is NORMAL CRI-O behavior — only flag actual pull failures (ImagePullBackOff, ErrImagePull)

### Phase 7: Operator Source Patching

22. Call `mcp_argocd_get_application` for each operator that has `patch-source.yaml`:
    - Verify the Subscription `source` field points to the disconnected CatalogSource
    - Verify the `sourceNamespace` matches
23. If not using ArgoCD, call `mcp_openshift_resources_list` with kind=`Subscription`:
    - Verify each operator subscription references the custom CatalogSource, not `redhat-operators`

## oc-mirror v2 Workspace Awareness

When users run `oc-mirror` v2, results are stored in a workspace directory structure:
- `workspace/results-{timestamp}/` — contains generated cluster resources
  - `release-signatures/` — image signature ConfigMaps
  - `mapping.txt` — full digest-to-mirror mapping
  - `imageDigestMirrorSet.yaml` — IDMS to apply
  - `imageTagMirrorSet.yaml` — ITMS to apply
  - `catalogSource.yaml` — CatalogSource for the mirrored index

If the user references their oc-mirror workspace, check these files to validate completeness before they apply to the cluster.

## Output Format

```
# Disconnected Environment Diagnostic — {timestamp}

## Overall: {HEALTHY | DEGRADED | BROKEN}

## Mirror Configuration
| Source Registry | Mirror | Type (IDMS/ITMS/ICSP) | Status |
|-----------------|--------|------------------------|--------|
| registry.redhat.io | {mirror} | {type} | ✓/✗ |
| quay.io/modh | {mirror} | {type} | ✓/✗ |
| registry.redhat.io/rhaiis | {mirror} | {type} | ✓/✗ |
| registry.connect.redhat.com | {mirror} | {type} | ✓/✗ |

**Missing Mappings**: {list of registries that should be mirrored but aren't}

## Pull Secret Status
| Registry Host | Has Credentials | Auth Valid |
|---------------|-----------------|------------|
| {mirror host} | ✓/✗ | ✓/✗ |

## CA Trust Bundle
| Check | Status | Detail |
|-------|--------|--------|
| Proxy trustedCA configured | ✓/✗ | ConfigMap: {name} |
| Image additionalTrustedCA | ✓/✗ | ConfigMap: {name} |
| Registry uses self-signed cert | Yes/No/Unknown | {detail} |

## CatalogSource Health
| CatalogSource | State | Index Image | Mirror? |
|---------------|-------|-------------|---------|
| {name} | READY/TRANSIENT_FAILURE | {image ref} | ✓/✗ |

## Image Coverage Analysis
| Image Category | Required | Mapped in IDMS/ITMS | Missing |
|----------------|----------|---------------------|---------|
| Notebook images | {count} | {count} | {list} |
| Serving runtimes | {count} | {count} | {list} |
| Operator images | {count} | {count} | {list} |

## Image Pull Issues
| Namespace | Pod | Image | Error | Fix |
|-----------|-----|-------|-------|-----|
| {ns} | {pod} | {image} | ImagePullBackOff | {action} |

## Operator Source Configuration
| Operator | Source | Correct? | Issue |
|----------|--------|----------|-------|
| rhoai-operator | {catalog name} | ✓/✗ | {detail} |
| gpu-operator | {catalog name} | ✓/✗ | {detail} |

## Recommendations
1. {Prioritized fix actions — CA trust, pull secret, missing images, etc.}
```

## Domain Knowledge

- RHOAI in disconnected mode requires ALL images to be mirrored, including:
  - Operator bundle images from `registry.redhat.io/rhoai`
  - Notebook images from `quay.io/modh`
  - Runtime images for KServe (vLLM, TGI, etc.) from `registry.redhat.io/rhaiis`
  - Model mesh sidecar images
- oc-mirror v2 generates BOTH `ImageDigestMirrorSet` AND `ImageTagMirrorSet` — both must be applied
- Legacy ICSP is deprecated on OCP 4.14+; clusters should migrate to IDMS/ITMS
- The `imageset-config-template.yaml` in this repo defines what to mirror
- `patch-source.yaml` files in each operator's directory override the CatalogSource
- If an operator shows `Degraded` with `constraints not satisfiable`, the mirrored catalog may be missing dependency operators
- Common fix: re-run `oc mirror` with updated `ImageSetConfiguration` then apply new IDMS/ITMS
- Pull secret must be updated BEFORE applying IDMS/ITMS, otherwise nodes will fail to pull mirrored images
- Self-signed registry certificates require `additionalTrustBundle` in the proxy config or `additionalTrustedCA` in the image config
- x509 errors during image pull always indicate missing CA trust configuration
- The global pull secret in `openshift-config/pull-secret` is propagated to all nodes via MCO — changes trigger a rolling node reboot
- **imageID on mirrored clusters**: CRI-O records the canonical source digest in `imageID` even when pulled from a mirror. Seeing `quay.io/...` or `registry.redhat.io/...` in imageID is NORMAL and must NOT be flagged as a mirror failure.

## Safety Constraints

- Never modify pull secrets, IDMS/ITMS, or CA trust bundles directly — this is a diagnostic/read-only skill
- Never interpret `imageID` showing external registry references as a failure on mirrored clusters
- Never recommend deleting IDMS/ITMS resources without confirming replacement mirrors are in place
- Do not expose decoded pull secret credentials in output — only confirm presence/absence of auth entries
- Report findings accurately; do not suppress or escalate severity incorrectly

## Disconnected Environment Notes

- This skill is purpose-built for disconnected/air-gapped environments
- Uses `ImageDigestMirrorSet` (IDMS) and `ImageTagMirrorSet` (ITMS) — the current standard for OCP 4.14+
- Legacy `ImageContentSourcePolicy` (ICSP) is detected and flagged for migration but still supported for diagnosis
- All image references in RHOAI must be mirrored: operator bundles, notebook images, serving runtimes, and sidecars
- oc-mirror v2 workspace output (`imageDigestMirrorSet.yaml`, `imageTagMirrorSet.yaml`, `catalogSource.yaml`) can be validated before applying

## Related Skills

- `platform-setup/rhoai-install-validator` — post-install validation including disconnected integrity checks
- `platform-setup/rhoai-disconnected-deploy` — end-to-end disconnected RHOAI deployment
- `platform-setup/gitops-config-generator` — generate patches and ArgoCD Applications for disconnected config
- `monitor/argocd-health-check` — ArgoCD application health monitoring
- `administer/rhoai-dsc-inspector` — inspect DSC component status
