---
name: workbench-troubleshooter
description: "Diagnose workbench startup failures — OOM, quota exceeded, image pull errors, and PVC issues."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Data Scientist, Workbench, Notebook, Troubleshooting]
---

# Workbench Troubleshooter

Diagnoses workbench (Jupyter notebook) startup failures including OOM kills, quota issues, image pull errors, and PVC binding problems.

## Trigger Phrases

- "My workbench won't start"
- "Notebook stuck in starting"
- "Workbench keeps crashing"
- "Why is my notebook OOMKilled?"
- "Workbench image not found"
- "PVC not binding for my workbench"

## Procedure

### Phase 1: Identify the Workbench

1. Call `mcp_rhoai_list_workbenches` to find the problematic workbench:
   - Note the workbench name, namespace, and current status
   - Identify the notebook image being used
2. Call `mcp_rhoai_get_workbench` for detailed status:
   - Check `status.conditions` for failure reasons
   - Note resource requests (CPU, memory, GPU)
   - Note PVC configuration

### Phase 2: Pod-Level Diagnostics

3. Call `mcp_openshift_pods_list_in_namespace` for the workbench namespace:
   - Find the workbench pod (pattern: `{workbench-name}-0` or similar StatefulSet pod)
   - Check pod phase: Pending, Running, CrashLoopBackOff, Error
4. Based on pod status:

**If Pending:**
- Call `mcp_openshift_events_list` filtered to the pod:
  - Look for `FailedScheduling` (resource constraints)
  - Look for `FailedAttachVolume` (PVC issues)
  - Look for `Unschedulable` (node affinity/taint issues)

**If CrashLoopBackOff:**
- Call `mcp_openshift_pods_log` for the pod:
  - Look for OOMKilled in previous termination
  - Look for permission errors
  - Look for startup script failures

**If ImagePullBackOff:**
- Call `mcp_openshift_pods_get` to see exact image reference
- Verify image exists in the configured registry

### Phase 3: Resource Analysis

5. Check namespace quotas:
   - Call `mcp_openshift_resources_list` with kind=`ResourceQuota` in the namespace
   - Compare workbench requests against remaining quota
6. Check GPU availability (if GPU workbench):
   - Call `mcp_openshift_nodes_top` to see GPU utilization
   - Call `mcp_openshift_resources_list` for `ClusterQueue` or `LocalQueue` (if Kueue enabled)
7. Check PVC status:
   - Call `mcp_openshift_resources_list` with kind=`PersistentVolumeClaim` in the namespace
   - Verify PVC is Bound and has sufficient capacity

### Phase 4: Common Patterns & Fixes

8. Match against known failure patterns:

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Pod Pending + FailedScheduling | Insufficient resources | Reduce workbench size or scale cluster |
| Pod Pending + Unschedulable | No GPU nodes / taint issue | Check GPU node labels and tolerations |
| OOMKilled | Memory limit too low | Increase memory in workbench config |
| ImagePullBackOff | Image not in registry | Use supported notebook image from list |
| CrashLoopBackOff + permission denied | SCC too restrictive | Check namespace SecurityContextConstraints |
| PVC Pending | StorageClass unavailable | Verify default StorageClass exists |
| PVC Pending + WaitForFirstConsumer | PVC waiting for pod scheduling | Normal — schedule first, then binds |
| Startup timeout | Large image + slow pull | Pre-pull image or use smaller image |

### Phase 5: Provide Resolution

9. Generate fix recommendation based on root cause
10. If applicable, check available notebook images:
    - Call `mcp_rhoai_list_notebook_images`
    - Suggest alternative images that might avoid the issue

## Output Format

```
# Workbench Troubleshooting Report

## Workbench: {name}
- Namespace: {namespace}
- Image: {image}
- Status: {current_status}
- Created: {timestamp}
- Last Transition: {timestamp}

## Diagnosis

### Pod Status: {phase}
| Condition | Status | Reason | Message |
|-----------|--------|--------|---------|
| {type} | True/False | {reason} | {message} |

### Resource Check
| Resource | Requested | Limit | Available | Sufficient? |
|----------|-----------|-------|-----------|-------------|
| CPU | {req} | {limit} | {avail} | ✓/✗ |
| Memory | {req} | {limit} | {avail} | ✓/✗ |
| GPU | {req} | {limit} | {avail} | ✓/✗ |
| PVC | {size} | — | {status} | ✓/✗ |

### Events (last 10)
| Time | Type | Reason | Message |
|------|------|--------|---------|
| {time} | {type} | {reason} | {message} |

## Root Cause
**{One-line root cause}**

{Detailed explanation}

## Fix
### Immediate Action
{Steps to fix right now}

### Alternative
{Alternative approach if immediate fix isn't possible}

## Available Notebook Images
| Image | Size | GPU Support | Status |
|-------|------|-------------|--------|
| {name} | {size} | ✓/✗ | Available |
```

## Domain Knowledge

- Workbenches in RHOAI are StatefulSets (not Deployments) — they maintain PVC state
- Default notebook images: Jupyter, VS Code, RStudio — each with CPU and CUDA variants
- CUDA images are significantly larger (~8-15GB) — first pull can timeout
- Workbench pods need `anyuid` SCC if running as non-root (default in RHOAI)
- GPU workbenches need nodes with matching accelerator profile labels
- PVCs use the namespace's default StorageClass unless overridden
- Idle workbench culling is configured at the cluster level — workbenches auto-stop after inactivity
- Data connections (S3 secrets) are mounted as environment variables in the workbench pod
