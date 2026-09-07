---
name: rhoai-upgrade-advisor
description: "Advise on RHOAI operator upgrades — check version compatibility, CRD readiness, and produce safe upgrade checklists."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, Upgrade, OLM, Subscription, Version]
---

# RHOAI Upgrade Advisor

Assess upgrade readiness and produce safe upgrade checklists for RHOAI operators.

## RHOAI Upgrade Patterns

RHOAI upgrades flow through these channels:
- `fast` — Latest GA releases (recommended for non-production)
- `stable` — LTS releases (recommended for production)
- `beta` — Early Access releases (for testing new features)

Upgrade path: Change `patch-channel.yaml` in Git → ArgoCD syncs → OLM processes Subscription change → New CSV installs

## Procedure

1. Call `mcp_argocd_get_application_managed_resources` for `operator-rhoai-operator`
2. From the Subscription resource, extract:
   - Current channel
   - Current startingCSV (installed version)
   - InstallPlan status
   - Any conditions (ResolutionFailed, etc.)
3. Check dependent operators for compatibility:
   - cert-manager: Get its Subscription via `operator-cert-manager` managed resources
   - servicemesh: Get its Subscription via `operator-servicemesh` managed resources
   - nfd + gpu-operator: Same pattern
4. Check the DSC for component health:
   - If DSC shows degraded components, upgrading may make things worse
5. Produce the upgrade advisory

## Pre-Upgrade Checklist

Before recommending any upgrade:

- [ ] All dependency operators (cert-manager, servicemesh, nfd) are Healthy
- [ ] DataScienceCluster is Healthy with no degraded components
- [ ] No pending workloads in Kueue queues (avoid disrupting running jobs)
- [ ] Cluster nodes have sufficient resources (no DiskPressure, MemoryPressure)
- [ ] Backup of current DSC configuration exists in Git (it does — this is GitOps)
- [ ] No active model serving disruption window conflicts

## Output Format

```
# RHOAI Upgrade Advisory — {timestamp}

## Current State
- RHOAI Operator: {version} on channel {channel}
- DataScienceCluster: {health}
- Dependent operators: {all healthy? list any issues}

## Upgrade Readiness: {READY | BLOCKED | CAUTION}

## Pre-Upgrade Checklist
- [x/!] cert-manager: {version} — {status}
- [x/!] servicemesh: {version} — {status}
- [x/!] nfd: {version} — {status}
- [x/!] gpu-operator: {version} — {status}
- [x/!] DSC health: {status}
- [x/!] Kueue queue empty: {yes/no}
- [x/!] Node pressure: {none/DiskPressure/etc.}

## Blocking Issues
{Issues that must be resolved before upgrade}

## Recommended Upgrade Steps
1. Verify Git branch contains desired channel in `components/operators/rhoai-operator/patch-channel.yaml`
2. Commit channel change: `fast` → `stable` (or version bump)
3. Push to Git — ArgoCD will detect the change
4. Monitor: operator-rhoai-operator sync status
5. Verify: DSC reconciliation after new CSV installs
6. Validate: All InferenceServices remain Ready

## Rollback Plan
1. Revert Git commit (restore previous patch-channel.yaml)
2. Push — ArgoCD syncs back to previous Subscription spec
3. OLM will NOT auto-downgrade — manual CSV deletion may be needed
4. If DSC is stuck: check operator logs in redhat-ods-operator namespace
```

## Safety Rules

- NEVER recommend upgrading if any dependency operator is Degraded
- NEVER recommend upgrading during active model serving (check Kueue workloads)
- Always recommend dry-run sync before real sync for operator apps
- If the cluster shows DiskPressure, resolve that FIRST before any upgrade
- Channel changes in disconnected environments require updated CatalogSource mirrors
