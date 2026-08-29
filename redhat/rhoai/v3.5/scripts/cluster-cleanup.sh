#!/usr/bin/env bash
set -euo pipefail

# Pre-deployment cleanup for shared/reused clusters.
#
# Detects and removes stale RHOAI CRs left by previous tenants that
# block fresh GitOps deployments. Run this BEFORE deploying RHOAI.
#
# Usage:
#   ./redhat/rhoai/v3.5/scripts/cluster-cleanup.sh
#
# Safe to run on a clean cluster (no-ops if nothing stale found).

echo "=== RHOAI Pre-deployment Cleanup ==="
echo ""

STALE_FOUND=0

check_stale() {
  local resource="$1"
  local items
  items=$(oc get "$resource" -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\t"}{.metadata.deletionTimestamp}{"\n"}{end}' 2>/dev/null | grep -v "^$" || true)

  if [ -n "$items" ]; then
    while IFS=$'\t' read -r name ns deletion; do
      if [ -n "$deletion" ]; then
        echo "  STALE: $resource/$name (ns=$ns) -- stuck deleting since $deletion"
        echo "    Fix: oc patch $resource $name ${ns:+-n $ns} --type merge -p '{\"metadata\":{\"finalizers\":null}}'"
        STALE_FOUND=1
      fi
    done <<< "$items"
  fi
}

echo "Checking for stale RHOAI CRs..."
echo ""

for cr in \
  kueue.kueue.openshift.io \
  kserve.components.platform.opendatahub.io \
  trustyai.components.platform.opendatahub.io \
  datasciencecluster.datasciencecluster.opendatahub.io \
  multiclusterengine.multicluster.openshift.io \
  multiclusterhub.operator.open-cluster-management.io; do
  check_stale "$cr" 2>/dev/null
done

echo ""
echo "Checking for terminating namespaces..."
TERM_NS=$(oc get ns --no-headers 2>/dev/null | grep Terminating | awk '{print $1}')
if [ -n "$TERM_NS" ]; then
  for ns in $TERM_NS; do
    echo "  STUCK: namespace/$ns is Terminating"
    echo "    Fix: oc get namespace $ns -o json | python3 -c \"import json,sys; ns=json.load(sys.stdin); ns['spec']['finalizers']=[]; json.dump(ns,sys.stdout)\" | oc replace --raw '/api/v1/namespaces/$ns/finalize' -f -"
    STALE_FOUND=1
  done
fi

echo ""
echo "Checking for stale external.metrics API service..."
STALE_API=$(oc get apiservice v1beta1.external.metrics.k8s.io -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || true)
if [ "$STALE_API" = "ServiceNotFound" ]; then
  echo "  STALE: apiservice/v1beta1.external.metrics.k8s.io -- service not found"
  echo "    Fix: oc delete apiservice v1beta1.external.metrics.k8s.io"
  STALE_FOUND=1
fi

echo ""
if [ "$STALE_FOUND" -eq 0 ]; then
  echo "Cluster is clean -- no stale resources found."
else
  echo "Stale resources found. Run the suggested fix commands above,"
  echo "or re-run this script with --fix to auto-remediate:"
  echo ""
  if [ "${1:-}" = "--fix" ]; then
    echo "Auto-fix mode enabled..."
    for cr in kueue.kueue.openshift.io kserve.components.platform.opendatahub.io trustyai.components.platform.opendatahub.io; do
      for item in $(oc get "$cr" -A -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
        echo "  Removing finalizer from $cr/$item"
        oc patch "$cr" "$item" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null
      done
    done
    for ns in $TERM_NS; do
      echo "  Finalizing namespace/$ns"
      oc get namespace "$ns" -o json 2>/dev/null | python3 -c "import json,sys; ns=json.load(sys.stdin); ns['spec']['finalizers']=[]; json.dump(ns,sys.stdout)" | oc replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null
    done
    if [ "$STALE_API" = "ServiceNotFound" ]; then
      echo "  Deleting stale apiservice"
      oc delete apiservice v1beta1.external.metrics.k8s.io 2>/dev/null
    fi
    echo "Done. Re-run without --fix to verify."
  fi
fi
