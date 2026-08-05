#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Palworld Windows VM Builder for KubeVirt
# 
# Prerequisites:
#   - Packer (packer.io)
#   - VirtualBox (virtualbox.org)
#   - qemu-img (part of qemu)
#   - kubectl + CDI operator installed
#   - Windows Server 2022 ISO
#
# Usage:
#   ./build.sh [--iso /path/to/windows.iso] [--version 1.7.0]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PACKER_DIR="$SCRIPT_DIR/packer"
OUTPUT_DIR="$SCRIPT_DIR/output"
QCOW2_FILE="$OUTPUT_DIR/palworld-windows.qcow2"

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
ISO_PATH=""
KUBEVIRT_VERSION="1.7.0"

while [[ $# -gt 0 ]]; do
    case $1 in
        --iso) ISO_PATH="$2"; shift 2;;
        --version) KUBEVIRT_VERSION="$2"; shift 2;;
        *) err "Unknown option: $1"; exit 1;;
    esac
done

# Check prerequisites
check_prereqs() {
    local missing=0
    
    for cmd in packer qemu-img kubectl VBoxManage; do
        if ! command -v "$cmd" &>/dev/null; then
            err "$cmd is not installed"
            missing=1
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        err "Install missing prerequisites and try again"
        exit 1
    fi
    
    # Check for ISO
    if [[ -z "$ISO_PATH" ]]; then
        ISO_PATH="$HOME/Downloads/en-us_windows_server_2022.iso"
    fi
    
    if [[ ! -f "$ISO_PATH" ]]; then
        err "Windows ISO not found: $ISO_PATH"
        echo "  Download from: https://www.microsoft.com/en-gb/evalcenter/download-windows-server-2022"
        echo "  Specify with: --iso /path/to/windows.iso"
        exit 1
    fi
    
    ok "All prerequisites found"
    ok "ISO: $ISO_PATH"
}

# Build image with Packer
build_image() {
    log "Building Windows image with Packer..."
    log "This will take 20-40 minutes depending on your machine."
    echo ""
    
    # Clean previous builds
    rm -rf "$PACKER_DIR/output-windows" 2>/dev/null || true
    rm -rf "$OUTPUT_DIR" 2>/dev/null || true
    mkdir -p "$OUTPUT_DIR"
    
    # Initialize Packer plugins
    cd "$PACKER_DIR"
    log "Initializing Packer plugins..."
    packer init .
    
    # Run Packer
    packer build windows.pkr.hcl
    
    # Find the output VMDK
    local vmdk=""
    if [[ -f "output-windows/win2022-disk001.vmdk" ]]; then
        vmdk="output-windows/win2022-disk001.vmdk"
    elif ls output-windows/*.vmdk &>/dev/null; then
        vmdk=$(ls output-windows/*.vmdk | head -1)
    else
        err "No VMDK output found in output-windows/"
        exit 1
    fi
    
    ok "Packer build complete: $vmdk"
    
    # Convert to QCOW2
    log "Converting VMDK to QCOW2..."
    qemu-img convert -f vmdk -O qcow2 "$vmdk" "$QCOW2_FILE"
    
    # Show info
    local size
    size=$(du -h "$QCOW2_FILE" | cut -f1)
    ok "QCOW2 image created: $QCOW2_FILE ($size)"
    qemu-img info "$QCOW2_FILE" | grep "virtual size" | while read -r line; do
        ok "  $line"
    done
    
    cd - > /dev/null
}

# Upload to Kubernetes via CDI DataVolume
upload_to_k8s() {
    log "Uploading image to Kubernetes via CDI..."
    
    # Check if CDI is installed
    if ! kubectl get cdi cdi -n cdi &>/dev/null; then
        err "CDI operator not found in cluster"
        echo "  Install CDI: kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.61.0/cdi-operator.yaml"
        echo "               kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.61.0/cdi-cr.yaml"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace palworld-windows --dry-run=client -o yaml | kubectl apply -f -
    
    # Create PVC
    log "Creating PVC..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: palworld-os-disk
  namespace: palworld-windows
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 40Gi
EOF
    ok "PVC created"
    
    # Create DataVolume from local file
    log "Creating DataVolume from local file..."
    log "This may take 5-15 minutes for a 40GB image."
    
    # Upload using kubectl cdi-uploadproxy or direct PVC population
    # Method 1: Use virtctl upload (requires uploadproxy)
    if command -v virtctl &>/dev/null; then
        log "Using virtctl to upload image..."
        virtctl upload disk --image="$QCOW2_FILE" --pvc=palworld-os-disk \
            --namespace=palworld-windows --size=40Gi --wait-secs=600
        ok "Image uploaded via virtctl"
    else
        # Method 2: Create DataVolume with HTTP source (requires local web server)
        warn "virtctl not found. Using DataVolume with local file upload."
        warn "Start a local web server in another terminal:"
        warn "  python3 -m http.server 8080 --directory $(dirname "$QCOW2_FILE")"
        warn ""
        warn "Then run: ./upload-http.sh"
        
        # Create DataVolume manifest
        cat > "$OUTPUT_DIR/datavolume.yaml" <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: palworld-os-disk
  namespace: palworld-windows
spec:
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 40Gi
  source:
    pvc:
      name: palworld-os-disk
      namespace: palworld-windows
EOF
        ok "DataVolume manifest created: $OUTPUT_DIR/datavolume.yaml"
    fi
}

# Wait for DataVolume to complete
wait_for_dv() {
    log "Waiting for DataVolume to complete..."
    kubectl wait dv palworld-os-disk -n palworld-windows \
        --for=condition=Ready --timeout=30m
    ok "DataVolume ready"
}

# Deploy the VM
deploy_vm() {
    log "Deploying VM..."
    
    # Apply VM manifest
    kubectl apply -f "$BASE_DIR/apps/palworld-windows/vm.yaml"
    ok "VM manifest applied"
    
    # Wait for VM to start
    log "Waiting for VM to start..."
    kubectl wait vm palworld -n palworld-windows \
        --for=condition=Ready --timeout=10m 2>/dev/null || true
    
    ok "VM deployed! Access via:"
    echo "  RDP:   kubectl port-forward svc/palworld-windows 3389:3389 -n palworld-windows"
    echo "  SSH:   kubectl port-forward svc/palworld-windows 2222:22 -n palworld-windows"
    echo "  VNC:   virtctl vnc palworld -n palworld-windows"
}

# Main
main() {
    log "=== Palworld Windows VM Builder ==="
    echo ""
    
    check_prereqs
    build_image
    upload_to_k8s
    wait_for_dv
    deploy_vm
    
    echo ""
    log "=== Build Complete ==="
    ok "VM image: $QCOW2_FILE"
    ok "VM name: palworld (namespace: palworld-windows)"
}

main "$@"
