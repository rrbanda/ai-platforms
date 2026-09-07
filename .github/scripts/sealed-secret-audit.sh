#!/usr/bin/env bash
# Audit SealedSecrets for correct format and detect plaintext secrets.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0

echo "=== SealedSecret Format Audit ==="

# 1. Every actual SealedSecret resource must have correct apiVersion
# Only check files where SealedSecret is the primary resource (has encryptedData)
while IFS= read -r f; do
  if ! grep -q "apiVersion: bitnami.com/v1alpha1" "$f"; then
    echo "FAIL: $f missing apiVersion: bitnami.com/v1alpha1"
    ERRORS=$((ERRORS + 1))
  fi
done < <(grep -rl "encryptedData:" "$REPO_ROOT/redhat" --include="*.yaml" 2>/dev/null || true)

# 2. No plaintext Secret resources outside safe contexts
while IFS= read -r f; do
  # Skip template files
  [[ "$f" == *.yaml.template ]] && continue
  # Skip files that contain SealedSecret (refs in ArgoCD apps, etc.)
  grep -q "SealedSecret" "$f" 2>/dev/null && continue
  # Skip ConfigMaps (embedded YAML examples in skills)
  grep -q "kind: ConfigMap" "$f" 2>/dev/null && continue
  # Skip Helm chart templates and values
  [[ "$f" == */chart/templates/* ]] && continue
  [[ "$f" == */chart/values.yaml ]] && continue
  [[ "$f" == */values/*.yaml ]] && continue
  [[ "$f" == */profiles/* ]] && continue
  # Skip ArgoCD Application files (they reference Secret in ignoreDifferences)
  grep -q "kind: Application" "$f" 2>/dev/null && continue
  # Skip secret template directories
  [[ "$f" == */secrets/templates/* ]] && continue
  # Skip broker service accounts and similar platform resources
  [[ "$f" == *serviceaccount* ]] && continue
  [[ "$f" == *broker* ]] && continue
  echo "FAIL: plaintext Secret in $f"
  ERRORS=$((ERRORS + 1))
done < <(grep -rl "kind: Secret$" "$REPO_ROOT/redhat" --include="*.yaml" 2>/dev/null || true)

# 3. No credential files committed
for pattern in "*.pem" "*.key" "*.crt" "credentials.json"; do
  while IFS= read -r f; do
    [[ "$f" == *node_modules* ]] && continue
    [[ "$f" == */.git/* ]] && continue
    echo "FAIL: credential file committed: $f"
    ERRORS=$((ERRORS + 1))
  done < <(find "$REPO_ROOT/redhat" -name "$pattern" 2>/dev/null || true)
done

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "SealedSecret audit FAILED with $ERRORS errors."
  exit 1
fi

SEALED_COUNT=$(grep -rl "encryptedData:" "$REPO_ROOT/redhat" --include="*.yaml" 2>/dev/null | wc -l | tr -d ' ')
echo "SealedSecret audit PASSED ($SEALED_COUNT SealedSecrets, 0 plaintext secrets, 0 credential files)."
