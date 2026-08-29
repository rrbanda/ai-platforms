#!/usr/bin/env bash
set -euo pipefail

# Onboard a spoke cluster for RHOAI deployment.
#
# Usage:
#   ./rhoai/scripts/spoke-onboard.sh <cluster-name> [labels...]
#
# Examples:
#   ./rhoai/scripts/spoke-onboard.sh spoke-gpu-01 rhoai.io/gpu=true
#   ./rhoai/scripts/spoke-onboard.sh spoke-rag-01 rhoai.io/rag=true rhoai.io/gpu=true
#   ./rhoai/scripts/spoke-onboard.sh spoke-train-01 rhoai.io/training=true
#
# Prerequisites:
#   - oc CLI logged in to the HUB cluster
#   - Cluster already imported into RHACM as a ManagedCluster
#   - Hub spoke-management applied: oc apply -k rhoai/clusters/hubs/primary/

CLUSTER_NAME="${1:?Usage: spoke-onboard.sh <cluster-name> [labels...]}"
shift
EXTRA_LABELS=("$@")

echo "=== RHOAI Spoke Onboarding: ${CLUSTER_NAME} ==="
echo ""

if ! oc get managedcluster "${CLUSTER_NAME}" &>/dev/null; then
  echo "ERROR: ManagedCluster '${CLUSTER_NAME}' not found."
  echo "Import the cluster into RHACM first."
  exit 1
fi

echo "Step 1: Applying base label rhoai.io/platform=true..."
oc label managedcluster "${CLUSTER_NAME}" rhoai.io/platform=true --overwrite

for label in "${EXTRA_LABELS[@]}"; do
  echo "  Adding label: ${label}"
  oc label managedcluster "${CLUSTER_NAME}" "${label}" --overwrite
done
echo ""

echo "Step 2: Verifying labels..."
oc get managedcluster "${CLUSTER_NAME}" -o jsonpath='{range .metadata.labels}{@}{"\n"}{end}' | grep rhoai
echo ""

echo "Step 3: Checking RHACM Policy compliance..."
sleep 10
echo "  GitOps operator policy:"
oc get policy spoke-install-gitops -n "${CLUSTER_NAME}" -o jsonpath='{.status.compliant}' 2>/dev/null || echo "  (pending)"
echo ""
echo "  SealedSecrets policy:"
oc get policy spoke-install-sealed-secrets -n "${CLUSTER_NAME}" -o jsonpath='{.status.compliant}' 2>/dev/null || echo "  (pending)"
echo ""

echo "Step 4: Waiting for ApplicationSet to generate Application..."
sleep 15
echo "  Looking for Application '${CLUSTER_NAME}-rhoai-platform'..."
oc get application.argoproj.io "${CLUSTER_NAME}-rhoai-platform" -n openshift-gitops 2>/dev/null && echo "  Found!" || echo "  (not yet created -- Pull Model propagation may take 1-3 min)"
echo ""

echo "=========================================="
echo "  Spoke '${CLUSTER_NAME}' onboarding initiated!"
echo "=========================================="
echo ""
echo "The RHACM Pull Model will now:"
echo "  1. Install GitOps + SealedSecrets operators on the spoke (via Policy)"
echo "  2. Deliver ArgoCD Applications to the spoke (via ManifestWork)"
echo "  3. Spoke's local ArgoCD will pull from Git and deploy RHOAI"
echo ""
echo "Monitor progress:"
echo "  oc get policy -n ${CLUSTER_NAME}"
echo "  oc get application.argoproj.io -n openshift-gitops | grep ${CLUSTER_NAME}"
echo ""
echo "To re-seal secrets for this spoke:"
echo "  1. oc login to the SPOKE cluster"
echo "  2. ./rhoai/scripts/reseal-all.sh"
echo "  3. git add, commit, push"
