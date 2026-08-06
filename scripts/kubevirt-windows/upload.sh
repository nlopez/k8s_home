#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Upload QCOW2 image to existing palworld-windows PVC
#
# Run from macOS (or any machine with kubectl/virtctl)
# after copying the qcow2 file from the Windows build host.
#
# Prerequisites:
#   - kubectl configured for your cluster
#   - virtctl installed
#   - CDI operator deployed (via ArgoCD apps-helm/cdi/)
#   - Namespace + PVCs already applied (via ArgoCD apps/palworld-windows/)
#   - QCOW2 file (default: output/palworld-windows.qcow2)
#
# Usage:
#   ./upload.sh [--image /path/to/palworld-windows.qcow2]
#   ./upload.sh --dry-run   # Show what would run
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
QCOW2_FILE="$OUTPUT_DIR/palworld-windows.qcow2"
NAMESPACE="palworld-windows"
PVC_NAME="os-disk"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()  { echo -e "${GREEN}✓${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*" >&2; }

# Parse arguments
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --image)   QCOW2_FILE="$2"; shift 2;;
        --dry-run) DRY_RUN=1; shift;;
        *)         err "Unknown option: $1"; exit 1;;
    esac
done

# Expand ~ to full path
QCOW2_FILE="${QCOW2_FILE/#\~/$HOME}"

# Check prerequisites
check_prereqs() {
    local missing=0

    for cmd in kubectl virtctl; do
        if ! command -v "$cmd" &>/dev/null; then
            err "$cmd is not installed"
            missing=1
        fi
    done

    if [[ $missing -eq 1 ]]; then
        err "Install missing prerequisites and try again"
        echo "  kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  virtctl: https://github.com/kubevirt/kubevirt/releases"
        exit 1
    fi

    # Check CDI
    if ! kubectl get cdi cdi -n cdi &>/dev/null; then
        err "CDI operator not found in cluster"
        echo "  CDI is managed via ArgoCD (apps-helm/cdi/)."
        echo "  Make sure the bootstrap ApplicationSet is synced:"
        echo "    kubectl get applicationset -n argocd"
        exit 1
    fi

    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        err "Namespace '$NAMESPACE' not found"
        echo "  Apply namespace manifest:"
        echo "    kubectl apply -f apps/palworld-windows/namespace.yaml"
        exit 1
    fi

    # Check PVC exists
    if ! kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        err "PVC '$PVC_NAME' not found in namespace '$NAMESPACE'"
        echo "  Apply PVC manifest:"
        echo "    kubectl apply -f apps/palworld-windows/pvc-os-disk.yaml"
        exit 1
    fi

    # Check image file
    if [[ ! -f "$QCOW2_FILE" ]]; then
        err "Image file not found: $QCOW2_FILE"
        echo "  Specify with: --image /path/to/palworld-windows.qcow2"
        exit 1
    fi

    ok "All prerequisites found"
    ok "Image: $QCOW2_FILE"
    ok "PVC: $PVC_NAME ($NAMESPACE)"
}

# Upload the image via virtctl
upload_image() {
    log "Uploading image to PVC '$PVC_NAME'..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would run:"
        log "  virtctl image-upload pvc $PVC_NAME -n $NAMESPACE \\"
        log "    --image-path=$QCOW2_FILE --size=80Gi --insecure --wait-secs=600"
        return
    fi

    virtctl image-upload pvc "$PVC_NAME" -n "$NAMESPACE" \
        --image-path="$QCOW2_FILE" --size=80Gi --insecure --wait-secs=600

    ok "Image uploaded"
}

# Main
main() {
    log "=== Upload Windows QCOW2 Image ==="
    echo ""

    check_prereqs
    upload_image

    echo ""
    log "=== Complete ==="
    ok "Image: $QCOW2_FILE"
    ok "PVC: $PVC_NAME (namespace: $NAMESPACE)"
    echo ""
    log "Next steps:"
    echo "  1. Verify VM manifest is applied: kubectl apply -f apps/palworld-windows/"
    echo "  2. Start the VM: virtctl start palworld -n $NAMESPACE"
    echo "  3. Open VNC: virtctl vnc palworld -n $NAMESPACE"
}

main "$@"
