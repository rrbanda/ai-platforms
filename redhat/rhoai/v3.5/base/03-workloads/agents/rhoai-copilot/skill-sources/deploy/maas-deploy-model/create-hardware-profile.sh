#!/bin/bash
# Create or update HardwareProfile for model deployments

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create or update a HardwareProfile for model deployments.

Required Parameters:
  --name, -n              Profile name (e.g., "gpu", "llama-70b-profile")

Optional Parameters:
  --namespace, -ns        Target namespace (default: redhat-ods-applications)
  --cpu-min              Minimum CPU cores (default: 1)
  --cpu-default          Default CPU cores (default: 2)
  --cpu-max              Maximum CPU cores (default: 4)
  --memory-min           Minimum memory (default: 2Gi)
  --memory-default       Default memory (default: 8Gi)
  --memory-max           Maximum memory (default: 16Gi)
  --gpu-min              Minimum GPU count (default: 1)
  --gpu-default          Default GPU count (default: 1)
  --gpu-max              Maximum GPU count (default: 1)
  --gpu-type             GPU resource type (default: nvidia.com/gpu)
  --display-name         Display name (default: same as name)
  --description          Profile description
  --disable              Set profile as disabled (default: false)
  --no-gpu               Create CPU-only profile (no GPU accelerator)
  --dry-run              Print manifest without applying
  --output, -o           Output manifest to file instead of applying
  --update               Update existing profile instead of creating new

Preset Profiles:
  --preset small-gpu     1-2 CPU, 4-12Gi Memory, 1 GPU
  --preset medium-gpu    2-4 CPU, 8-24Gi Memory, 1 GPU
  --preset large-gpu     4-8 CPU, 16-48Gi Memory, 1-2 GPU
  --preset xlarge-gpu    8-16 CPU, 32-96Gi Memory, 2-4 GPU
  --preset cpu-only      2-8 CPU, 4-32Gi Memory, No GPU

Examples:
  # Create a basic GPU profile
  $0 -n gpu-profile --cpu-default 2 --memory-default 12Gi --gpu-default 1

  # Create a large GPU profile for 70B models
  $0 -n llama-70b-profile --preset large-gpu --description "Profile for Llama 70B models"

  # Create a CPU-only profile
  $0 -n cpu-profile --no-gpu --cpu-max 8 --memory-max 32Gi

  # Update existing profile
  $0 -n gpu --update --cpu-max 8 --memory-max 24Gi

  # Dry run to see manifest
  $0 -n test-profile --preset medium-gpu --dry-run

EOF
    exit 1
}

# Default values
NAMESPACE="redhat-ods-applications"
CPU_MIN=1
CPU_DEFAULT=2
CPU_MAX=4
MEMORY_MIN="2Gi"
MEMORY_DEFAULT="8Gi"
MEMORY_MAX="16Gi"
GPU_MIN=1
GPU_DEFAULT=1
GPU_MAX=1
GPU_TYPE="nvidia.com/gpu"
DISABLED="false"
NO_GPU=false
DRY_RUN=false
OUTPUT_FILE=""
UPDATE=false

# Parse arguments
NAME=""
DISPLAY_NAME=""
DESCRIPTION=""
PRESET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage ;;
        -n|--name) NAME="$2"; shift 2 ;;
        -ns|--namespace) NAMESPACE="$2"; shift 2 ;;
        --cpu-min) CPU_MIN="$2"; shift 2 ;;
        --cpu-default) CPU_DEFAULT="$2"; shift 2 ;;
        --cpu-max) CPU_MAX="$2"; shift 2 ;;
        --memory-min) MEMORY_MIN="$2"; shift 2 ;;
        --memory-default) MEMORY_DEFAULT="$2"; shift 2 ;;
        --memory-max) MEMORY_MAX="$2"; shift 2 ;;
        --gpu-min) GPU_MIN="$2"; shift 2 ;;
        --gpu-default) GPU_DEFAULT="$2"; shift 2 ;;
        --gpu-max) GPU_MAX="$2"; shift 2 ;;
        --gpu-type) GPU_TYPE="$2"; shift 2 ;;
        --display-name) DISPLAY_NAME="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --disable) DISABLED="true"; shift ;;
        --no-gpu) NO_GPU=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        --update) UPDATE=true; shift ;;
        --preset) PRESET="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# Apply preset if specified
case "$PRESET" in
    "small-gpu")
        CPU_MIN=1; CPU_DEFAULT=2; CPU_MAX=2
        MEMORY_MIN="4Gi"; MEMORY_DEFAULT="8Gi"; MEMORY_MAX="12Gi"
        GPU_MIN=1; GPU_DEFAULT=1; GPU_MAX=1
        ;;
    "medium-gpu")
        CPU_MIN=2; CPU_DEFAULT=4; CPU_MAX=4
        MEMORY_MIN="8Gi"; MEMORY_DEFAULT="16Gi"; MEMORY_MAX="24Gi"
        GPU_MIN=1; GPU_DEFAULT=1; GPU_MAX=1
        ;;
    "large-gpu")
        CPU_MIN=4; CPU_DEFAULT=8; CPU_MAX=8
        MEMORY_MIN="16Gi"; MEMORY_DEFAULT="32Gi"; MEMORY_MAX="48Gi"
        GPU_MIN=1; GPU_DEFAULT=2; GPU_MAX=2
        ;;
    "xlarge-gpu")
        CPU_MIN=8; CPU_DEFAULT=16; CPU_MAX=16
        MEMORY_MIN="32Gi"; MEMORY_DEFAULT="64Gi"; MEMORY_MAX="96Gi"
        GPU_MIN=2; GPU_DEFAULT=4; GPU_MAX=4
        ;;
    "cpu-only")
        CPU_MIN=2; CPU_DEFAULT=4; CPU_MAX=8
        MEMORY_MIN="4Gi"; MEMORY_DEFAULT="16Gi"; MEMORY_MAX="32Gi"
        NO_GPU=true
        ;;
    "")
        # No preset, use defaults or user-specified values
        ;;
    *)
        log_error "Unknown preset: $PRESET"
        log_info "Valid presets: small-gpu, medium-gpu, large-gpu, xlarge-gpu, cpu-only"
        exit 1
        ;;
esac

# Validate required parameters
if [ -z "$NAME" ]; then
    log_error "Missing required parameter: --name"
    usage
fi

# Set defaults
DISPLAY_NAME="${DISPLAY_NAME:-$NAME}"

# Generate manifest
log_info "Generating HardwareProfile manifest..."

TEMP_DIR=$(mktemp -d)
MANIFEST="$TEMP_DIR/hardwareprofile.yaml"

# Build the manifest
cat > "$MANIFEST" << EOF
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: $NAME
  namespace: $NAMESPACE
  annotations:
    opendatahub.io/dashboard-feature-visibility: '[]'
    opendatahub.io/disabled: "$DISABLED"
    opendatahub.io/display-name: $DISPLAY_NAME
EOF

# Add description if provided
if [ -n "$DESCRIPTION" ]; then
    cat >> "$MANIFEST" << EOF
    opendatahub.io/description: "$DESCRIPTION"
EOF
fi

# Add modified date for updates
if [ "$UPDATE" = true ]; then
    MODIFIED_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    cat >> "$MANIFEST" << EOF
    opendatahub.io/modified-date: "$MODIFIED_DATE"
EOF
fi

# Start spec section
cat >> "$MANIFEST" << EOF
spec:
  identifiers:
  - defaultCount: $CPU_DEFAULT
    displayName: CPU
    identifier: cpu
    maxCount: $CPU_MAX
    minCount: $CPU_MIN
    resourceType: CPU
  - defaultCount: $MEMORY_DEFAULT
    displayName: Memory
    identifier: memory
    maxCount: $MEMORY_MAX
    minCount: $MEMORY_MIN
    resourceType: Memory
EOF

# Add GPU accelerator if not CPU-only
if [ "$NO_GPU" = false ]; then
    cat >> "$MANIFEST" << EOF
  - defaultCount: $GPU_DEFAULT
    displayName: GPU
    identifier: $GPU_TYPE
    maxCount: $GPU_MAX
    minCount: $GPU_MIN
    resourceType: Accelerator
EOF
fi

# Display summary
log_info "Profile Configuration:"
echo "  Name: $NAME"
echo "  Namespace: $NAMESPACE"
echo "  Display Name: $DISPLAY_NAME"
[ -n "$DESCRIPTION" ] && echo "  Description: $DESCRIPTION"
echo "  CPU: ${CPU_MIN}-${CPU_MAX} (default: ${CPU_DEFAULT})"
echo "  Memory: ${MEMORY_MIN}-${MEMORY_MAX} (default: ${MEMORY_DEFAULT})"
if [ "$NO_GPU" = false ]; then
    echo "  GPU: ${GPU_MIN}-${GPU_MAX} (default: ${GPU_DEFAULT}) [${GPU_TYPE}]"
else
    echo "  GPU: None (CPU-only profile)"
fi

# Output or apply
if [ "$DRY_RUN" = true ]; then
    log_info "=== HardwareProfile Manifest ==="
    cat "$MANIFEST"
elif [ -n "$OUTPUT_FILE" ]; then
    cp "$MANIFEST" "$OUTPUT_FILE"
    log_success "Manifest written to: $OUTPUT_FILE"
else
    # Check if profile exists
    if oc get hardwareprofile "$NAME" -n "$NAMESPACE" &>/dev/null; then
        if [ "$UPDATE" = true ]; then
            log_warning "HardwareProfile $NAME already exists, updating it"
            oc apply -f "$MANIFEST"
            log_success "HardwareProfile updated successfully!"
        else
            log_error "HardwareProfile $NAME already exists"
            log_info "Use --update to update the existing profile, or choose a different name"
            exit 1
        fi
    else
        log_info "Creating HardwareProfile..."
        oc apply -f "$MANIFEST"
        log_success "HardwareProfile created successfully!"
    fi

    log_info ""
    log_info "To use this profile in a deployment, add:"
    log_info "  --hardware-profile $NAME"
fi

# Cleanup
rm -rf "$TEMP_DIR"
