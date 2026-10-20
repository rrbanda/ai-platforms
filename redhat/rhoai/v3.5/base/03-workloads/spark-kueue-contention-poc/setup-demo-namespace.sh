#!/bin/bash
# ============================================================================
# Kueue + Spark Operator POC — Namespace Setup for Non-Admin Users
# ============================================================================
#
# This script creates everything needed so a non-admin user can run
# all 5 POC test cases without cluster-admin access.
#
# Prerequisites:
#   - Logged in as cluster-admin: oc whoami → admin or kubeadmin
#   - Spark Operator installed (sparkapplications.sparkoperator.k8s.io CRD exists)
#   - Kueue Operator installed with SparkApplicationIntegration enabled
#
# Usage:
#   ./setup-demo-namespace.sh <namespace> <username>
#
# Example:
#   ./setup-demo-namespace.sh spark-kueue-demo user1
# ============================================================================

set -euo pipefail

NAMESPACE="${1:?Usage: $0 <namespace> <username>}"
USERNAME="${2:?Usage: $0 <namespace> <username>}"

echo "=== Kueue + Spark POC — Namespace Setup ==="
echo "Namespace: ${NAMESPACE}"
echo "User:      ${USERNAME}"
echo ""

# --------------------------------------------------------
# 1. Create namespace
# --------------------------------------------------------
echo "[1/6] Creating namespace ${NAMESPACE}..."
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

# --------------------------------------------------------
# 2. ResourceFlavor (cluster-scoped, idempotent)
# --------------------------------------------------------
echo "[2/6] Creating ResourceFlavor..."
cat <<'EOF' | oc apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: default-flavor
EOF

# --------------------------------------------------------
# 3. ClusterQueue with constrained quota (cluster-scoped)
#    Two queues: 8 CPU (default) and 6 CPU (for TC-4 queuing test)
# --------------------------------------------------------
echo "[3/6] Creating ClusterQueues..."
cat <<EOF | oc apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: spark-cq
spec:
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - ${NAMESPACE}
  resourceGroups:
  - coveredResources:
    - cpu
    - memory
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: "8"
      - name: memory
        nominalQuota: "32Gi"
EOF

cat <<EOF | oc apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: spark-cq-6cpu
spec:
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - ${NAMESPACE}
  resourceGroups:
  - coveredResources:
    - cpu
    - memory
    flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: "6"
      - name: memory
        nominalQuota: "32Gi"
EOF

# --------------------------------------------------------
# 4. LocalQueues (namespace-scoped)
# --------------------------------------------------------
echo "[4/6] Creating LocalQueues in ${NAMESPACE}..."
cat <<EOF | oc apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: spark-lq
  namespace: ${NAMESPACE}
spec:
  clusterQueue: spark-cq
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: spark-lq-6cpu
  namespace: ${NAMESPACE}
spec:
  clusterQueue: spark-cq-6cpu
EOF

# --------------------------------------------------------
# 5. RBAC — Grant user namespace admin + ClusterQueue viewer
# --------------------------------------------------------
echo "[5/6] Granting RBAC to ${USERNAME}..."

# Namespace admin — full control over SparkApplications, pods, events, LocalQueues
oc create rolebinding spark-demo-admin \
  --clusterrole=admin \
  --user="${USERNAME}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | oc apply -f -

# ClusterQueue viewer — read-only access to see queue status
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kueue-cq-viewer
rules:
- apiGroups: ["kueue.x-k8s.io"]
  resources: ["clusterqueues", "resourceflavors"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spark-demo-cq-viewer-${USERNAME}
subjects:
- kind: User
  name: ${USERNAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: kueue-cq-viewer
  apiGroup: rbac.authorization.k8s.io
EOF

# --------------------------------------------------------
# 6. Verify
# --------------------------------------------------------
echo "[6/6] Verifying setup..."
echo ""
echo "Namespace:"
oc get namespace "${NAMESPACE}" --no-headers
echo ""
echo "ClusterQueues:"
oc get clusterqueue spark-cq spark-cq-6cpu --no-headers
echo ""
echo "LocalQueues:"
oc get localqueue -n "${NAMESPACE}" --no-headers
echo ""
echo "RBAC:"
oc get rolebinding -n "${NAMESPACE}" --no-headers | grep spark-demo
oc get clusterrolebinding --no-headers | grep "spark-demo-cq-viewer-${USERNAME}"

echo ""
echo "============================================"
echo "Setup complete."
echo ""
echo "The user ${USERNAME} can now run:"
echo ""
echo "  oc login -u ${USERNAME}"
echo "  oc project ${NAMESPACE}"
echo ""
echo "  # TC-1: Half-admitted state (no Kueue)"
echo "  oc apply -f tc1-baseline-no-kueue.yaml"
echo ""
echo "  # TC-2: Kueue blocks it (uses spark-lq → spark-cq, 8 CPU)"
echo "  oc apply -f tc2-kueue-admission-blocking.yaml"
echo ""
echo "  # TC-4: Auto queue/release (uses spark-lq-6cpu → spark-cq-6cpu, 6 CPU)"
echo "  #   Update tc4a/tc4b YAML label to: spark-lq-6cpu"
echo "  oc apply -f tc4a-large-job.yaml"
echo "  oc apply -f tc4b-queued-job.yaml"
echo ""
echo "  # TC-5: Dynamic allocation rejection"
echo "  oc apply -f tc5-dynamic-allocation.yaml"
echo ""
echo "  # TC-7: Executor failure recovery"
echo "  oc apply -f tc7-executor-failure.yaml"
echo ""
echo "No cluster-admin required for any of the above."
echo "============================================"
