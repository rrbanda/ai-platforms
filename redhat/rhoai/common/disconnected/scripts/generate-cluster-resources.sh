#!/usr/bin/env bash
# chmod +x generate-cluster-resources.sh
#
# Generate Kubernetes manifests for configuring a disconnected OpenShift cluster
# to pull RHOAI images from an internal mirror registry.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TEMPLATE_DIR="${SCRIPT_DIR}/../cluster-resources"

readonly DEFAULT_OUTPUT_DIR="./cluster-resources"
readonly DEFAULT_REDHAT_CATALOG="mirror-redhat-operators"
readonly DEFAULT_CERTIFIED_CATALOG="mirror-certified-operators"

REGISTRY=""
REDHAT_CATALOG="${DEFAULT_REDHAT_CATALOG}"
CERTIFIED_CATALOG="${DEFAULT_CERTIFIED_CATALOG}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Generate Kubernetes manifests for disconnected OpenShift AI cluster configuration.

Options:
  --registry <url>           Internal mirror registry URL (required)
  --redhat-catalog <name>    CatalogSource name for Red Hat operators
                             (default: ${DEFAULT_REDHAT_CATALOG})
  --certified-catalog <name> CatalogSource name for certified operators
                             (default: ${DEFAULT_CERTIFIED_CATALOG})
  --output-dir <path>        Output directory (default: ${DEFAULT_OUTPUT_DIR})
  -h, --help                 Show this help

Example:
  ${SCRIPT_NAME} --registry registry.internal.example.com:5000 \\
      --output-dir ./my-cluster-resources
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --registry)           REGISTRY="$2"; shift 2 ;;
            --redhat-catalog)     REDHAT_CATALOG="$2"; shift 2 ;;
            --certified-catalog)  CERTIFIED_CATALOG="$2"; shift 2 ;;
            --output-dir)         OUTPUT_DIR="$2"; shift 2 ;;
            -h|--help)            usage; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
}

validate_args() {
    [[ -z "${REGISTRY}" ]] && die "--registry is required"
    REGISTRY="${REGISTRY%/}"
}

generate_idms() {
    local output="${OUTPUT_DIR}/idms.yaml"
    local template="${TEMPLATE_DIR}/idms-template.yaml"

    if [[ -f "${template}" ]]; then
        sed "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" "${template}" > "${output}"
    else
        cat > "${output}" <<EOF
# ImageDigestMirrorSet — redirects image pulls to the internal mirror registry.
# Apply with: oc apply -f idms.yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: rhoai-mirror
spec:
  imageDigestMirrors:
    # Mirror registry.redhat.io images
    - mirrors:
        - ${REGISTRY}
      source: registry.redhat.io
    # Mirror quay.io images
    - mirrors:
        - ${REGISTRY}
      source: quay.io
    # Mirror registry.connect.redhat.com images
    - mirrors:
        - ${REGISTRY}
      source: registry.connect.redhat.com
EOF
    fi

    echo "  Created ${output}"
}

generate_redhat_catalogsource() {
    local output="${OUTPUT_DIR}/catalogsource-redhat.yaml"
    local template="${TEMPLATE_DIR}/catalogsource-redhat-template.yaml"

    if [[ -f "${template}" ]]; then
        sed \
            -e "s|CATALOG_NAME_PLACEHOLDER|${REDHAT_CATALOG}|g" \
            -e "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" \
            "${template}" > "${output}"
    else
        cat > "${output}" <<EOF
# CatalogSource — mirrored Red Hat operator catalog.
# Apply with: oc apply -f catalogsource-redhat.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${REDHAT_CATALOG}
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${REGISTRY}/redhat/redhat-operator-index:REPLACE_OCP_VERSION
  displayName: Mirrored Red Hat Operators
  publisher: Red Hat (mirrored)
  updateStrategy:
    registryPoll:
      interval: 30m
EOF
    fi

    echo "  Created ${output}"
}

generate_certified_catalogsource() {
    local output="${OUTPUT_DIR}/catalogsource-certified.yaml"
    local template="${TEMPLATE_DIR}/catalogsource-certified-template.yaml"

    if [[ -f "${template}" ]]; then
        sed \
            -e "s|CATALOG_NAME_PLACEHOLDER|${CERTIFIED_CATALOG}|g" \
            -e "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" \
            "${template}" > "${output}"
    else
        cat > "${output}" <<EOF
# CatalogSource — mirrored certified operator catalog.
# Apply with: oc apply -f catalogsource-certified.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${CERTIFIED_CATALOG}
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${REGISTRY}/redhat/certified-operator-index:REPLACE_OCP_VERSION
  displayName: Mirrored Certified Operators
  publisher: Red Hat (mirrored)
  updateStrategy:
    registryPoll:
      interval: 30m
EOF
    fi

    echo "  Created ${output}"
}

generate_disable_default_catalogs() {
    local output="${OUTPUT_DIR}/disable-default-catalogs.yaml"
    local template="${TEMPLATE_DIR}/disable-default-catalogs.yaml"

    if [[ -f "${template}" ]]; then
        cp "${template}" "${output}"
    else
        cat > "${output}" <<EOF
# OperatorHub — disable all default catalog sources to prevent pulling from the internet.
# Apply with: oc apply -f disable-default-catalogs.yaml
apiVersion: config.openshift.io/v1
kind: OperatorHub
metadata:
  name: cluster
spec:
  disableAllDefaultSources: true
EOF
    fi

    echo "  Created ${output}"
}

main() {
    parse_args "$@"
    validate_args

    mkdir -p "${OUTPUT_DIR}"

    echo "Generating disconnected cluster resources..."
    echo "  Registry: ${REGISTRY}"
    echo ""

    generate_idms
    generate_redhat_catalogsource
    generate_certified_catalogsource
    generate_disable_default_catalogs

    echo ""
    echo "All resources generated in ${OUTPUT_DIR}/"
    echo ""
    echo "Apply to cluster:"
    echo "  oc apply -f ${OUTPUT_DIR}/idms.yaml"
    echo "  oc apply -f ${OUTPUT_DIR}/catalogsource-redhat.yaml"
    echo "  oc apply -f ${OUTPUT_DIR}/catalogsource-certified.yaml"
    echo "  oc apply -f ${OUTPUT_DIR}/disable-default-catalogs.yaml"
    echo ""
    echo "NOTE: Replace REPLACE_OCP_VERSION in CatalogSource files with your OCP version (e.g. v4.14)."
}

main "$@"
