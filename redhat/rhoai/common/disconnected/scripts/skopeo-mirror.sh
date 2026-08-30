#!/usr/bin/env bash
# chmod +x skopeo-mirror.sh
#
# Mirror container images for disconnected RHOAI deployments using skopeo.
# Works with version-specific image lists generated per RHOAI release.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_LOCAL_DIR="./mirror-images"
readonly DEFAULT_PARALLEL=4
readonly DEFAULT_AUTH_FILE="${HOME}/.docker/config.json"
readonly DEFAULT_REPORT="./mirror-report.txt"

COMMAND=""
IMAGE_LIST=""
LOCAL_DIR="${DEFAULT_LOCAL_DIR}"
TARGET_REGISTRY=""
DRY_RUN=false
PARALLEL="${DEFAULT_PARALLEL}"
AUTH_FILE="${DEFAULT_AUTH_FILE}"
SKIP_TLS_VERIFY=false
REPORT="${DEFAULT_REPORT}"

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0
ABORT=false

trap 'echo ""; echo "Caught SIGINT — aborting after current copies finish..."; ABORT=true' INT

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} <command> [options]

Mirror container images for disconnected OpenShift AI deployments.

Commands:
  pull    Download images from source registries to local directory
  push    Upload images from local directory to target registry
  direct  Copy images directly between registries (partially connected)

Options:
  --image-list <path>     Path to image list file (one image per line)
  --local-dir <path>      Local directory for image storage (default: ${DEFAULT_LOCAL_DIR})
  --target-registry <url> Target registry URL (required for push/direct)
  --dry-run               Show what would be copied without copying
  --parallel <n>          Number of parallel copies (default: ${DEFAULT_PARALLEL})
  --auth-file <path>      Path to auth file (default: \$HOME/.docker/config.json)
  --skip-tls-verify       Skip TLS verification for target registry
  --report <path>         Write mirror report (default: ${DEFAULT_REPORT})
  -h, --help              Show this help

Examples:
  # Pull all images to local directory
  ${SCRIPT_NAME} pull --image-list images-v3.5.txt --local-dir ./offline-bundle

  # Push from local directory to internal registry
  ${SCRIPT_NAME} push --image-list images-v3.5.txt --local-dir ./offline-bundle \\
      --target-registry registry.internal.example.com:5000

  # Direct copy (partially connected environment)
  ${SCRIPT_NAME} direct --image-list images-v3.5.txt \\
      --target-registry registry.internal.example.com:5000
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

parse_args() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    COMMAND="$1"; shift
    case "${COMMAND}" in
        pull|push|direct) ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown command: ${COMMAND}. Use pull, push, or direct." ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image-list)     IMAGE_LIST="$2"; shift 2 ;;
            --local-dir)      LOCAL_DIR="$2"; shift 2 ;;
            --target-registry) TARGET_REGISTRY="$2"; shift 2 ;;
            --dry-run)        DRY_RUN=true; shift ;;
            --parallel)       PARALLEL="$2"; shift 2 ;;
            --auth-file)      AUTH_FILE="$2"; shift 2 ;;
            --skip-tls-verify) SKIP_TLS_VERIFY=true; shift ;;
            --report)         REPORT="$2"; shift 2 ;;
            -h|--help)        usage; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
}

validate_args() {
    [[ -z "${IMAGE_LIST}" ]] && die "--image-list is required"
    [[ ! -f "${IMAGE_LIST}" ]] && die "Image list not found: ${IMAGE_LIST}"

    if [[ "${COMMAND}" == "push" || "${COMMAND}" == "direct" ]]; then
        [[ -z "${TARGET_REGISTRY}" ]] && die "--target-registry is required for ${COMMAND}"
    fi

    if ! command -v skopeo &>/dev/null; then
        die "skopeo is not installed or not in PATH"
    fi

    TARGET_REGISTRY="${TARGET_REGISTRY%/}"
}

build_skopeo_opts() {
    local opts=("--all")
    if [[ -f "${AUTH_FILE}" ]]; then
        opts+=("--authfile" "${AUTH_FILE}")
    fi
    if [[ "${SKIP_TLS_VERIFY}" == true ]]; then
        opts+=("--dest-tls-verify=false")
    fi
    echo "${opts[@]}"
}

# Strip the source registry prefix, keeping the repository path.
# e.g. registry.redhat.io/rhoai/odh-dashboard-rhel8 -> rhoai/odh-dashboard-rhel8
strip_registry() {
    local image="$1"
    echo "${image#*/}"
}

# Produce a filesystem-safe hash of the full image reference for local storage.
image_hash() {
    local image="$1"
    echo -n "${image}" | sha256sum | awk '{print $1}'
}

read_image_list() {
    local -a images=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(echo "${line}" | xargs)"
        [[ -z "${line}" ]] && continue
        [[ "${line}" == \#* ]] && continue
        images+=("${line}")
    done < "${IMAGE_LIST}"
    printf '%s\n' "${images[@]}"
}

do_pull() {
    local image="$1"
    local hash
    hash="$(image_hash "${image}")"
    local dest_dir="${LOCAL_DIR}/${hash}"
    mkdir -p "${dest_dir}"

    local -a opts
    read -ra opts <<< "$(build_skopeo_opts)"

    if [[ "${DRY_RUN}" == true ]]; then
        echo "  [dry-run] skopeo copy ${opts[*]} docker://${image} dir://${dest_dir}/"
        return 0
    fi

    echo "${image}" > "${dest_dir}/source-image.txt"
    skopeo copy "${opts[@]}" "docker://${image}" "dir://${dest_dir}/" 2>&1
}

do_push() {
    local image="$1"
    local hash
    hash="$(image_hash "${image}")"
    local src_dir="${LOCAL_DIR}/${hash}"
    local repo_path
    repo_path="$(strip_registry "${image}")"
    local dest="docker://${TARGET_REGISTRY}/${repo_path}"

    if [[ ! -d "${src_dir}" ]]; then
        echo "  WARNING: Local directory not found for ${image} (expected ${src_dir})" >&2
        return 1
    fi

    local -a opts
    read -ra opts <<< "$(build_skopeo_opts)"

    if [[ "${DRY_RUN}" == true ]]; then
        echo "  [dry-run] skopeo copy ${opts[*]} dir://${src_dir}/ ${dest}"
        return 0
    fi

    skopeo copy "${opts[@]}" "dir://${src_dir}/" "${dest}" 2>&1
}

do_direct() {
    local image="$1"
    local repo_path
    repo_path="$(strip_registry "${image}")"
    local dest="docker://${TARGET_REGISTRY}/${repo_path}"

    local -a opts
    read -ra opts <<< "$(build_skopeo_opts)"

    if [[ "${DRY_RUN}" == true ]]; then
        echo "  [dry-run] skopeo copy ${opts[*]} docker://${image} ${dest}"
        return 0
    fi

    skopeo copy "${opts[@]}" "docker://${image}" "${dest}" 2>&1
}

copy_image() {
    local image="$1"
    local index="$2"

    echo "[${index}/${TOTAL_COUNT}] Copying ${image}"

    local rc=0
    case "${COMMAND}" in
        pull)   do_pull   "${image}" || rc=$? ;;
        push)   do_push   "${image}" || rc=$? ;;
        direct) do_direct "${image}" || rc=$? ;;
    esac

    if [[ ${rc} -ne 0 ]]; then
        echo "  FAILED: ${image}" >&2
        echo "FAIL ${image}" >> "${REPORT}.tmp"
    else
        echo "OK   ${image}" >> "${REPORT}.tmp"
    fi
    return ${rc}
}

write_report() {
    {
        echo "============================================="
        echo " RHOAI Disconnected Mirror Report"
        echo " Command:  ${COMMAND}"
        echo " Date:     $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo " Image list: ${IMAGE_LIST}"
        [[ -n "${TARGET_REGISTRY}" ]] && echo " Target:   ${TARGET_REGISTRY}"
        echo "============================================="
        echo ""
        echo "Total:   ${TOTAL_COUNT}"
        echo "Success: ${SUCCESS_COUNT}"
        echo "Failed:  ${FAIL_COUNT}"
        echo ""
        if [[ -f "${REPORT}.tmp" ]]; then
            echo "--- Details ---"
            cat "${REPORT}.tmp"
        fi
    } > "${REPORT}"
    rm -f "${REPORT}.tmp"

    echo ""
    echo "Report written to ${REPORT}"
}

run_mirror() {
    local -a images
    mapfile -t images < <(read_image_list)
    TOTAL_COUNT=${#images[@]}

    [[ ${TOTAL_COUNT} -eq 0 ]] && die "No images found in ${IMAGE_LIST}"

    echo "=== RHOAI Disconnected Image Mirror ==="
    echo "Command:    ${COMMAND}"
    echo "Images:     ${TOTAL_COUNT}"
    echo "Parallel:   ${PARALLEL}"
    [[ -n "${TARGET_REGISTRY}" ]] && echo "Target:     ${TARGET_REGISTRY}"
    [[ "${DRY_RUN}" == true ]] && echo "Mode:       DRY RUN"
    echo ""

    rm -f "${REPORT}.tmp"
    touch "${REPORT}.tmp"

    local running=0
    local index=0

    for image in "${images[@]}"; do
        if [[ "${ABORT}" == true ]]; then
            echo "Aborting — waiting for in-flight copies..."
            wait
            break
        fi

        index=$((index + 1))

        copy_image "${image}" "${index}" &
        running=$((running + 1))

        if [[ ${running} -ge ${PARALLEL} ]]; then
            wait -n 2>/dev/null || true
            running=$((running - 1))
        fi
    done

    wait

    if [[ -f "${REPORT}.tmp" ]]; then
        SUCCESS_COUNT=$(grep -c '^OK ' "${REPORT}.tmp" 2>/dev/null || echo 0)
        FAIL_COUNT=$(grep -c '^FAIL ' "${REPORT}.tmp" 2>/dev/null || echo 0)
    fi

    write_report

    echo ""
    echo "Summary: ${SUCCESS_COUNT} succeeded, ${FAIL_COUNT} failed out of ${TOTAL_COUNT}"

    [[ ${FAIL_COUNT} -gt 0 ]] && exit 1
    exit 0
}

main() {
    parse_args "$@"
    validate_args
    run_mirror
}

main "$@"
