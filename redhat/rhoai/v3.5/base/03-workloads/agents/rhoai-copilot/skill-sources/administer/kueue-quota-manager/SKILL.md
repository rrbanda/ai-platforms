---
name: kueue-quota-manager
description: "Configure Kueue quota management for distributed training, model serving, and workbench workloads — manage ClusterQueues, LocalQueues, and ResourceFlavors."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Kueue, Quota, GPU, Training, Scheduling, Administration]
---

# Kueue Quota Manager

Configure Kueue quota management for distributed training, model serving, and workbench workloads on RHOAI. Manage ClusterQueues, LocalQueues, ResourceFlavors, and admission policies to ensure fair resource sharing across teams and workload types.

## Trigger Conditions

- "Set up GPU quotas for my team"
- "Configure Kueue for distributed training"
- "Why is my training job not starting?"
- "Create a ClusterQueue for model serving"
- "How much GPU quota does my namespace have?"
- "Set up resource sharing between teams"
- "Migrate from embedded Kueue to the operator"
- "Configure preemption policies for training jobs"
- "Add a LocalQueue to my namespace"
- "Check pending workloads in the queue"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | get_cluster_resources | GPU and resource inventory |
| mcp_rhoai | list_training_jobs | Training job status and queue info |
| mcp_openshift | resources_list | List Kueue CRs (ClusterQueue, LocalQueue, ResourceFlavor, Workload) |
| mcp_openshift | resources_get | Get specific Kueue resource details |
| mcp_openshift | nodes_top | Node resource utilization |
| mcp_openshift | events_list | Admission and scheduling events |
| mcp_argocd | get_application | Kueue config GitOps application status |

## Procedure

### Phase 1: Kueue Installation Assessment

1. Verify Kueue operator status:
   - Call `mcp_openshift` → `resources_list` with kind=`Subscription` in namespace `openshift-operators` to find the Kueue operator
   - The **Red Hat build of Kueue Operator** replaces the embedded kueue component starting in RHOAI 3.5
   - DSC component `kueue` must have `managementState: Managed`
2. Check for migration requirements:
   - If upgrading from RHOAI < 3.5, the embedded kueue must be migrated to the standalone operator
   - Call `mcp_openshift` → `resources_list` with kind=`ClusterQueue` to see existing configuration
   - Existing ClusterQueues, LocalQueues, and ResourceFlavors are preserved during migration

### Phase 2: Resource Inventory

3. Call `mcp_rhoai` → `get_cluster_resources` to determine available resources:
   - GPU types: NVIDIA (A100, H100, L40S, T4) and AMD (MI300X)
   - GPU counts per node
   - CPU and memory capacity
4. Call `mcp_openshift` → `nodes_top` for current utilization
5. Call `mcp_openshift` → `resources_list` with kind=`ResourceFlavor` to enumerate existing flavors:
   - Each ResourceFlavor represents a hardware class (e.g., `gpu-a100-40gb`, `gpu-t4`, `cpu-only`)
   - Flavors use node labels and taints to match hardware

### Phase 3: ResourceFlavor Configuration

6. For each hardware class, define or verify a ResourceFlavor:
   ```yaml
   apiVersion: kueue.x-k8s.io/v1beta1
   kind: ResourceFlavor
   metadata:
     name: gpu-a100-80gb
   spec:
     nodeLabels:
       nvidia.com/gpu.product: NVIDIA-A100-SXM4-80GB
     tolerations:
       - key: nvidia.com/gpu
         operator: Exists
         effect: NoSchedule
   ```
7. Common ResourceFlavor patterns:
   - `default-gpu`: any GPU node (`nvidia.com/gpu.present: "true"`)
   - `gpu-a100-40gb`: specific GPU type for large models
   - `gpu-t4`: budget GPU for inference and small training
   - `cpu-only`: non-GPU workloads (workbenches without accelerator)

### Phase 4: ClusterQueue Configuration

8. Design ClusterQueue based on organizational needs:
   ```yaml
   apiVersion: kueue.x-k8s.io/v1beta1
   kind: ClusterQueue
   metadata:
     name: team-ml-cq
   spec:
     namespaceSelector:
       matchLabels:
         kueue.openshift.io/managed: "true"
     resourceGroups:
       - coveredResources: ["cpu", "memory", "nvidia.com/gpu"]
         flavors:
           - name: gpu-a100-80gb
             resources:
               - name: "nvidia.com/gpu"
                 nominalQuota: 8
                 borrowingLimit: 4
                 lendingLimit: 2
               - name: "cpu"
                 nominalQuota: 64
               - name: "memory"
                 nominalQuota: 256Gi
     preemption:
       reclaimWithinCohort: Any
       withinClusterQueue: LowerPriority
   ```
9. Key ClusterQueue parameters:
   - **nominalQuota**: guaranteed resources for this queue
   - **borrowingLimit**: maximum resources borrowed from other queues in the cohort
   - **lendingLimit**: maximum resources lent to other queues
   - **cohort**: group of ClusterQueues that share resources
   - **preemption**: policies for reclaiming lent resources

### Phase 5: LocalQueue Setup

10. Create LocalQueues in user namespaces:
    ```yaml
    apiVersion: kueue.x-k8s.io/v1beta1
    kind: LocalQueue
    metadata:
      name: team-ml-lq
      namespace: ml-project
      annotations:
        kueue.x-k8s.io/default-queue: "true"
    spec:
      clusterQueue: team-ml-cq
    ```
11. Namespace requirements:
    - Namespace must have label `kueue.openshift.io/managed=true` (auto-applied by RHOAI Dashboard when creating Data Science Projects)
    - The validating webhook enforces that workloads in managed namespaces include the `kueue.x-k8s.io/queue-name` label
    - Set `kueue.x-k8s.io/default-queue: "true"` annotation to make it the default queue for the namespace

### Phase 6: Workload Integration

12. Managed workload types and their queue-name label injection:
    | Workload | Label Location | Auto-injected |
    |----------|---------------|---------------|
    | RayJob | `.spec.template.metadata.labels` | No — user must set |
    | RayCluster | `.metadata.labels` | No — user must set |
    | PyTorchJob | `.metadata.labels` | No — user must set |
    | Notebook (workbench) | `.metadata.labels` | Yes — Dashboard sets |
    | InferenceService | `.metadata.labels` | Yes — Dashboard sets |

13. For training jobs, ensure the queue-name label is set:
    ```yaml
    metadata:
      labels:
        kueue.x-k8s.io/queue-name: team-ml-lq
    ```
14. Call `mcp_rhoai` → `list_training_jobs` to check training workload queue status

### Phase 7: Monitoring and Troubleshooting

15. Call `mcp_openshift` → `resources_list` with kind=`Workload` to check admission status:
    - `Admitted: True` → workload is running
    - `Admitted: False` with condition `Pending` → waiting for quota
    - `Admitted: False` with condition `Inadmissible` → cannot be admitted (check quota)
16. Call `mcp_openshift` → `events_list` to find admission-related events:
    - `FailedAdmission`: quota insufficient
    - `Preempted`: workload evicted for higher priority
    - `QuotaReserved`: resources allocated
17. Common troubleshooting:
    - **Job stuck pending**: Check ClusterQueue `.status.pendingWorkloads` and available quota
    - **Missing queue-name label**: Webhook rejects pod — add `kueue.x-k8s.io/queue-name` label
    - **Namespace not managed**: Add `kueue.openshift.io/managed=true` label to namespace
    - **Preemption not working**: Verify PriorityClass is set and preemption policy allows it

### Phase 8: GitOps Integration

18. Call `mcp_argocd` → `get_application` for the Kueue configuration application to verify sync status
19. All Kueue CRs must be committed to Git and deployed via ArgoCD:
    - ResourceFlavors: `clusters/{cluster}/kueue/resource-flavors/`
    - ClusterQueues: `clusters/{cluster}/kueue/cluster-queues/`
    - LocalQueues: `clusters/{cluster}/namespaces/{ns}/local-queues/`

## Output Format

```
# Kueue Quota Configuration — {timestamp}

## Kueue Operator Status
- Operator: {Red Hat build of Kueue Operator}
- Version: {version}
- DSC state: {Managed/Removed}
- Migration: {complete/required/not applicable}

## Resource Inventory
| Node | GPU Type | GPU Count | CPU | Memory | Labels |
|------|----------|-----------|-----|--------|--------|
| {node} | {type} | {count} | {cores} | {gb} GB | {labels} |

## ResourceFlavors
| Flavor | Node Selector | Tolerations | Matched Nodes |
|--------|--------------|-------------|---------------|
| {name} | {labels} | {tolerations} | {count} |

## ClusterQueues
| Queue | Cohort | GPU Quota | Borrowed | Pending | Admitted |
|-------|--------|-----------|----------|---------|----------|
| {name} | {cohort} | {nominal}/{limit} | {borrowed} | {pending} | {admitted} |

## LocalQueues
| Queue | Namespace | ClusterQueue | Pending Workloads | Default |
|-------|-----------|-------------|-------------------|---------|
| {name} | {ns} | {cq} | {count} | {yes/no} |

## Workload Status
| Workload | Type | Namespace | Queue | State | Wait Time |
|----------|------|-----------|-------|-------|-----------|
| {name} | {RayJob/PyTorchJob/...} | {ns} | {queue} | {Admitted/Pending} | {duration} |

## Issues Detected
| Issue | Resource | Resolution |
|-------|----------|------------|
| {description} | {resource} | {fix} |

## Recommended Configuration
{YAML manifests or changes needed}

## GitOps Path
- Commit to: {path in git repo}
- ArgoCD app: {app name}
```

## Safety Constraints

- Never reduce quota below currently admitted workloads — this causes preemption cascades
- Do not delete ClusterQueues with active workloads without explicit user confirmation
- Verify preemption policies before enabling — can disrupt running training jobs
- Always validate ResourceFlavor node selectors match actual cluster nodes
- Do not modify Kueue CRs directly via kubectl — all changes through Git PRs
- Warn before enabling borrowing/lending if teams have strict resource isolation requirements
- Never remove the `kueue.openshift.io/managed=true` label from namespaces with active workloads
- Validate that GPU quota totals do not exceed physical GPU count (overcommit is intentional only with lending)

## Disconnected Environment Notes

- The Red Hat build of Kueue Operator must be installed from the mirrored OperatorHub catalog
- Operator images must exist in the mirrored registry (check ImageContentSourcePolicy)
- Kueue validating/mutating webhooks require cert-manager or manual certificate provisioning
- ResourceFlavor node labels must match the actual GPU hardware available (verify with `nvidia-smi` output or NFD labels)
- In air-gapped environments, training job container images must be pre-pulled or available from internal registry
- Monitoring dashboards for Kueue metrics require Prometheus with the cluster-monitoring-config ConfigMap properly configured
