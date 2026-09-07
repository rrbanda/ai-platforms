---
name: hardware-profile-manager
description: "Create and manage hardware profiles to target specific accelerator types and CPU-only nodes for workbenches, model serving, and pipelines."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Hardware Profiles, Accelerators, GPU, Node Selectors, Workbenches, Model Serving]
---

# Hardware Profile Manager

Create and manage hardware profiles that define resource templates (CPU, memory, accelerators) and node targeting for RHOAI workloads. Hardware profiles replace the legacy accelerator profile mechanism and provide a unified way to assign compute resources to workbenches, model serving, and pipeline runs.

## Trigger Conditions

- "Create a hardware profile for A100 GPUs"
- "Set up a CPU-only profile for lightweight notebooks"
- "Configure node selectors to pin workloads to GPU nodes"
- "List available hardware profiles"
- "Which accelerator profiles are configured?"
- "My workbench can't see GPUs — check hardware profiles"
- "Create a profile for multi-GPU model serving"
- "How do I target a specific node pool for training?"
- "Set default hardware profile for a namespace"
- "Migrate from accelerator profiles to hardware profiles"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `get_cluster_resources` | Current GPU/CPU allocation across the cluster |
| mcp_rhoai | `list_workbenches` | Workbenches consuming hardware profiles |
| mcp_openshift | `nodes_top` | Node-level resource utilization and GPU availability |
| mcp_openshift | `resources_list` | List HardwareProfile CRs, Nodes, accelerator labels |
| mcp_openshift | `resources_get` | Inspect individual HardwareProfile or Node details |

## Procedure

### Phase 1: Discover Cluster Hardware

1. Call `mcp_openshift_nodes_top` to get current node resource utilization:
   - Identify nodes with GPUs (look for `nvidia.com/gpu` in allocatable)
   - Note CPU/memory capacity per node
   - Identify node roles and instance types

2. Call `mcp_openshift_resources_list` with kind=`Node` to enumerate hardware:
   - Extract GPU labels: `nvidia.com/gpu.product` (e.g., `NVIDIA-A100-SXM4-40GB`)
   - Extract instance type labels: `node.kubernetes.io/instance-type`
   - Note taints that restrict scheduling (e.g., `nvidia.com/gpu=present:NoSchedule`)
   - Identify node pools or MachineSet groupings

3. Call `mcp_rhoai_get_cluster_resources` for the RHOAI-level view:
   - GPU allocation by namespace
   - Which workloads are consuming GPUs

### Phase 2: Audit Existing Profiles

4. List existing hardware profiles:
   ```bash
   oc get hardwareprofiles -n redhat-ods-applications
   ```

5. List legacy accelerator profiles (if any remain):
   ```bash
   oc get acceleratorprofiles -n redhat-ods-applications
   ```

6. Check the dashboard configuration for profile visibility:
   ```bash
   oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
     -o jsonpath='{.spec.notebookController.notebookTolerationSettings}'
   ```

### Phase 3: Create Hardware Profiles

7. Based on user requirements, generate the appropriate HardwareProfile CR.

**GPU Hardware Profile (e.g., NVIDIA A100 40GB):**

```yaml
apiVersion: dashboard.opendatahub.io/v1alpha1
kind: HardwareProfile
metadata:
  name: nvidia-gpu-a100-40gb
  namespace: redhat-ods-applications
spec:
  displayName: "NVIDIA A100 40GB GPU"
  description: "Single NVIDIA A100 40GB GPU for model serving and training"
  enabled: true
  identifiers:
    - displayName: CPU
      identifier: cpu
      defaultCount: 4
      minCount: 1
      maxCount: 16
    - displayName: Memory
      identifier: memory
      defaultCount: 16
      minCount: 4
      maxCount: 64
      units: Gi
    - displayName: "NVIDIA GPU"
      identifier: nvidia.com/gpu
      defaultCount: 1
      minCount: 1
      maxCount: 8
  nodeSelectors:
    nvidia.com/gpu.product: "NVIDIA-A100-SXM4-40GB"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
```

**Multi-GPU Profile (e.g., 4x A100 for large model serving):**

```yaml
apiVersion: dashboard.opendatahub.io/v1alpha1
kind: HardwareProfile
metadata:
  name: nvidia-gpu-a100-4x
  namespace: redhat-ods-applications
spec:
  displayName: "4x NVIDIA A100 40GB (Multi-GPU)"
  description: "Four NVIDIA A100 GPUs for large language model serving and distributed training"
  enabled: true
  identifiers:
    - displayName: CPU
      identifier: cpu
      defaultCount: 16
      minCount: 8
      maxCount: 64
    - displayName: Memory
      identifier: memory
      defaultCount: 64
      minCount: 32
      maxCount: 256
      units: Gi
    - displayName: "NVIDIA GPU"
      identifier: nvidia.com/gpu
      defaultCount: 4
      minCount: 4
      maxCount: 8
  nodeSelectors:
    nvidia.com/gpu.product: "NVIDIA-A100-SXM4-40GB"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
```

**CPU-Only Profile:**

```yaml
apiVersion: dashboard.opendatahub.io/v1alpha1
kind: HardwareProfile
metadata:
  name: cpu-small
  namespace: redhat-ods-applications
spec:
  displayName: "CPU Small (Development)"
  description: "Lightweight CPU-only profile for data exploration and code development"
  enabled: true
  identifiers:
    - displayName: CPU
      identifier: cpu
      defaultCount: 2
      minCount: 1
      maxCount: 8
    - displayName: Memory
      identifier: memory
      defaultCount: 8
      minCount: 2
      maxCount: 32
      units: Gi
  nodeSelectors:
    node-role.kubernetes.io/worker: ""
  tolerations: []
```

8. Apply the profile:
   ```bash
   oc apply -f hardware-profile.yaml
   ```

9. Verify the profile is visible in the dashboard:
   ```bash
   oc get hardwareprofile <name> -n redhat-ods-applications -o yaml
   ```

### Phase 4: Validate Profile Assignment

10. Confirm workloads can schedule with the new profile:
    - Call `mcp_openshift_nodes_top` to verify target nodes have available capacity
    - Check that node selectors match at least one schedulable node
    - Verify tolerations align with node taints

11. If the profile targets GPU nodes, confirm the GPU Operator is healthy:
    ```bash
    oc get pods -n nvidia-gpu-operator -l app=nvidia-device-plugin-daemonset --no-headers
    ```

12. Test by creating a minimal workbench or serving runtime that references the profile and verifying it schedules correctly.

### Phase 5: Generate GitOps Manifests

13. Output the HardwareProfile YAML in a format suitable for ArgoCD/Kustomize:
    - Place under the appropriate overlay directory
    - Include in the Kustomization resource list
    - Strip server-side fields (`status`, `resourceVersion`, `uid`, `creationTimestamp`)

## Output Format

```
# Hardware Profile Report — {timestamp}

## Cluster Hardware Inventory
| Node | Instance Type | GPUs | GPU Type | CPU | Memory | Taints |
|------|--------------|------|----------|-----|--------|--------|
| {node} | {type} | {count} | {product} | {cpu} | {mem} | {taints} |

## Existing Hardware Profiles
| Name | Display Name | GPU | CPU Range | Memory Range | Node Selector | Enabled |
|------|-------------|-----|-----------|-------------|---------------|---------|
| {name} | {display} | {gpu_id} | {min}-{max} | {min}-{max} | {selectors} | ✓/✗ |

## Created/Updated Profile
- Name: {name}
- Display Name: {displayName}
- Identifiers: CPU {min}-{max}, Memory {min}-{max}Gi, GPU {min}-{max}
- Node Selectors: {selectors}
- Tolerations: {tolerations}
- Status: Applied ✓

## GitOps Manifest
{YAML for ArgoCD deployment}

## Validation
| Check | Status |
|-------|--------|
| Matching nodes found | ✓/✗ ({count} nodes) |
| GPU device plugin healthy | ✓/✗ |
| Node capacity available | ✓/✗ |
| Profile visible in dashboard | ✓/✗ |
```

## Safety Constraints

- Never delete a hardware profile that is actively referenced by running workbenches or InferenceServices — check consumers first
- Do not set GPU `maxCount` higher than the maximum GPUs available on any single node in the cluster
- Always include tolerations when targeting tainted GPU nodes — without them, pods will remain Pending indefinitely
- Node selectors must match actual node labels — verify with `oc get nodes --show-labels` before applying
- Hardware profiles are cluster-scoped within `redhat-ods-applications` — changes affect all namespaces
- Never set `minCount` for memory below 2Gi for notebook workloads — the Jupyter process itself requires at least 1.5Gi
- All changes must go through Git (PR) — never apply hardware profiles directly with `oc apply` in production

## Disconnected Environment Notes

- GPU node labels are set by the NVIDIA GPU Operator — verify it is installed from the disconnected OperatorHub catalog
- The `nvidia-device-plugin-daemonset` must be running on GPU nodes; in disconnected environments, ensure the device plugin image is mirrored to the internal registry
- Hardware profile CRDs are part of the RHOAI operator — no additional image pulls are required for profile management
- If using custom node labels for hardware targeting, document them in the cluster inventory so they persist across node replacements
