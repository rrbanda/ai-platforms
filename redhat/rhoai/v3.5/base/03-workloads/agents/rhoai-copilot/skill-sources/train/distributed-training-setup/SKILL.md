---
name: distributed-training-setup
description: "Configure and launch distributed training jobs using RayJob or PyTorchJob with Kueue quota integration on Red Hat OpenShift AI."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Training, Distributed, RayJob, PyTorchJob, Kueue, CodeFlare, GPU]
---

# Distributed Training Setup

Configure and launch distributed training jobs on Red Hat OpenShift AI 3.5 using RayJob (Ray) or PyTorchJob (Kubeflow Training Operator) with Kueue-managed quota scheduling. Handles GPU resource allocation, multi-node configuration, and framework-specific settings for both NVIDIA and AMD accelerators.

## Trigger Conditions

- "Set up distributed training on OpenShift AI"
- "Launch a RayJob for model training"
- "Configure PyTorchJob with multiple GPUs"
- "Run distributed fine-tuning with Kueue quotas"
- "Set up multi-node training with RDMA"
- "Use CodeFlare SDK to submit a training job"
- "Configure training operator for distributed workloads"
- "How do I run multi-GPU training on RHOAI?"
- User wants to train a model that requires more than one GPU or one node

## Required MCP Tools

### mcp_rhoai
- `get_cluster_resources` — check available GPU types, counts, and allocatable capacity
- `list_training_jobs` — enumerate existing training jobs and their states
- `get_training_progress` — monitor active training job metrics (loss, epoch, throughput)
- `list_training_runtimes` — discover available training runtime images
- `estimate_resources` — estimate GPU/memory requirements for a given model and method

### mcp_openshift
- `nodes_top` — real-time node CPU/memory/GPU utilization
- `pods_list` — list pods in training namespaces (worker status, restarts)
- `events_list` — surface scheduling failures, OOMKills, or GPU allocation errors

## Procedure

### Phase 1: Validate Platform Readiness

1. Verify DSC components are enabled:
   ```bash
   oc get dsc default-dsc -o jsonpath='{.spec.components.ray.managementState}'
   # Must be: Managed
   oc get dsc default-dsc -o jsonpath='{.spec.components.trainingoperator.managementState}'
   # Must be: Managed
   oc get dsc default-dsc -o jsonpath='{.spec.components.kueue.managementState}'
   # Must be: Managed
   ```

2. Confirm CRDs are installed:
   ```bash
   oc get crd rayjobs.ray.io
   oc get crd pytorchjobs.kubeflow.org
   oc get crd clusterqueues.kueue.x-k8s.io
   ```

3. Call `mcp_rhoai.get_cluster_resources` to inventory available GPUs (type, count, VRAM).

4. Call `mcp_openshift.nodes_top` to assess current cluster utilization.

### Phase 2: Determine Training Framework

5. Select framework based on user requirements:

   | Criterion | RayJob | PyTorchJob |
   |-----------|--------|------------|
   | Data-parallel scaling | Excellent (Ray Data + Train) | Good (torchrun DDP) |
   | Heterogeneous resources | Supported (head vs workers) | Homogeneous only |
   | Python-first submission | CodeFlare SDK | kubectl/YAML |
   | Fault tolerance | Built-in (Ray actor recovery) | Job-level restart |
   | Ecosystem | Ray Tune, Ray Data, DeepSpeed | Native PyTorch, FSDP |
   | Multi-framework (TF+PT) | Supported | PyTorch only |

6. If user prefers Python submission over YAML, recommend CodeFlare SDK:
   ```python
   from codeflare_sdk import Cluster, ClusterConfiguration

   cluster = ClusterConfiguration(
       name="training-cluster",
       namespace="my-project",
       num_workers=4,
       min_cpus=2,
       max_cpus=4,
       min_memory="8Gi",
       max_memory="16Gi",
       num_gpus=1,
       image="quay.io/modh/ray:2.35.0-py311-cu121",
   )
   ```

### Phase 3: Configure Kueue Integration

7. Verify LocalQueue exists in the target namespace:
   ```bash
   oc get localqueue -n <namespace>
   ```

8. If no LocalQueue exists, identify the ClusterQueue and create one:
   ```yaml
   apiVersion: kueue.x-k8s.io/v1beta1
   kind: LocalQueue
   metadata:
     name: training-queue
     namespace: <namespace>
   spec:
     clusterQueue: <cluster-queue-name>
   ```

9. Confirm the ClusterQueue has GPU resource flavors allocated:
   ```bash
   oc get clusterqueue <name> -o jsonpath='{.spec.resourceGroups}'
   ```

### Phase 4: Generate Training Job Manifest

10. **For RayJob** — generate the manifest with Kueue label:
    ```yaml
    apiVersion: ray.io/v1
    kind: RayJob
    metadata:
      name: <job-name>
      namespace: <namespace>
      labels:
        kueue.x-k8s.io/queue-name: <local-queue-name>
    spec:
      shutdownAfterJobFinishes: true
      entrypoint: "python train.py --model <model> --epochs <n>"
      runtimeEnvYAML: |
        pip:
          - transformers
          - peft
          - accelerate
          - datasets
      rayClusterSpec:
        headGroupSpec:
          rayStartParams:
            dashboard-host: '0.0.0.0'
            num-gpus: "0"
          template:
            spec:
              containers:
                - name: ray-head
                  image: <training-runtime-image>
                  resources:
                    limits:
                      cpu: "4"
                      memory: "16Gi"
                    requests:
                      cpu: "2"
                      memory: "8Gi"
        workerGroupSpecs:
          - replicas: <num-gpu-workers>
            minReplicas: <num-gpu-workers>
            maxReplicas: <num-gpu-workers>
            groupName: gpu-workers
            rayStartParams:
              num-gpus: "1"
            template:
              spec:
                containers:
                  - name: ray-worker
                    image: <training-runtime-image>
                    resources:
                      limits:
                        nvidia.com/gpu: 1
                        cpu: "<cpu-per-worker>"
                        memory: "<mem-per-worker>"
                      requests:
                        nvidia.com/gpu: 1
                        cpu: "<cpu-per-worker>"
                        memory: "<mem-per-worker>"
    ```

    **Critical**: `shutdownAfterJobFinishes: true` is required for Kueue-managed RayJobs. Without it, the RayCluster persists after job completion, holding GPU quota indefinitely.

11. **For PyTorchJob** — generate the manifest with Kueue label:
    ```yaml
    apiVersion: kubeflow.org/v1
    kind: PyTorchJob
    metadata:
      name: <job-name>
      namespace: <namespace>
      labels:
        kueue.x-k8s.io/queue-name: <local-queue-name>
    spec:
      pytorchReplicaSpecs:
        Master:
          replicas: 1
          restartPolicy: OnFailure
          template:
            spec:
              containers:
                - name: pytorch
                  image: <training-runtime-image>
                  command:
                    - torchrun
                    - --nproc_per_node=<gpus-per-node>
                    - --nnodes=<num-nodes>
                    - --node_rank=0
                    - --master_addr=$(MASTER_ADDR)
                    - --master_port=$(MASTER_PORT)
                    - train.py
                  resources:
                    limits:
                      nvidia.com/gpu: <gpus-per-node>
                      memory: "<memory>"
                      cpu: "<cpus>"
        Worker:
          replicas: <num-workers>
          restartPolicy: OnFailure
          template:
            spec:
              containers:
                - name: pytorch
                  image: <training-runtime-image>
                  command:
                    - torchrun
                    - --nproc_per_node=<gpus-per-node>
                    - --nnodes=<num-nodes>
                    - --master_addr=$(MASTER_ADDR)
                    - --master_port=$(MASTER_PORT)
                    - train.py
                  resources:
                    limits:
                      nvidia.com/gpu: <gpus-per-node>
                      memory: "<memory>"
                      cpu: "<cpus>"
    ```

12. For AMD GPUs, replace `nvidia.com/gpu` with `amd.com/gpu` in resource limits.

13. For RDMA-enabled multi-node training (optional, high-performance interconnect):
    ```yaml
    spec:
      template:
        spec:
          containers:
            - name: ray-worker
              env:
                - name: NCCL_IB_DISABLE
                  value: "0"
                - name: NCCL_NET_GDR_LEVEL
                  value: "5"
              resources:
                limits:
                  rdma/rdma_shared_device_a: 1
    ```

### Phase 5: Submit and Monitor

14. Apply the training job:
    ```bash
    oc apply -f <job-manifest>.yaml
    ```

15. Verify Kueue admission:
    ```bash
    oc get workloads -n <namespace>
    # Status should transition: Pending → Admitted → Active
    ```

16. Monitor training progress:
    - Call `mcp_rhoai.get_training_progress` for loss curves and throughput
    - Call `mcp_openshift.pods_list` to check worker pod status
    - Call `mcp_openshift.events_list` to catch scheduling or OOM events

17. For RayJob, access the Ray dashboard:
    ```bash
    oc port-forward svc/<raycluster-head-svc> 8265:8265 -n <namespace>
    ```

## Output Format

```
# Distributed Training Job: {job_name}

## Platform Readiness
- Ray component: {Managed|Not Ready}
- Training Operator: {Managed|Not Ready}
- Kueue: {Managed|Not Ready}
- Available GPUs: {count}x {type} ({vram}GB each)

## Configuration
- Framework: {RayJob|PyTorchJob}
- Workers: {count} × {gpu_per_worker} GPU ({gpu_type})
- Total GPUs: {total}
- Queue: {local_queue_name} → {cluster_queue_name}
- Parallelism strategy: {DDP|FSDP|DeepSpeed ZeRO-3}

## Generated Manifest
```yaml
{complete job YAML}
```

## Submission
- Job submitted: {yes/no}
- Kueue admission: {Admitted|Pending (position {n} in queue)}
- Estimated wait: {time}

## Monitoring
- Dashboard: oc port-forward svc/{svc} 8265:8265 -n {ns}
- Progress command: hermes ask "training progress for {job_name}"
```

## Safety Constraints

- Never modify ClusterQueue quotas without explicit user approval — this affects all teams sharing the cluster
- Always set `shutdownAfterJobFinishes: true` on RayJobs to prevent GPU resource leaks
- Do not exceed the namespace ResourceQuota — check limits before submitting
- Never hardcode credentials in training scripts; use Kubernetes Secrets or data connections
- Validate the training image exists and is pullable before submitting the job
- Do not schedule training jobs on control-plane nodes
- Warn the user if the requested GPU count exceeds 80% of cluster capacity (impact on other workloads)

## Disconnected Environment Notes

- Training runtime images must be pre-mirrored to the internal registry; call `mcp_rhoai.list_training_runtimes` to discover available images
- Replace `quay.io` and `registry.redhat.io` image references with the internal mirror path
- pip packages in `runtimeEnvYAML` will fail to download — use pre-built images with dependencies baked in, or configure a PyPI mirror in the runtime environment
- HuggingFace model downloads require a model cache on PVC or S3-compatible storage (MinIO); set `HF_HOME` and `TRANSFORMERS_OFFLINE=1`
- CodeFlare SDK cluster submission works unchanged since it targets the in-cluster API server
- Dataset access must use internal S3 (MinIO/Ceph) or PVC — no external network calls
