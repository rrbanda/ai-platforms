---
name: rhoai-uninstall
description: "Cleanly uninstall Red Hat OpenShift AI and its dependency operators in the correct reverse order, verifying nothing remains."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Uninstall, Cleanup, Operators]
---

# RHOAI Uninstall

Cleanly remove Red Hat OpenShift AI and its dependency operators from an OpenShift cluster. Operates in reverse installation order to avoid orphaned resources.

## Trigger Conditions

- "Uninstall RHOAI"
- "Remove OpenShift AI from my cluster"
- "Clean uninstall of RHOAI"
- "Delete all RHOAI components"
- "I want to reinstall RHOAI from scratch"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_openshift | resources_list | List Subscriptions, CSVs, namespaces, CRDs |
| mcp_rhoai | cluster_summary | Check current RHOAI state |

## Procedure

**Order matters. Uninstall is the REVERSE of install.**

**Idempotent:** This procedure is safe to run even if RHOAI is already uninstalled or partially removed. Every command handles "not found" gracefully.

**NotReady DSC is normal:** If the DSC shows `NotReady` (commonly due to `trainer` defaulting to Managed without JobSet), the delete still works. Do not try to fix the DSC before deleting it.

### Step 1: Delete the DataScienceCluster

The RHOAI operator watches the DSC and removes its operands (pods, services, routes) when the DSC is deleted. Let it do its job before removing the operator.

```bash
oc delete datasciencecluster --all --timeout=10m 2>/dev/null || echo "No DataScienceCluster found (already clean)"
```

Verify operands are draining:

```bash
oc get pods -n redhat-ods-applications -w 2>/dev/null
# Wait until pod count drops to near zero
```

### Step 2: Delete the DSCInitialization

```bash
oc delete dscinitialization --all --timeout=5m 2>/dev/null || echo "No DSCInitialization found (already clean)"
```

### Step 3: Delete the RHOAI operator

```bash
# Delete the Subscription (stops OLM from reinstalling)
oc delete subscription rhods-operator -n redhat-ods-operator

# Delete all RHOAI CSVs
oc delete csv -n redhat-ods-operator --all

# Delete the OperatorGroup
oc delete operatorgroup -n redhat-ods-operator --all
```

### Step 4: Delete dependency operators (reverse order)

Only delete operators that were installed FOR RHOAI. Do NOT delete shared operators used by other workloads.

```bash
# ServiceMesh 3 (if installed for RHOAI)
oc delete subscription servicemeshoperator3 -n openshift-operators 2>/dev/null
oc delete csv -n openshift-operators -l operators.coreos.com/servicemeshoperator3.openshift-operators 2>/dev/null

# NFD (if installed)
oc delete subscription nfd -n openshift-nfd 2>/dev/null
oc delete csv -n openshift-nfd --all 2>/dev/null
oc delete nodefeaturediscovery --all -n openshift-nfd 2>/dev/null

# GPU operator (if installed)
oc delete subscription gpu-operator-certified -n nvidia-gpu-operator 2>/dev/null
oc delete csv -n nvidia-gpu-operator --all 2>/dev/null

# cert-manager (if installed for RHOAI)
oc delete subscription openshift-cert-manager-operator -n cert-manager-operator 2>/dev/null
oc delete csv -n cert-manager-operator --all 2>/dev/null
```

### Step 5: Clean up namespaces

Delete only the RHOAI-specific namespaces. NEVER delete shared namespaces like openshift-operators.

**Note:** Namespace deletion takes 30-60 seconds per namespace as Kubernetes runs finalizers. This is normal.

```bash
for ns in redhat-ods-operator redhat-ods-applications redhat-ods-monitoring \
          rhods-notebooks rhoai-model-registries \
          cert-manager-operator openshift-nfd nvidia-gpu-operator; do
  oc delete namespace "$ns" --timeout=2m 2>/dev/null && echo "Deleted namespace $ns" || echo "Namespace $ns not found (already clean)"
done
```

### Step 6: Clean up CRDs (optional)

**CRDs persisting after uninstall is expected and harmless.** The RHOAI operator creates ~38 CRDs during installation. After uninstalling the operator, the CRDs remain registered but have no instances. If you reinstall RHOAI, the new operator adopts the existing CRDs.

Only delete CRDs if you want a completely clean slate and will NOT reinstall:

```bash
oc get crd | grep -E 'opendatahub|datasciencecluster|dscinitialization|trustyai|kserve' | awk '{print $1}' | xargs -r oc delete crd
```

### Step 7: Verify clean state

```bash
echo "=== Remaining CSVs ===" 
oc get csv -A 2>/dev/null | grep -iE 'rhods|cert-manager|servicemesh|nfd|gpu' || echo "CLEAN: No RHOAI-related CSVs"

echo "=== Remaining Subscriptions ==="
oc get sub -A 2>/dev/null | grep -iE 'rhods|cert-manager|servicemesh|nfd|gpu' || echo "CLEAN: No RHOAI-related subscriptions"

echo "=== Remaining DSC/DSCI ==="
oc get datasciencecluster -A 2>/dev/null || echo "CLEAN: No DataScienceCluster"
oc get dscinitialization -A 2>/dev/null || echo "CLEAN: No DSCInitialization"

echo "=== Remaining namespaces ==="
oc get ns | grep -iE 'redhat-ods|cert-manager-operator|openshift-nfd|nvidia-gpu' || echo "CLEAN: No RHOAI namespaces"

echo "=== ImagePullBackOff check ==="
oc get pods -A -o json | jq '[.items[].status.containerStatuses[]? | select(.state.waiting.reason=="ImagePullBackOff")] | length'
```

## Output Format

```
# RHOAI Uninstall Report

## Components Removed
- DataScienceCluster: {deleted / not found}
- DSCInitialization: {deleted / not found}
- RHOAI Operator: {deleted / not found}
- ServiceMesh 3: {deleted / skipped}
- cert-manager: {deleted / skipped}
- NFD: {deleted / skipped}
- GPU Operator: {deleted / skipped}

## Namespaces Removed
{list}

## Verification
- RHOAI CSVs remaining: {count}
- RHOAI Subscriptions remaining: {count}
- DSC/DSCI remaining: {count}
- RHOAI namespaces remaining: {count}

## Status: {CLEAN / PARTIAL — details}
```

## Safety Constraints

- **Never delete openshift-operators namespace** — it is shared by all operators
- **Never delete openshift-marketplace namespace** — it hosts CatalogSources
- **Never delete namespaces that contain non-RHOAI workloads** — check first
- **Always delete the DSC BEFORE the operator** — the operator removes operands when DSC is deleted
- **Always confirm with the user** before deleting CRDs (Step 6) — this is irreversible
- **Tier 2 operation** — requires human confirmation at each destructive step

## Disconnected Environment Notes

The uninstall procedure is the same for connected and disconnected environments. No mirroring or registry changes needed.

## Related Skills

- [`rhoai-connected-deploy`](../rhoai-connected-deploy/) — Reinstall after uninstall
- [`rhoai-disconnected-deploy`](../rhoai-disconnected-deploy/) — Reinstall in disconnected environments
- [`rhoai-install-validator`](../rhoai-install-validator/) — Verify clean state after uninstall
