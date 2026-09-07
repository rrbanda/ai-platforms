#!/usr/bin/env bash
# Search and list models from the internal OpenShift model catalog.
# Requires: oc, yq

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

NAMESPACE="rhoai-model-registries"
POD_NAME="" DB_USER="" DB_NAME=""

_init_db() {
    POD_NAME="$(oc get pods -n "$NAMESPACE" -o name 2>/dev/null | grep model-catalog-postgres | cut -d'/' -f2)"
    if [ -z "$POD_NAME" ]; then
        echo -e "${RED}Error: model-catalog-postgres pod not found in namespace $NAMESPACE${NC}" >&2
        echo "Is the cluster reachable? Run: oc whoami" >&2
        exit 1
    fi
    DB_USER="$(oc get secret model-catalog-postgres -n "$NAMESPACE" -o yaml | yq '.data.database-user' | base64 -d)"
    DB_NAME="$(oc get secret model-catalog-postgres -n "$NAMESPACE" -o yaml | yq '.data.database-name' | base64 -d)"
}

db_query() {
    oc exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -t -c "$1" 2>/dev/null
}

cmd_search() {
    local term="${1:-}"
    if [ -z "$term" ]; then
        echo -e "${RED}Error: search term required${NC}" >&2
        echo "Usage: $0 search <term>" >&2
        exit 1
    fi

    _init_db

    echo -e "${BLUE}Searching catalog for: ${CYAN}$term${NC}"
    echo ""

    MODELS=$(db_query "
    SELECT DISTINCT SPLIT_PART(c.name, ':', 2) AS model_name
    FROM \"Artifact\" a
    JOIN \"Attribution\" attr ON a.id = attr.artifact_id
    JOIN \"Context\" c ON attr.context_id = c.id
    WHERE c.type_id = 15
    AND (a.uri LIKE 'oci://%' OR a.uri LIKE 'https://%' OR a.uri LIKE 's3://%')
    AND LOWER(SPLIT_PART(c.name, ':', 2)) LIKE LOWER('%${term}%')
    ORDER BY model_name;
    ")

    local count=0
    while IFS='|' read -r model; do
        model=$(echo "$model" | xargs)
        [ -z "$model" ] && continue
        echo "$model"
        ((count++)) || true
    done <<< "$MODELS"

    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No models found matching '$term'${NC}"
        echo ""
        echo "Try a broader term, or run: $0 list-families"
        exit 0
    fi

    echo ""
    echo -e "${GREEN}Found: $count model(s)${NC}"
}

cmd_list() {
    local family="${1:-}"
    _init_db

    if [ -z "$family" ]; then
        echo -e "${BLUE}All Models in Catalog${NC}"
        echo ""
        MODELS=$(db_query "
        SELECT DISTINCT SPLIT_PART(c.name, ':', 2) AS model_name
        FROM \"Artifact\" a
        JOIN \"Attribution\" attr ON a.id = attr.artifact_id
        JOIN \"Context\" c ON attr.context_id = c.id
        WHERE c.type_id = 15
        AND (a.uri LIKE 'oci://%' OR a.uri LIKE 'https://%' OR a.uri LIKE 's3://%')
        ORDER BY model_name;
        ")
    else
        echo -e "${BLUE}Models with family/tag: ${CYAN}$family${NC}"
        echo ""
        MODELS=$(db_query "
        SELECT DISTINCT SPLIT_PART(c.name, ':', 2) AS model_name
        FROM \"Artifact\" a
        JOIN \"Attribution\" attr ON a.id = attr.artifact_id
        JOIN \"Context\" c ON attr.context_id = c.id
        JOIN \"ContextProperty\" cp ON c.id = cp.context_id
        WHERE c.type_id = 15
        AND (a.uri LIKE 'oci://%' OR a.uri LIKE 'https://%' OR a.uri LIKE 's3://%')
        AND LOWER(cp.name) = LOWER('$family')
        ORDER BY model_name;
        ")
    fi

    local count=0
    while IFS='|' read -r model; do
        model=$(echo "$model" | xargs)
        [ -z "$model" ] && continue
        echo "$model"
        ((count++)) || true
    done <<< "$MODELS"

    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No models found${NC}"
        [ -n "$family" ] && echo "Run: $0 list-families  to see available tags"
        exit 0
    fi

    echo ""
    echo -e "${GREEN}Total: $count${NC}"
}

cmd_list_families() {
    _init_db

    echo -e "${BLUE}Available Model Families / Tags${NC}"
    echo ""

    FAMILIES=$(db_query "
    SELECT DISTINCT cp.name AS family, COUNT(DISTINCT a.id) AS model_count
    FROM \"Context\" c
    JOIN \"ContextProperty\" cp ON c.id = cp.context_id
    JOIN \"Attribution\" attr ON c.id = attr.context_id
    JOIN \"Artifact\" a ON attr.artifact_id = a.id
    WHERE c.type_id = 15
    AND (a.uri LIKE 'oci://%' OR a.uri LIKE 'https://%' OR a.uri LIKE 's3://%')
    GROUP BY cp.name
    ORDER BY cp.name;
    ")

    if [ -z "$FAMILIES" ]; then
        echo -e "${RED}No families found${NC}"
        exit 1
    fi

    printf "%-35s %s\n" "Family / Tag" "Models"
    echo "--------------------------------------------"
    while IFS='|' read -r family count; do
        family=$(echo "$family" | xargs); count=$(echo "$count" | xargs)
        [ -z "$family" ] && continue
        printf "%-35s %s\n" "$family" "$count"
    done <<< "$FAMILIES"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  search <term>      Search models by keyword (case-insensitive, supports partial match)
  list [family]      List all models, optionally filtered by family/tag
  list-families      Show all available family/tag names with model counts

Examples:
  $(basename "$0") search llama
  $(basename "$0") search "8b.*fp8"
  $(basename "$0") list
  $(basename "$0") list qwen
  $(basename "$0") list-families
EOF
    exit 1
}

case "${1:-}" in
    search)        cmd_search "${2:-}" ;;
    list)          cmd_list "${2:-}" ;;
    list-families) cmd_list_families ;;
    *) usage ;;
esac
