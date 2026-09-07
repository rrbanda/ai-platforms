---
name: gitops-config-generator
description: "Generate standalone Kustomize patches, ArgoCD Applications, Subscriptions, and DSC/DSCI CRs for RHOAI GitOps-driven configuration — works with any repo structure."
version: 2.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, GitOps, Kustomize, Configuration, ArgoCD]
---

# GitOps Configuration Generator

Generates standalone Kustomize patches, ArgoCD Application CRs, operator Subscription YAML, and DSC/DSCI resources for RHOAI configuration management. Works with any Git repository structure — paths are configurable, not assumed.

## Trigger Conditions

- "Enable component X"
- "Generate config for enabling KServe"
- "Create a patch to add ModelMesh"
- "How do I enable distributed training via GitOps?"
- "Generate overlay for production DSC"
- "Create an ArgoCD Application for RHOAI"
- "Generate operator subscription YAML"
- "Set up RHOAI from scratch via GitOps"

## Required MCP Tools

| MCP Server | Tool | Purpose |
|------------|------|---------|
| RHOAI | `cluster_summary` | Get current DSC configuration state |
| ArgoCD | `get_application` | Identify existing Git repo, path, and revision |
| GitHub | `create_or_update_file` | Push generated manifests to user's repo (optional) |
| GitHub | `create_pull_request` | Open PR with generated config changes (optional) |

## Procedure

### Phase 1: Understand Current State

1. Call `mcp_rhoai_cluster_summary` to see current DSC configuration (if cluster is available)
2. Call `mcp_argocd_get_application` for any existing DSC application to identify:
   - Git repository URL
   - Target revision/branch
   - Path within repo
3. Ask the user (if not clear from context):
   - Target directory/path in their repo for generated files
   - Environment name (dev/staging/prod) if applicable
   - Whether this is a new deployment or modification of existing
4. Identify what the user wants to generate:
   - DSC patch (enable/disable/configure components)
   - Full DSC resource (new deployment)
   - DSCInitialization resource (new deployment)
   - ArgoCD Application CR
   - Operator Subscription YAML

### Phase 2: Determine Required Changes

5. Map the requested change to the DSC spec structure:

| Component | DSC Path | Dependencies |
|-----------|----------|--------------|
| KServe | `.spec.components.kserve.managementState` | ServiceMesh, cert-manager |
| ModelMeshServing | `.spec.components.modelMeshServing.managementState` | — |
| Dashboard | `.spec.components.dashboard.managementState` | — |
| Workbenches | `.spec.components.workbenches.managementState` | — |
| DataSciencePipelines | `.spec.components.datasciencepipelines.managementState` | — |
| Ray | `.spec.components.ray.managementState` | — |
| Kueue | `.spec.components.kueue.managementState` | — |
| TrustyAI | `.spec.components.trustyai.managementState` | — |
| ModelRegistry | `.spec.components.modelregistry.managementState` | — |
| TrainingOperator | `.spec.components.trainingoperator.managementState` | — |
| FeastOperator | `.spec.components.feastoperator.managementState` | — |
| OGX | `.spec.components.ogx.managementState` | — |
| MLflowOperator | `.spec.components.mlflowoperator.managementState` | — |

Valid values: `Managed`, `Removed`, `Unmanaged`

6. Check prerequisites: if enabling KServe, verify ServiceMesh operator is healthy

### Phase 3: Generate Kustomize Patch (Component Enable/Disable)

7. Generate a **standalone** patch file that works independently of repo structure:

**For enabling a component:**
```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    <component>:
      managementState: Managed
```

**For configuring KServe with serving options:**
```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
        managementState: Managed
```

**For enabling multiple components at once:**
```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    kserve:
      managementState: Managed
    ray:
      managementState: Managed
    trainingoperator:
      managementState: Managed
    kueue:
      managementState: Managed
```

8. Generate the kustomization.yaml snippet to include the patch:
```yaml
patches:
  - path: patch-enable-<component>.yaml
    target:
      kind: DataScienceCluster
      name: default-dsc
```

### Phase 4: Generate ArgoCD Application CR (New Deployments)

9. When the user needs an ArgoCD Application for RHOAI, generate:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoai-instance
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: default
  source:
    repoURL: <USER_REPO_URL>
    targetRevision: <BRANCH>
    path: <USER_PATH>
  destination:
    server: https://kubernetes.default.svc
    namespace: redhat-ods-applications
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Customize based on user input:
- `repoURL`: user's Git repository
- `targetRevision`: branch (default: `main`)
- `path`: directory in repo where DSC manifests live
- `syncPolicy`: automated for dev, manual for prod

### Phase 5: Generate Operator Subscription YAML

10. When setting up operators via GitOps, generate Subscription resources:

**RHOAI Operator:**
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable-2.16
  installPlanApproval: <Automatic|Manual>
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**For disconnected environments, add source override:**
```yaml
  source: <custom-catalog-source-name>
  sourceNamespace: openshift-marketplace
```

Generate subscriptions for prerequisite operators as needed:
- `servicemeshoperator` (namespace: `openshift-operators`)
- `openshift-cert-manager-operator` (namespace: `cert-manager-operator`)
- `nfd` (namespace: `openshift-nfd`)
- `gpu-operator-certified` (namespace: `nvidia-gpu-operator`)

### Phase 6: Generate DSCInitialization CR (New Deployments)

11. For fresh RHOAI deployments, a DSCInitialization CR is required before the DSC:

```yaml
apiVersion: dscinitialization.opendatahub.io/v1
kind: DSCInitialization
metadata:
  name: default-dsci
spec:
  applicationsNamespace: redhat-ods-applications
  monitoring:
    managementState: Managed
    namespace: redhat-ods-monitoring
  serviceMesh:
    controlPlane:
      metricsCollection: Istio
      name: data-science-smcp
      namespace: istio-system
    managementState: Managed
  trustedCABundle:
    managementState: Managed
    customCABundle: ""
```

For disconnected environments, populate `customCABundle` with the registry CA certificate.

### Phase 7: Provide Implementation Instructions

12. Output the complete file(s) to create with user-specified paths
13. Explain how to apply via GitOps:
    - Create the generated files in the user's chosen directory
    - Ensure a `kustomization.yaml` references them (generate one if needed)
    - Commit and push to trigger ArgoCD sync
14. Warn about any prerequisites or ordering requirements:
    - DSCInitialization must exist before DSC
    - Operator subscriptions must be healthy before DSC references their components
    - Use ArgoCD sync-waves to order deployments

## Output Format

```
# GitOps Configuration Change: {description}

## Current State
- Component: {component name}
- Current managementState: {Managed/Removed/Unmanaged}
- Dependencies satisfied: {yes/no}

## Generated Files

### File: `{user-specified-path}/patch-{description}.yaml`
```yaml
{generated patch content}
```

### File: `{user-specified-path}/kustomization.yaml` (create or update)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - {base resources if new}
patches:
  - path: patch-{description}.yaml
    target:
      kind: DataScienceCluster
      name: default-dsc
```

### File: `{user-specified-path}/argocd-application.yaml` (if requested)
```yaml
{ArgoCD Application CR}
```

### File: `{user-specified-path}/subscription.yaml` (if requested)
```yaml
{Operator Subscription}
```

### File: `{user-specified-path}/dsci.yaml` (if new deployment)
```yaml
{DSCInitialization CR}
```

## Apply via GitOps
1. Create the files at the paths shown above
2. Ensure kustomization.yaml references all resources
3. Commit: `git commit -m "feat(rhoai): {description}"`
4. Push to trigger ArgoCD sync
5. Monitor: check DSC component status after sync completes

## Sync Order (if multiple resources)
1. Namespaces (sync-wave: 0)
2. Operator Subscriptions (sync-wave: 1)
3. DSCInitialization (sync-wave: 2)
4. DataScienceCluster (sync-wave: 3)

## Prerequisites
{List any operators/components that must be healthy first}

## Rollback
To revert, change `managementState` to `Removed` and push again.
For full removal, delete the ArgoCD Application or remove resources from kustomization.yaml.
```

## Domain Knowledge

- DSC patches must target `kind: DataScienceCluster` with `name: default-dsc`
- DSCInitialization is a singleton — only one can exist per cluster, named `default-dsci`
- Generated patches are standalone — they work with any Kustomize base/overlay structure
- The user's repo structure should NOT be assumed; always ask or detect from ArgoCD app config
- Common pattern: `patch-airgapped.yaml` overrides registries for disconnected environments
- KServe enabling requires: ServiceMesh operator healthy + cert-manager healthy
- Components set to `Removed` will have their operands deleted from the cluster
- `Unmanaged` means RHOAI won't reconcile the component — useful for custom configurations
- Changes to DSC are reconciled by the RHOAI operator controller — not instant, typically 2-5 minutes
- ArgoCD sync-waves ensure proper ordering: operators before DSCI before DSC
- For production, use `installPlanApproval: Manual` in Subscriptions to control upgrade timing
- RHOAI 3.5 components list: kserve, modelMeshServing, dashboard, workbenches, datasciencepipelines, ray, kueue, trustyai, modelregistry, trainingoperator, feastoperator, ogx, mlflowoperator
- `ServerSideApply=true` sync option is recommended for CRDs and large resources to avoid annotation size limits

## Safety Constraints

- Never apply generated manifests directly to the cluster — always output for user review and Git commit
- Never include credentials, tokens, or secrets in generated YAML (pull secrets, registry auth, etc.)
- Never weaken existing security settings (e.g., changing Manual installPlanApproval to Automatic in prod)
- Generated patches must be additive — do not remove components the user did not explicitly request to remove
- Always warn the user about ordering dependencies (DSCI before DSC, operators before components)

## Disconnected Environment Notes

- For disconnected environments, generated Subscriptions must use a custom CatalogSource name (not `redhat-operators`)
- DSCInitialization `trustedCABundle.customCABundle` should be populated with the mirror registry CA certificate
- Generated ArgoCD Applications in disconnected clusters must point to an internally-accessible Git repository
- Add `patch-source.yaml` overrides for each operator Subscription to point to the disconnected catalog
- Index image references in CatalogSource resources must use the mirrored registry path

## Related Skills

- `platform-setup/rhoai-install-validator` — validate the deployment after applying generated config
- `platform-setup/rhoai-disconnected-deploy` — end-to-end disconnected deployment (uses generated config)
- `platform-setup/rhoai-connected-deploy` — end-to-end connected deployment
- `platform-setup/rhoai-disconnected-helper` — diagnose disconnected mirror and pull issues
- `administer/rhoai-dsc-inspector` — inspect DSC component status after config changes
- `monitor/argocd-health-check` — verify ArgoCD sync after pushing config
