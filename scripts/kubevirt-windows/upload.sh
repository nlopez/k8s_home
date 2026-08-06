#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Upload QCOW2 image to Kubernetes (CDI) and deploy VM
#
# Run this from macOS (or any machine with kubectl/virtctl)
# after copying the qcow2 file from the Windows build host.
#
# Prerequisites:
#   - kubectl configured for your cluster
#   - virtctl installed
#   - CDI operator installed in the cluster
#   - QCOW2 file (default: output/palworld-windows.qcow2)
#
# Usage:
#   ./upload.sh [--image /path/to/palworld-windows.qcow2]
#   ./upload.sh --dry-run   # Show manifests without applying
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$SCRIPT_DIR/output"
QCOW2_FILE="$OUTPUT_DIR/palworld-windows.qcow2"
NAMESPACE="palworld-windows"
PVC_NAME="palworld-os-disk"
VM_NAME="palworld"

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
        echo "  CDI is managed via ArgoCD in bootstrap/kubevirt-manifests/."
        echo "  Make sure the kubevirt ApplicationSet is synced:"
        echo "    kubectl get application kubevirt -n argocd"
        echo "  Or deploy manually:"
        echo "    kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.66.0/cdi-operator.yaml"
        echo "    kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.66.0/cdi-cr.yaml"
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
}

# Upload to Kubernetes via CDI DataVolume
upload_to_k8s() {
    log "Uploading image to Kubernetes via CDI..."

    # Create namespace
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would create namespace: $NAMESPACE"
    else
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
        ok "Namespace '$NAMESPACE' ready"
    fi

    # Create PVC
    log "Creating PVC..."
    cat <<EOF | { if [[ $DRY_RUN -eq 1 ]]; then cat; else kubectl apply -f -; fi; }
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 40Gi
EOF
    ok "PVC '$PVC_NAME' created"

    # Upload using virtctl
    log "Uploading image via virtctl..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would run:"
        log "  virtctl upload disk --image=$QCOW2_FILE --pvc=$PVC_NAME --namespace=$NAMESPACE --size=40Gi --wait-secs=600"
    else
        virtctl upload disk --image="$QCOW2_FILE" --pvc="$PVC_NAME" \
            --namespace="$NAMESPACE" --size=40Gi --wait-secs=600
    fi
    ok "Image uploaded"
}

# Wait for DataVolume to complete
wait_for_dv() {
    log "Waiting for DataVolume to become ready..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would wait for DataVolume '$PVC_NAME' to be ready (30m timeout)"
    else
        kubectl wait dv "$PVC_NAME" -n "$NAMESPACE" \
            --for=condition=Ready --timeout=30m
    fi
    ok "DataVolume ready"
}

# Deploy the VM
deploy_vm() {
    log "Deploying VM..."

    # Apply VM manifest
    VM_MANIFEST="$BASE_DIR/apps/palworld-windows/vm.yaml"
    if [[ ! -f "$VM_MANIFEST" ]]; then
        err "VM manifest not found: $VM_MANIFEST"
        exit 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would apply: $VM_MANIFEST"
    else
        kubectl apply -f "$VM_MANIFEST"
    fi
    ok "VM manifest applied"

    # Wait for VM to start
    log "Waiting for VM to start..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would wait for VM '$VM_NAME' to be ready (10m timeout)"
    else
        kubectl wait vm "$VM_NAME" -n "$NAMESPACE" \
            --for=condition=Ready --timeout=10m 2>/dev/null || true
    fi

    ok "VM deployed!"
    echo ""
    log "Access the VM via:"
    echo "  SSH:   kubectl port-forward svc/${VM_NAME}-windows 2222:22 -n $NAMESPACE"
    echo "  VNC:   virtctl vnc $VM_NAME -n $NAMESPACE"
    echo "  RDP:   kubectl port-forward svc/${VM_NAME}-windows 3389:3389 -n $NAMESPACE"
}

# Main
main() {
    log "=== Upload & Deploy Windows VM ==="
    echo ""

    check_prereqs
    upload_to_k8s
    wait_for_dv
    deploy_vm

    echo ""
    log "=== Complete ==="
    ok "Image: $QCOW2_FILE"
    ok "VM: $VM_NAME (namespace: $NAMESPACE)"
}

main "$@"
