---
name: incident-runbook
description: "Structured incident response with escalation paths — for RHOAI operator degradation, model failures, and platform issues."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, SRE, Incident Response, Runbook, Escalation]
---

# Incident Runbook

Provides structured incident response guidance for RHOAI platform issues with diagnostic steps, severity classification, and escalation paths.

## Trigger Phrases

- "Operator X is degraded"
- "RHOAI dashboard is down"
- "Models not serving"
- "Platform incident"
- "KServe is broken"
- "Pods crashlooping in redhat-ods-applications"
- "ServiceMesh errors"

## Procedure

### Phase 1: Incident Classification

1. Identify the affected component:
   - Call `mcp_rhoai_cluster_summary` for overall platform state
   - Call `mcp_argocd_list_applications` to check GitOps health

2. Classify severity:

| Severity | Criteria | Response Time |
|----------|----------|---------------|
| P1 - Critical | All models down, platform inaccessible, data loss risk | Immediate (15 min) |
| P2 - High | Multiple models affected, key component degraded | 1 hour |
| P3 - Medium | Single model/workbench affected, workaround exists | 4 hours |
| P4 - Low | Cosmetic, non-blocking, informational | Next business day |

3. Classify impact scope:
   - **Platform-wide**: affects all users (operator failure, mesh down)
   - **Project-scoped**: affects one team/namespace
   - **Single workload**: one model/workbench/pipeline

### Phase 2: Component-Specific Runbook

4. Execute the appropriate runbook based on affected component:

---

#### Runbook: RHOAI Operator Degraded

```
1. Check operator pod: oc get pods -n redhat-ods-operator
2. Check CSV status: oc get csv -n redhat-ods-operator
3. Check Subscription: oc get sub -n redhat-ods-operator
```
- Call `mcp_argocd_get_application` for `operator-rhoai-operator`
- Call `mcp_openshift_pods_list_in_namespace` for `redhat-ods-operator`
- Call `mcp_openshift_pods_log` for the operator pod

**Common causes:**
- CatalogSource unhealthy → check mirror registry (disconnected)
- CSV pending approval → check InstallPlan
- Memory/CPU pressure → check operator pod resource usage
- Webhook failures → check cert-manager health

---

#### Runbook: Models Not Serving (KServe)

```
1. Check KServe controller: oc get pods -n redhat-ods-applications -l control-plane=kserve-controller-manager
2. Check ServiceMesh: oc get smcp -n istio-system
3. Check certificates: oc get certificates -n istio-system
```
- Call `mcp_rhoai_list_inference_services` to see model status
- Call `mcp_openshift_pods_list_in_namespace` for the model namespace
- Call `mcp_openshift_events_list` for recent errors

**Common causes:**
- ServiceMesh not ready → check SMCP status
- Certificate expired → check cert-manager and ClusterIssuer
- Gateway misconfigured → check ingress gateway pods
- Model pod OOM → check GPU/memory allocation

---

#### Runbook: Dashboard Inaccessible

```
1. Check dashboard pods: oc get pods -n redhat-ods-applications -l app=rhods-dashboard
2. Check route: oc get route -n redhat-ods-applications
3. Check OAuth: oc get oauth cluster
```
- Call `mcp_openshift_pods_list_in_namespace` for `redhat-ods-applications`
- Call `mcp_openshift_resources_get` for the dashboard Route

**Common causes:**
- Pod crash → check logs for auth/DB errors
- Route misconfigured → check TLS certificate
- OAuth provider issue → check identity provider health
- Ingress controller overloaded → check router pods

---

#### Runbook: GPU Operator Degraded

- Call `mcp_argocd_get_application` for `operator-gpu-operator`
- Call `mcp_openshift_pods_list_in_namespace` for `nvidia-gpu-operator`
- Call `mcp_openshift_nodes_top` for node-level issues

**Common causes:**
- NFD not labeling nodes → check NFD operator
- Driver pod failing → check DKMS/driver compatibility
- Node cordoned → check node conditions
- Kernel mismatch → check node OS version vs driver version

### Phase 3: Gather Evidence

5. Collect diagnostic information:
   - Call `mcp_openshift_events_list` filtered by namespace and time window
   - Call `mcp_openshift_pods_log` for affected pods (last 100 lines)
   - Call `mcp_argocd_get_application_resource_tree` for dependency mapping
   - Note any recent ArgoCD syncs that may have triggered the issue

### Phase 4: Remediation

6. Determine fix type:
   - **Restart**: pod deletion to trigger re-creation
   - **Rollback**: ArgoCD sync to previous Git revision
   - **Configuration**: patch resource/config to fix immediate issue
   - **Escalation**: issue requires vendor/upstream support

7. For ArgoCD-managed resources:
   - Check if a recent sync caused the issue
   - If so, identify the commit and consider reverting

### Phase 5: Resolution & Post-Mortem

8. Verify resolution:
   - Re-run the same checks from Phase 1
   - Confirm affected component is Healthy
9. Document:
   - Timeline of events
   - Root cause
   - Fix applied
   - Prevention measures

## Output Format

```
# Incident Report — {timestamp}

## Classification
- **Severity**: P{1-4} — {Critical/High/Medium/Low}
- **Component**: {affected component}
- **Scope**: {Platform-wide/Project-scoped/Single workload}
- **Status**: {Investigating/Identified/Mitigating/Resolved}

## Impact
- Affected users/teams: {scope}
- Affected workloads: {count and type}
- Duration: {start_time} — {current/end_time}

## Timeline
| Time | Event |
|------|-------|
| {time} | {First symptom observed} |
| {time} | {Investigation started} |
| {time} | {Root cause identified} |
| {time} | {Fix applied} |
| {time} | {Resolution confirmed} |

## Diagnostics
### Component Status
| Component | Status | Detail |
|-----------|--------|--------|
| {component} | ✓/✗ | {detail} |

### Relevant Events
| Time | Namespace | Reason | Message |
|------|-----------|--------|---------|
| {time} | {ns} | {reason} | {message} |

### Logs (relevant excerpts)
```
{log output}
```

## Root Cause
**{One-line summary}**

{Detailed explanation}

## Resolution
### Applied Fix
{What was done to resolve}

### Verification
{How we confirmed resolution}

## Escalation (if needed)
- **Escalate to**: {team/vendor}
- **Case/ticket**: {reference}
- **SLA**: {expected response time}
- **Required info**: {what to provide}

## Prevention
- **Short-term**: {immediate preventive measure}
- **Long-term**: {systemic improvement}
- **Monitoring**: {alert/check to add}
```

## Escalation Matrix

| Component | L1 (SRE) | L2 (Platform Team) | L3 (Vendor) |
|-----------|-----------|--------------------|-----------  |
| RHOAI Operator | Restart pod, check sub | Investigate CSV, DSC | Red Hat Support |
| KServe/Mesh | Check gateway, certs | Debug mesh config | Red Hat Support |
| GPU Operator | Check NFD, node status | Driver debugging | NVIDIA Support |
| ArgoCD | Check sync, rollback | RBAC, repo issues | Red Hat Support |
| Training (Ray) | Check pods, queue | Debug Ray cluster | Community |
| MLflow | Restart pod, check DB | DB migration issues | Community |

## Domain Knowledge

- RHOAI operator reconciles every 5 minutes — wait before re-checking after a fix
- ServiceMesh issues cascade: if SMCP is degraded, ALL KServe models are affected
- GPU driver updates require node drain — schedule during maintenance windows
- ArgoCD auto-sync may revert manual fixes — disable auto-sync temporarily if needed
- cert-manager certificate rotation can cause brief serving interruption
- DSC controller restarts don't affect running workloads, only reconciliation
