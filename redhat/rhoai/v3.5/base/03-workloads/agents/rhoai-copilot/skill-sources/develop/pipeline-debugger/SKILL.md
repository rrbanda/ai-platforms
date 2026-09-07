---
name: pipeline-debugger
description: "Diagnose Data Science Pipeline failures — DSPA health, pipeline run errors, and step-level troubleshooting."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, MLOps, Pipelines, DSPA, Debugging, Troubleshooting]
---

# Pipeline Debugger

Diagnoses Data Science Pipeline Application (DSPA) health issues and pipeline run failures with step-level troubleshooting.

## Trigger Phrases

- "Why did my pipeline fail?"
- "Pipeline run stuck in pending"
- "DSPA not working"
- "Debug pipeline step failure"
- "Pipeline server not ready"

## Procedure

### Phase 1: DSPA Health Check

1. Call `mcp_rhoai_get_pipeline_server` to check DSPA status:
   - Is the pipeline server deployed?
   - Is it in Ready state?
   - What's the backend (Argo Workflows / Tekton)?
2. Call `mcp_openshift_pods_list_in_namespace` for the project namespace:
   - Look for `ds-pipeline-*` pods
   - Check if they're Running or in error state
3. If DSPA pods are unhealthy, call `mcp_openshift_pods_log` for the failing pod:
   - Look for database connection errors (MariaDB/MySQL)
   - Look for object storage errors (S3/Minio connectivity)

### Phase 2: Pipeline Run Analysis

4. Identify the failed pipeline run:
   - Ask user for the run name or get the latest failed run
5. Call `mcp_openshift_pods_list_in_namespace` filtering for pipeline run pods:
   - Look for pods matching the run ID pattern
   - Identify which step pod failed
6. For the failed step pod:
   - Call `mcp_openshift_pods_get` to see status and exit code
   - Call `mcp_openshift_pods_log` to get container logs
   - Call `mcp_openshift_events_list` filtered to that pod

### Phase 3: Common Failure Patterns

7. Match error against known patterns:

| Error Pattern | Cause | Fix |
|--------------|-------|-----|
| `OOMKilled` | Step exceeded memory limit | Increase resource request |
| `ImagePullBackOff` | Pipeline step image not available | Check image registry access |
| `ContainerCannotRun` | Permission/security context issue | Check SCC/pod security |
| `DeadlineExceeded` | Step took too long | Increase timeout or optimize |
| `connection refused` on DB | MariaDB pod not ready | Check `mariadb-*` pod health |
| `NoCredentialProviders` | S3 credentials missing | Check data connection secret |
| `PipelineRunTimeout` | Overall run timeout | Increase pipeline timeout |
| `TaskRunValidationFailed` | Invalid parameter/artifact reference | Check pipeline definition |
| `ResourceQuotaExceeded` | Namespace quota hit | Request quota increase |
| `PodSchedulingFailed` | No nodes with sufficient resources | Check node availability |

### Phase 4: Dependency Validation

8. Check pipeline infrastructure dependencies:
   - Database: `mcp_openshift_pods_list_in_namespace` for `mariadb-*`
   - Object Storage: verify data connection secret exists
   - ArgoCD sync: `mcp_argocd_get_application` for the project's pipeline config
9. Call `mcp_rhoai_list_data_connections` to verify S3/storage connectivity:
   - Confirm endpoint URL is reachable
   - Confirm bucket exists

### Phase 5: Provide Fix Recommendations

10. Based on the diagnosis, recommend:
    - Immediate fix (patch/restart)
    - Configuration change (resource limits, timeouts)
    - Infrastructure fix (quota, node scheduling)
    - Pipeline definition fix (image, parameters)

## Output Format

```
# Pipeline Debug Report — {timestamp}

## Pipeline Run: {run_name}
- Status: {Failed/Pending/Running}
- Started: {start_time}
- Duration: {duration}
- Failed Step: {step_name}

## DSPA Health
| Component | Status | Detail |
|-----------|--------|--------|
| Pipeline Server | ✓/✗ | {status} |
| Database (MariaDB) | ✓/✗ | {status} |
| Object Storage | ✓/✗ | {connectivity} |
| Workflow Engine | ✓/✗ | {argo/tekton status} |

## Failed Step Analysis
- Step: {step_name}
- Container: {container_name}
- Image: {image_ref}
- Exit Code: {code}
- Reason: {reason}

### Logs (last 20 lines)
```
{relevant log output}
```

### Events
| Time | Type | Reason | Message |
|------|------|--------|---------|
| {time} | Warning | {reason} | {message} |

## Root Cause
**{One-line root cause}**

{Detailed explanation of why this happened}

## Fix
### Immediate
{What to do right now to fix/retry}

### Prevent Recurrence
{Configuration/infrastructure changes to prevent this}

## Retry Command
After applying the fix, retry the pipeline run via the RHOAI dashboard or:
`oc create -f {pipeline-run-yaml} -n {namespace}`
```

## Domain Knowledge

- DSPA in RHOAI uses Argo Workflows as the backend (not Tekton for newer versions)
- Pipeline pods run in the user's Data Science Project namespace, not redhat-ods-applications
- MariaDB is deployed per-DSPA instance for metadata storage
- Pipeline artifacts are stored in the data connection's S3 bucket
- Pipeline step images must be pullable from the namespace's image pull secrets
- Resource limits on pipeline steps default to the namespace's LimitRange
- Long-running training steps may hit the Argo Workflow's global timeout (default: 12h)
- DSPA requires a `DataSciencePipelinesApplication` CR in the project namespace
