---
name: capacity-forecaster
description: "GPU/CPU utilization trends and capacity predictions — forecast when resources will be exhausted and recommend scaling."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, SRE, Capacity, GPU, Forecasting, Scaling]
---

# Capacity Forecaster

Analyzes GPU/CPU/memory utilization trends and provides capacity predictions to forecast when resources will be exhausted.

## Trigger Phrases

- "Will we run out of GPUs?"
- "Capacity forecast for next month"
- "GPU utilization trend"
- "When will we need more nodes?"
- "Resource capacity planning"
- "How much headroom do we have?"

## Procedure

### Phase 1: Current Resource Inventory

1. Call `mcp_openshift_nodes_top` to get current resource consumption:
   - CPU utilization per node
   - Memory utilization per node
2. Call `mcp_openshift_resources_list` with kind=`Node` to get node details:
   - Total allocatable resources per node
   - Node labels (GPU type, instance type)
   - Taints and conditions
3. Call `mcp_rhoai_get_cluster_resources` for RHOAI-specific view:
   - GPU allocation and utilization
   - Per-namespace resource consumption

### Phase 2: GPU-Specific Analysis

4. Calculate GPU utilization:
   - Total GPUs: sum of `nvidia.com/gpu` across all nodes
   - Allocated GPUs: sum of GPU requests across all pods
   - Available GPUs: total - allocated
   - Utilization rate: allocated / total × 100%
5. Call `mcp_openshift_pods_list` to find GPU consumers:
   - InferenceService pods (model serving)
   - Training job pods (Ray workers, TrainJobs)
   - Workbench pods with GPU accelerators
6. Break down by purpose:
   - Serving: {N} GPUs for {M} models
   - Training: {N} GPUs for {M} jobs (transient)
   - Workbenches: {N} GPUs for {M} notebooks (interactive)

### Phase 3: Trend Analysis

7. Based on current deployments, analyze growth patterns:
   - How many models are deployed (and trend from ArgoCD app count)
   - How many workbenches exist (and growth)
   - Queue depth: pending training jobs waiting for GPU
8. Call `mcp_openshift_resources_list` with kind=`ClusterQueue` (if Kueue enabled):
   - Check pending workloads in queue
   - Current queue utilization vs nominal capacity
9. Check for resource pressure signals:
   - Pods in Pending state due to GPU unavailability
   - Kueue workloads waiting > threshold

### Phase 4: Capacity Projection

10. Generate capacity forecast based on:
    - Current utilization rate
    - Growth rate (based on new deployments over time)
    - Known upcoming deployments (from Git - pending PRs/branches)
    - Buffer requirements (recommended 20-30% headroom for training bursts)

11. Calculate key thresholds:
    - **Yellow** (70% utilized): plan procurement
    - **Orange** (85% utilized): limit new deployments
    - **Red** (95% utilized): training jobs queued, urgent scaling needed

### Phase 5: Scaling Recommendations

12. Recommend scaling actions:

| Scenario | Action | Lead Time |
|----------|--------|-----------|
| GPU < 70% | No action needed | — |
| GPU 70-85% | Start procurement process | 4-8 weeks |
| GPU 85-95% | Optimize (consolidate, quantize) | 1-2 weeks |
| GPU > 95% | Emergency: pause non-critical, scale up | Immediate |
| Training queue > 2h | Add training-specific nodes | 1-2 weeks |
| Pending workbenches | Idle culling + GPU sharing | Days |

13. Optimization opportunities:
    - Models that could be quantized to use fewer GPUs
    - Idle workbenches consuming GPU without activity
    - Multi-model serving (ModelMesh) to share GPU across small models
    - Spot/preemptible nodes for training workloads

## Output Format

```
# Capacity Forecast Report — {timestamp}

## Current Utilization
| Resource | Total | Allocated | Available | Utilization |
|----------|-------|-----------|-----------|-------------|
| GPU | {total} | {alloc} | {avail} | {pct}% |
| CPU (cores) | {total} | {alloc} | {avail} | {pct}% |
| Memory | {total} | {alloc} | {avail} | {pct}% |

## GPU Breakdown
| Purpose | GPUs | Models/Jobs | Avg Util/GPU |
|---------|------|-------------|--------------|
| Serving | {n} | {m} models | {pct}% |
| Training | {n} | {m} jobs | {pct}% |
| Workbenches | {n} | {m} notebooks | {pct}% |
| Idle/Reserved | {n} | — | 0% |

## GPU by Type
| Type | Count | Allocated | Queue Depth |
|------|-------|-----------|-------------|
| A100-40GB | {n} | {alloc} | {pending} |
| A100-80GB | {n} | {alloc} | {pending} |
| T4-16GB | {n} | {alloc} | {pending} |

## Capacity Signals
| Signal | Status | Detail |
|--------|--------|--------|
| Overall utilization | 🟢/🟡/🟠/🔴 | {pct}% |
| Training queue depth | 🟢/🟡/🟠/🔴 | {pending} jobs waiting |
| Pending workbenches | 🟢/🟡/🟠/🔴 | {count} waiting for GPU |
| Growth trend | 🟢/🟡/🟠/🔴 | +{n} GPU consumers/month |

## Forecast
| Timeframe | Projected Utilization | Risk |
|-----------|-----------------------|------|
| Now | {pct}% | {Low/Medium/High} |
| +2 weeks | {pct}% | {Low/Medium/High} |
| +1 month | {pct}% | {Low/Medium/High} |
| +3 months | {pct}% | {Low/Medium/High} |

**Estimated exhaustion date**: {date or "Not projected within 6 months"}

## Recommendations
### Immediate (this week)
{actions}

### Short-term (1-4 weeks)
{actions}

### Long-term (1-3 months)
{actions}

## Optimization Opportunities
| Action | GPU Savings | Effort | Impact |
|--------|------------|--------|--------|
| {action} | {gpus freed} | {low/med/high} | {description} |
```

## Domain Knowledge

- GPU scheduling in Kubernetes is all-or-nothing — a pod requesting 1 GPU blocks 1 full GPU
- NVIDIA MPS (Multi-Process Service) can share a GPU but isn't standard in RHOAI
- Kueue manages fair queuing across teams — check ClusterQueue nominal quotas
- Training jobs are bursty — they consume GPUs for hours/days then release
- Model serving is steady-state — GPUs allocated 24/7 per model
- A100-40GB: good for models up to 13B, A100-80GB: good for models up to 34B
- Quantized models (INT8/INT4) can reduce GPU requirements by 2-4x
- GPU node provisioning on cloud takes 5-15 minutes, on-prem can take weeks
- Autoscaler (if enabled) can add nodes but not GPUs if none available in the pool
