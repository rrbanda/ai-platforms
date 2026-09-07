---
name: argocd-health-check
description: "Check health and sync status of all ArgoCD applications, report degraded or out-of-sync apps."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [ArgoCD, GitOps, Health, Monitoring]
---

# ArgoCD Health Check

Perform a comprehensive health check of all ArgoCD-managed applications.

## Procedure

1. Call `mcp_argocd_list_applications` to get all applications
2. For each application, note:
   - `status.health.status` (Healthy, Degraded, Progressing, Missing, Unknown)
   - `status.sync.status` (Synced, OutOfSync, Unknown)
   - `status.operationState.phase` (Succeeded, Failed, Running)
   - `status.operationState.finishedAt` (last sync time)
3. Group applications by health status
4. For any Degraded or OutOfSync applications:
   - Call `mcp_argocd_get_application` with the app name for details
   - Call `mcp_argocd_get_application_resource_tree` to identify failing resources
   - Call `mcp_argocd_get_resource_events` for recent events on failing resources
5. Produce a summary report:
   - Total applications, healthy count, degraded count, out-of-sync count
   - For each unhealthy app: name, status, root cause from events
   - Recommended actions

## Output format

```
# ArgoCD Health Report — {timestamp}

## Summary
- Total: {n} applications
- Healthy: {n} | Degraded: {n} | OutOfSync: {n} | Progressing: {n}

## Issues (if any)
### {app-name}
- Health: {status} | Sync: {status}
- Root cause: {explanation from events/logs}
- Recommendation: {action}

## All clear (if no issues)
All {n} applications are Healthy and Synced. [SILENT]
```

## Notes

- Applications named `operator-*` come from the cluster-operators ApplicationSet
- Applications named `instance-*` come from the cluster-instances ApplicationSet
- Sync failures on Subscriptions are often benign (startingCSV drift) — check ignoreDifferences
- If ALL apps show Unknown, the ArgoCD controller may be overloaded — check its pod logs
