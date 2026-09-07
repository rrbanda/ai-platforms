#!/usr/bin/env bash
# Audit RBAC for overly permissive ClusterRoles and bindings.
# Non-blocking: exits 0 with warnings, does not fail the build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WARNINGS=0

echo "=== RBAC Audit (advisory) ==="

# 1. Flag ClusterRoles with wildcard resources or verbs
while IFS= read -r f; do
  [[ "$f" == */chart/templates/* ]] && continue
  [[ "$f" == */.git/* ]] && continue
  LINE=$(grep -n 'resources.*"\*"\|verbs.*"\*"\|resources:.*\*\|verbs:.*\*' "$f" 2>/dev/null | head -1 || true)
  if [ -n "$LINE" ]; then
    REL="${f#$REPO_ROOT/}"
    echo "WARN: wildcard RBAC in $REL: $LINE"
    WARNINGS=$((WARNINGS + 1))
  fi
done < <(find "$REPO_ROOT/redhat" -name "*.yaml" -exec grep -li "kind:.*ClusterRole" {} \; 2>/dev/null || true)

# 2. Flag ClusterRoleBindings to cluster-admin
while IFS= read -r f; do
  if grep -q "name: cluster-admin" "$f" 2>/dev/null; then
    REL="${f#$REPO_ROOT/}"
    echo "WARN: cluster-admin binding in $REL"
    WARNINGS=$((WARNINGS + 1))
  fi
done < <(find "$REPO_ROOT/redhat" -name "*.yaml" -exec grep -li "kind:.*ClusterRoleBinding" {} \; 2>/dev/null || true)

echo ""
echo "RBAC audit completed: $WARNINGS warnings (advisory, non-blocking)."
exit 0
