#!/usr/bin/env bash
set -euo pipefail

# Configure a cluster to use its per-cluster overlay for secrets.
#
# Usage:
#   ./redhat/rhoai/v3.5/scripts/cluster-setup.sh <cluster-name>
#
# This script:
#   1. Creates the overlay directory if it doesn't exist
#   2. Re-seals secrets with this cluster's Sealed Secrets cert
#   3. Patches ArgoCD Applications to use the overlay paths
#   4. Commits and pushes the sealed secrets
#
# Prerequisites:
#   - oc CLI logged in to the target cluster
#   - kubeseal CLI installed
#   - Sealed Secrets controller running
#   - Git repo cloned and on main branch

CLUSTER_NAME="${1:?Usage: cluster-setup.sh <cluster-name>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RHOAI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY_DIR="${RHOAI_DIR}/overlays/${CLUSTER_NAME}"

echo "=== RHOAI Cluster Setup: ${CLUSTER_NAME} ==="
echo ""

# Step 1: Create overlay directory
if [ ! -d "${OVERLAY_DIR}/config" ]; then
  echo "Step 1: Creating overlay directory..."
  mkdir -p "${OVERLAY_DIR}/config" "${OVERLAY_DIR}/workloads"

  cat > "${OVERLAY_DIR}/config/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/02-config
  - sealed-maas-postgres-credentials.yaml
  - sealed-maas-db-config.yaml
EOF

  cat > "${OVERLAY_DIR}/workloads/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/03-workloads/autorag
  - sealed-llm-api-secret.yaml
  - sealed-s3-connection-secret.yaml
EOF
  echo "  Created ${OVERLAY_DIR}/"
else
  echo "Step 1: Overlay directory already exists."
fi
echo ""

# Step 2: Seal secrets
echo "Step 2: Sealing secrets for ${CLUSTER_NAME}..."
CERT_FILE="$(mktemp)"
trap 'rm -f "${CERT_FILE}"' EXIT

CONTROLLER_NS="${SEALED_SECRETS_NS:-sealed-secrets}"
kubeseal --fetch-cert --controller-namespace "${CONTROLLER_NS}" > "${CERT_FILE}"

seal_template() {
  local template="$1" output="$2" tmp="/tmp/reseal-$(basename "$template" .template)"
  cp "$template" "$tmp"

  if [[ -n "${LLM_API_KEY:-}" ]]; then sed -i.bak "s|REPLACE_WITH_LLM_API_KEY|${LLM_API_KEY}|g" "$tmp"; fi
  if [[ -n "${S3_ACCESS_KEY:-}" ]]; then
    sed -i.bak "s|REPLACE_WITH_ACCESS_KEY|${S3_ACCESS_KEY}|g" "$tmp"
    sed -i.bak "s|REPLACE_WITH_SECRET_KEY|${S3_SECRET_KEY:-changeme}|g" "$tmp"
    sed -i.bak "s|REPLACE_WITH_BUCKET_NAME|${S3_BUCKET:-autorag}|g" "$tmp"
    sed -i.bak "s|REPLACE_WITH_S3_ENDPOINT|${S3_ENDPOINT:-https://s3.amazonaws.com}|g" "$tmp"
  fi
  if [[ -n "${MAAS_DB_PASSWORD:-}" ]]; then sed -i.bak "s|REPLACE_WITH_DB_PASSWORD|${MAAS_DB_PASSWORD}|g" "$tmp"; fi

  if grep -q 'REPLACE_WITH_' "$tmp"; then
    echo "  WARNING: Unfilled placeholders in $template"
    grep 'REPLACE_WITH_' "$tmp" | sed 's/^/    /'
    read -rp "  Edit $tmp and press ENTER: "
  fi

  kubeseal --format yaml --cert "${CERT_FILE}" < "$tmp" > "$output"
  rm -f "$tmp" "$tmp.bak"
  echo "  Sealed: $(basename "$output")"
}

seal_template "${RHOAI_DIR}/base/03-workloads/autorag/templates/llm-api-secret.yaml.template" \
  "${OVERLAY_DIR}/workloads/sealed-llm-api-secret.yaml"
seal_template "${RHOAI_DIR}/base/03-workloads/autorag/templates/s3-connection-secret.yaml.template" \
  "${OVERLAY_DIR}/workloads/sealed-s3-connection-secret.yaml"
seal_template "${RHOAI_DIR}/base/02-config/templates/maas-postgres-credentials.yaml.template" \
  "${OVERLAY_DIR}/config/sealed-maas-postgres-credentials.yaml"
seal_template "${RHOAI_DIR}/base/02-config/templates/maas-db-config.yaml.template" \
  "${OVERLAY_DIR}/config/sealed-maas-db-config.yaml"
echo ""

# Step 3: Patch ArgoCD Applications to use overlay paths
echo "Step 3: Patching ArgoCD Applications to use overlay..."
OVERLAY_CONFIG_PATH="redhat/rhoai/v3.5/overlays/${CLUSTER_NAME}/config"
OVERLAY_WORKLOADS_PATH="redhat/rhoai/v3.5/overlays/${CLUSTER_NAME}/workloads"

oc patch application.argoproj.io rhoai-cluster-config -n openshift-gitops \
  --type merge -p "{\"spec\":{\"source\":{\"path\":\"${OVERLAY_CONFIG_PATH}\"}}}" 2>&1
oc patch application.argoproj.io autorag-workload -n openshift-gitops \
  --type merge -p "{\"spec\":{\"source\":{\"path\":\"${OVERLAY_WORKLOADS_PATH}\"}}}" 2>&1
echo ""

echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. git add redhat/rhoai/v3.5/overlays/${CLUSTER_NAME}/"
echo "  2. git commit -m 'Add overlay for ${CLUSTER_NAME}'"
echo "  3. git push"
echo "  4. Sync ArgoCD apps (or wait for auto-refresh)"
