#!/usr/bin/env bash
# Seal all secrets for the RFP Agent platform.
#
# This is a LOCAL developer tool — it runs on your machine, not on the cluster.
# It encrypts plaintext secret values using the cluster's public certificate
# so they can be safely committed to git.
#
# Prerequisites:
#   - kubeseal CLI installed
#   - pub-cert.pem fetched from the target cluster (see bootstrap/README.md)
#   - You know the actual secret values to seal
#
# Usage:
#   ./seal-secrets.sh
#
# After running, commit the updated .yaml files in this directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT="${SCRIPT_DIR}/pub-cert.pem"

if [ ! -f "$CERT" ] || grep -q "PLACEHOLDER" "$CERT"; then
  echo "ERROR: pub-cert.pem not found or is still the placeholder."
  echo ""
  echo "Fetch your cluster's cert first:"
  echo "  kubeseal --fetch-cert \\"
  echo "    --controller-name=sealed-secrets-controller \\"
  echo "    --controller-namespace=sealed-secrets \\"
  echo "    > ${CERT}"
  exit 1
fi

echo "=== Sealing secrets using cert: ${CERT} ==="
echo ""

seal() {
  local name="$1"
  local namespace="$2"
  local output="$3"
  shift 3
  # Remaining args are --from-literal pairs
  echo "  Sealing: ${namespace}/${name} -> ${output}"
  oc create secret generic "$name" -n "$namespace" "$@" \
    --dry-run=client -o yaml | \
    kubeseal --cert "$CERT" --format yaml --scope strict \
    > "${SCRIPT_DIR}/${output}"
}

echo "Enter secret values (leave blank to skip):"
echo ""

# MinIO credentials
read -sp "  MinIO root password: " MINIO_PASS; echo
if [ -n "$MINIO_PASS" ]; then
  seal minio-credentials minio minio-credentials.yaml \
    --from-literal=root-user=minioadmin \
    --from-literal=root-password="$MINIO_PASS"
fi

# Milvus
read -sp "  Milvus root password: " MILVUS_PASS; echo
if [ -n "$MILVUS_PASS" ]; then
  seal milvus-secret milvus milvus-secret.yaml \
    --from-literal=root-password="$MILVUS_PASS"
fi

# Gemini API key (used by agent + eval)
read -sp "  Gemini API key: " GEMINI_KEY; echo
if [ -n "$GEMINI_KEY" ]; then
  # Agent auth
  read -sp "  Dashboard password: " DASH_PASS; echo
  read -sp "  API server key: " API_KEY; echo
  read -sp "  GitHub PAT (stale-image-finder + pr-review-bot): " GH_PAT; echo
  seal rfp-agent-auth rfp-agent rfp-agent-auth.yaml \
    --from-literal=llm-api-key="$GEMINI_KEY" \
    --from-literal=dashboard-password="$DASH_PASS" \
    --from-literal=api-server-key="$API_KEY"

  seal pod-health-watcher-auth pod-health-watcher pod-health-watcher-auth.yaml \
    --from-literal=llm-api-key="$GEMINI_KEY" \
    --from-literal=dashboard-password="$DASH_PASS" \
    --from-literal=api-server-key="$API_KEY"

  seal stale-image-finder-auth stale-image-finder stale-image-finder-auth.yaml \
    --from-literal=llm-api-key="$GEMINI_KEY" \
    --from-literal=dashboard-password="$DASH_PASS" \
    --from-literal=api-server-key="$API_KEY" \
    --from-literal=github-token="$GH_PAT"

  seal pr-review-bot-auth pr-review-bot pr-review-bot-auth.yaml \
    --from-literal=llm-api-key="$GEMINI_KEY" \
    --from-literal=dashboard-password="$DASH_PASS" \
    --from-literal=api-server-key="$API_KEY" \
    --from-literal=github-token="$GH_PAT"

  read -sp "  ArgoCD API token (rhoai-copilot, blank to skip): " ARGOCD_TOKEN; echo
  seal rhoai-copilot-auth rhoai-copilot rhoai-copilot-auth.yaml \
    --from-literal=llm-api-key="$GEMINI_KEY" \
    --from-literal=dashboard-password="$DASH_PASS" \
    --from-literal=api-server-key="$API_KEY" \
    --from-literal=github-token="$GH_PAT" \
    --from-literal=argocd-api-token="${ARGOCD_TOKEN:-unused}"

  # Git clone token (ingest + eval Jobs need to clone this private repo)
  seal git-clone-github rfp-agent git-clone-github.yaml \
    --from-literal=token="$GH_PAT"

  seal git-clone-github rfp-agent-eval eval-git-clone-github.yaml \
    --from-literal=token="$GH_PAT"

  # Eval key
  seal eval-gemini-key rfp-agent-eval eval-gemini-key.yaml \
    --from-literal=OPENAI_API_KEY="$GEMINI_KEY"

  read -sp "  Open WebUI secret key (blank to skip): " WEBUI_SECRET; echo
  if [ -n "$WEBUI_SECRET" ]; then
    seal open-webui-providers open-webui open-webui-providers.yaml \
      --from-literal=WEBUI_SECRET_KEY="$WEBUI_SECRET" \
      --from-literal=OPENAI_API_KEYS="${API_KEY}"
  fi
fi

# DSPA MinIO creds (same as MinIO but in rfp-agent namespace)
if [ -n "$MINIO_PASS" ]; then
  seal dspa-minio-creds rfp-agent dspa-minio-creds.yaml \
    --from-literal=root-user=minioadmin \
    --from-literal=root-password="$MINIO_PASS"

  seal dspa-db-password rfp-agent dspa-db-password.yaml \
    --from-literal=password="dspadb$(date +%Y)"
fi

# OGX + S3 connections
if [ -n "$MINIO_PASS" ]; then
  seal rfp-ogx-connection rfp-agent rfp-ogx-connection.yaml \
    --from-literal=OGX_BASE_URL=http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321 \
    --from-literal=OGX_API_KEY=unused \
    --from-literal=OGX_CLIENT_BASE_URL=http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321 \
    --from-literal=OGX_CLIENT_API_KEY=unused

  seal rfp-s3-connection rfp-agent rfp-s3-connection.yaml \
    --from-literal=AWS_ACCESS_KEY_ID=minioadmin \
    --from-literal=AWS_SECRET_ACCESS_KEY="$MINIO_PASS" \
    --from-literal=AWS_S3_ENDPOINT=http://minio.minio.svc.cluster.local:9000 \
    --from-literal=AWS_S3_BUCKET=rfp-agent-knowledge \
    --from-literal=AWS_DEFAULT_REGION=us-east-1

  seal autorag-s3-connection rfp-agent autorag-s3-connection.yaml \
    --from-literal=AWS_ACCESS_KEY_ID=minioadmin \
    --from-literal=AWS_SECRET_ACCESS_KEY="$MINIO_PASS" \
    --from-literal=AWS_S3_ENDPOINT=http://minio.minio.svc.cluster.local:9000 \
    --from-literal=AWS_S3_BUCKET=rfp-agent-knowledge \
    --from-literal=AWS_DEFAULT_REGION=us-east-1
fi

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  git add platform/gitops/secrets/"
echo "  git commit -m 'chore: seal secrets for cluster'"
echo "  git push"
echo "  oc apply -f platform/gitops/apps/app-of-apps.yaml"
