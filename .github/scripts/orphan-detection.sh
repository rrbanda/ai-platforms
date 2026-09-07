#!/usr/bin/env bash
# Detect orphaned files and broken ArgoCD app paths.
# Non-blocking: advisory only.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WARNINGS=0

echo "=== Orphan Detection (advisory) ==="

# 1. ArgoCD apps pointing to non-existent paths
echo "--- ArgoCD path validation ---"
while IFS= read -r f; do
  while IFS= read -r path_val; do
    [ -z "$path_val" ] && continue
    FULL="$REPO_ROOT/$path_val"
    if [ ! -d "$FULL" ]; then
      REL="${f#$REPO_ROOT/}"
      echo "WARN: $REL references non-existent path: $path_val"
      WARNINGS=$((WARNINGS + 1))
    fi
  done < <(grep "^\s*path:" "$f" 2>/dev/null | awk '{print $2}' | grep -v '^\$')
done < <(find "$REPO_ROOT/redhat" -name "*.yaml" -exec grep -l "kind: Application" {} \; 2>/dev/null || true)

# 2. YAML files in agent dirs not referenced by kustomization
echo "--- Unreferenced agent files ---"
AGENTS_DIR="$REPO_ROOT/redhat/rhoai/v3.5/base/03-workloads/agents"
if [ -d "$AGENTS_DIR" ]; then
  for agent_dir in "$AGENTS_DIR"/*/; do
    [ ! -f "$agent_dir/kustomization.yaml" ] && continue
    KUST_CONTENT=$(cat "$agent_dir/kustomization.yaml")
    for yaml_file in "$agent_dir"/*.yaml; do
      [ ! -f "$yaml_file" ] && continue
      BASE=$(basename "$yaml_file")
      [ "$BASE" = "kustomization.yaml" ] && continue
      if ! echo "$KUST_CONTENT" | grep -q "$BASE"; then
        REL="${yaml_file#$REPO_ROOT/}"
        echo "WARN: $REL not referenced in kustomization.yaml"
        WARNINGS=$((WARNINGS + 1))
      fi
    done
  done
fi

echo ""
echo "Orphan detection completed: $WARNINGS warnings (advisory, non-blocking)."
exit 0
