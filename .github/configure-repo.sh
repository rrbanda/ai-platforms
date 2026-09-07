#!/usr/bin/env bash
# Configure GitHub repo settings for CI/CD.
# Run once after creating the repo or when settings drift.
#
# Prerequisites: gh CLI authenticated (gh auth login)
#
# Usage: ./configure-repo.sh
set -euo pipefail

REPO="${REPO:-rrbanda/ai-demos}"

echo "=== Configuring GitHub repo: ${REPO} ==="
echo ""

# 1. Set Actions workflow permissions to read-write (needed for packages:write)
echo "[1/4] Setting Actions workflow permissions to read-write..."
gh api "repos/${REPO}/actions/permissions/workflow" \
  --method PUT \
  -f default_workflow_permissions=write \
  -F can_approve_pull_request_reviews=true \
  2>&1 && echo "  Done." || echo "  WARNING: Failed (may need admin access)"

echo ""

# 2. Enable Actions for the repo (if disabled)
echo "[2/4] Enabling Actions..."
gh api "repos/${REPO}/actions/permissions" \
  --method PUT \
  -f enabled=true \
  -f allowed_actions=all \
  2>&1 && echo "  Done." || echo "  WARNING: Failed"

echo ""

# 3. Set hermes-runtime package visibility to public
echo "[3/4] Setting hermes-runtime package to public..."
gh api "users/${REPO%%/*}/packages/container/hermes-runtime" \
  --method PATCH \
  -f visibility=public \
  2>&1 && echo "  Done." || echo "  NOTE: Package doesn't exist yet. Run again after first runtime build."

echo ""

# 4. Set rfp-agent package visibility to public
echo "[4/4] Setting rfp-agent package to public..."
gh api "users/${REPO%%/*}/packages/container/rfp-agent" \
  --method PATCH \
  -f visibility=public \
  2>&1 && echo "  Done." || echo "  NOTE: Package doesn't exist yet. Run again after first agent build."

echo ""
echo "=== Configuration complete ==="
echo ""
echo "Images (after first build):"
echo "  Layer 1: ghcr.io/${REPO%%/*}/hermes-runtime:<version>"
echo "  Layer 2: ghcr.io/${REPO%%/*}/rfp-agent:latest"
echo ""
echo "Next steps:"
echo "  1. Push to main to trigger the first CI builds"
echo "  2. After first push, re-run this script to set package visibility"
echo "  3. Verify at: https://github.com/${REPO}/actions"
