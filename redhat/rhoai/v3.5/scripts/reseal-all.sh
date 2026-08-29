#!/usr/bin/env bash
set -euo pipefail

# Re-seal all SealedSecrets for a new cluster.
#
# Usage:
#   ./rhoai/scripts/reseal-all.sh
#
# Prerequisites:
#   - oc CLI logged in to the target cluster
#   - kubeseal CLI installed (brew install kubeseal)
#   - Sealed Secrets controller running in sealed-secrets namespace
#
# The script reads plaintext templates, prompts for values (or reads
# from environment variables), seals them with the target cluster's
# certificate, and writes the sealed files to the correct directories.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AUTORAG_DIR="${REPO_ROOT}/redhat/rhoai/v3.5/base/03-workloads/autorag"
CLUSTER_DIR="${REPO_ROOT}/redhat/rhoai/v3.5/base/02-config"

CONTROLLER_NS="${SEALED_SECRETS_NS:-sealed-secrets}"
CERT_FILE="$(mktemp)"
trap 'rm -f "${CERT_FILE}" /tmp/reseal-*.yaml' EXIT

echo "=== RHOAI GitOps -- Re-seal All Secrets ==="
echo ""

if ! command -v kubeseal &>/dev/null; then
  echo "ERROR: kubeseal not found. Install: brew install kubeseal"
  exit 1
fi

if ! command -v oc &>/dev/null; then
  echo "ERROR: oc not found. Install the OpenShift CLI."
  exit 1
fi

echo "Fetching sealing certificate from controller in namespace '${CONTROLLER_NS}'..."
kubeseal --fetch-cert --controller-namespace "${CONTROLLER_NS}" > "${CERT_FILE}"
echo "Certificate fetched."
echo ""

seal_secret() {
  local template_file="$1"
  local output_file="$2"
  local tmp_file="/tmp/reseal-$(basename "${template_file}" .template)"

  cp "${template_file}" "${tmp_file}"

  echo "--- Sealing: $(basename "${output_file}") ---"
  echo "  Template: ${template_file}"
  echo "  Edit ${tmp_file} with your values, then press ENTER to seal."
  echo "  (Or set env vars before running this script to skip prompts.)"

  # Auto-fill from env vars where possible
  if [[ -n "${LLM_API_KEY:-}" ]] && grep -q 'REPLACE_WITH_LLM_API_KEY' "${tmp_file}"; then
    sed -i.bak "s|REPLACE_WITH_LLM_API_KEY|${LLM_API_KEY}|g" "${tmp_file}"
    echo "  -> Auto-filled LLM_API_KEY from environment"
  fi
  if [[ -n "${S3_ACCESS_KEY:-}" ]] && grep -q 'REPLACE_WITH_ACCESS_KEY' "${tmp_file}"; then
    sed -i.bak "s|REPLACE_WITH_ACCESS_KEY|${S3_ACCESS_KEY}|g" "${tmp_file}"
    sed -i.bak "s|REPLACE_WITH_SECRET_KEY|${S3_SECRET_KEY:-changeme}|g" "${tmp_file}"
    sed -i.bak "s|REPLACE_WITH_BUCKET_NAME|${S3_BUCKET:-autorag}|g" "${tmp_file}"
    sed -i.bak "s|REPLACE_WITH_S3_ENDPOINT|${S3_ENDPOINT:-https://s3.amazonaws.com}|g" "${tmp_file}"
    echo "  -> Auto-filled S3 credentials from environment"
  fi
  if [[ -n "${MAAS_DB_PASSWORD:-}" ]] && grep -q 'REPLACE_WITH_DB_PASSWORD' "${tmp_file}"; then
    sed -i.bak "s|REPLACE_WITH_DB_PASSWORD|${MAAS_DB_PASSWORD}|g" "${tmp_file}"
    echo "  -> Auto-filled MAAS_DB_PASSWORD from environment"
  fi

  if grep -q 'REPLACE_WITH_' "${tmp_file}"; then
    echo ""
    echo "  WARNING: Unfilled placeholders remain in ${tmp_file}:"
    grep 'REPLACE_WITH_' "${tmp_file}" | sed 's/^/    /'
    echo ""
    read -rp "  Edit the file and press ENTER to continue (or Ctrl-C to abort): "
  fi

  kubeseal --format yaml --cert "${CERT_FILE}" < "${tmp_file}" > "${output_file}"
  echo "  -> Sealed to ${output_file}"
  echo ""
  rm -f "${tmp_file}" "${tmp_file}.bak"
}

echo "=========================================="
echo "  Sealing autorag secrets (2 of 4)"
echo "=========================================="
seal_secret \
  "${AUTORAG_DIR}/templates/llm-api-secret.yaml.template" \
  "${AUTORAG_DIR}/sealed-llm-api-secret.yaml"

seal_secret \
  "${AUTORAG_DIR}/templates/s3-connection-secret.yaml.template" \
  "${AUTORAG_DIR}/sealed-s3-connection-secret.yaml"

echo "=========================================="
echo "  Sealing cluster-config secrets (2 of 4)"
echo "=========================================="
seal_secret \
  "${CLUSTER_DIR}/templates/maas-postgres-credentials.yaml.template" \
  "${CLUSTER_DIR}/sealed-maas-postgres-credentials.yaml"

seal_secret \
  "${CLUSTER_DIR}/templates/maas-db-config.yaml.template" \
  "${CLUSTER_DIR}/sealed-maas-db-config.yaml"

echo "=========================================="
echo "  All 4 secrets sealed successfully!"
echo "=========================================="
echo ""

if [[ -f "${CLUSTER_DIR}/templates/maas-oidc-config.yaml.template" ]]; then
  echo "=========================================="
  echo "  Optional: MaaS OIDC (requires external IdP)"
  echo "=========================================="
  echo ""
  read -rp "  Configure MaaS OIDC? (y/N): " CONFIGURE_OIDC
  if [[ "${CONFIGURE_OIDC}" =~ ^[Yy]$ ]]; then
    seal_secret \
      "${CLUSTER_DIR}/templates/maas-oidc-config.yaml.template" \
      "${CLUSTER_DIR}/sealed-maas-oidc-config.yaml"
    echo "  NOTE: The sealed OIDC config contains the GatewayConfig patch."
    echo "  After applying, the MaaS gateway will require OIDC tokens."
    echo ""
    echo "  You may also want to create MaaSSubscription and MaaSAuthPolicy"
    echo "  resources. See templates in:"
    echo "    ${CLUSTER_DIR}/templates/maas-subscription.yaml.template"
    echo "    ${CLUSTER_DIR}/templates/maas-auth-policy.yaml.template"
    echo ""
  else
    echo "  Skipped OIDC configuration."
    echo ""
  fi
fi

echo "Next steps:"
echo "  1. git add rhoai/base/*/sealed-*.yaml rhoai/base/**/sealed-*.yaml"
echo "  2. git commit -m 'Re-seal secrets for new cluster'"
echo "  3. git push"
echo ""
echo "Note: SealedSecrets are cluster-specific. If you deploy to"
echo "another cluster, run this script again with that cluster's cert."
