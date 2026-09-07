---
name: argocd-diagnose-sync
description: "Diagnose sync failures for a specific ArgoCD application and suggest remediation."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [ArgoCD, GitOps, Troubleshooting, Sync]
---

# ArgoCD Sync Diagnosis

Diagnose why a specific ArgoCD application is out-of-sync or failing to sync.

## Procedure

1. Call `mcp_argocd_get_application` with the application name
2. Check `status.operationState`:
   - `phase`: Running, Failed, Error, Succeeded
   - `message`: The error message from the last sync attempt
   - `syncResult.resources`: Per-resource sync status
3. Call `mcp_argocd_get_application_resource_tree` to see all managed resources
4. For resources with `health.status != Healthy`:
   - Call `mcp_argocd_get_resource_events` for that resource
   - Call `mcp_argocd_get_application_workload_logs` if it's a Pod/Deployment
5. Analyze the failure pattern and categorize:

## Common failure patterns for RHOAI

| Pattern | Symptom | Fix |
|---------|---------|-----|
| CRD not ready | `resource mapping not found` | Operator not yet installed — check sync-wave ordering |
| Subscription drift | OutOfSync on `/spec/startingCSV` | Already in ignoreDifferences — verify it's applied |
| ImagePullBackOff | Pod stuck in ContainerCreating | Mirror not configured for disconnected env |
| Namespace missing | `namespaces "X" not found` | Add `CreateNamespace=true` to syncOptions |
| RBAC denied | `forbidden: User "system:serviceaccount:..."` | ClusterRole/Binding missing — check rbac.yaml |
| Webhook timeout | `failed calling webhook` | Operator webhook not ready — wait or check cert-manager |
| Resource conflict | `the object has been modified` | Enable ServerSideApply in syncOptions |

## Output format

```
# Sync Diagnosis: {app-name}

## Status
- Sync: {OutOfSync/Synced} | Health: {status}
- Last sync attempt: {timestamp} — {phase}
- Error: {message}

## Failing resources
| Resource | Kind | Status | Message |
|----------|------|--------|---------|
| {name}   | {kind} | {status} | {msg} |

## Root cause
{explanation of the failure pattern}

## Recommended fix
{specific steps to resolve — e.g., "Add the following to ignoreDifferences..." or "Run sync with prune=true"}
```

## Notes

- If the fix requires a manifest change, suggest the exact YAML patch for the Git repo
- For sync operations, always recommend dry-run first
- If the error is transient (webhook timeout, temporary network), suggest retry with backoff
- Never suggest deleting and recreating the Application — that's managed by ApplicationSet
