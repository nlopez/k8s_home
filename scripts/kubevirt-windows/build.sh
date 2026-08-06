#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Palworld Windows VM Builder for KubeVirt
#
# Prerequisites:
#   - Packer (packer.io)
#   - VMware Fusion Pro (vmware.com/fusion)
#   - qemu-img (part of qemu) — for QCOW2 conversion
#   - kubectl + CDI operator installed
#   - Windows Server 2022 ISO
#
# Usage:
#   ./build.sh [--iso /path/to/windows.iso]
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

while [[ $# -gt 0 ]]; do
    case $1 in
        --iso) ISO_PATH="$2"; shift 2;;
        *) err "Unknown option: $1"; exit 1;;
    esac
done

# Check prerequisites
check_prereqs() {
    local missing=0

    for cmd in packer qemu-img kubectl vmware-vmx; do
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

    # Expand ~ to full path
    ISO_PATH="${ISO_PATH/#\~/$HOME}"

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
    log "Building Windows image with Packer (VMware)..."
    log "This will take 20-40 minutes depending on your machine."
    echo ""

    # Clean previous builds
    rm -rf "$PACKER_DIR/output-vmware" 2>/dev/null || true
    rm -rf "$OUTPUT_DIR" 2>/dev/null || true
    mkdir -p "$OUTPUT_DIR"

    # Initialize Packer plugins
    cd "$PACKER_DIR"
    log "Initializing Packer plugins..."
    packer init .

    # Run Packer with ISO path override
    packer build -var "iso_path=$ISO_PATH" windows.pkr.hcl

    # Find the output VMDK
    local vmdk=""
    if [[ -f "output-vmware/palworld-windows.vmdk" ]]; then
        vmdk="output-vmware/palworld-windows.vmdk"
    elif ls output-vmware/*.vmdk &>/dev/null; then
        vmdk=$(ls output-vmware/*.vmdk | head -1)
    else
        err "No VMDK output found in output-vmware/"
        exit 1
    fi

    ok "Packer build complete: $vmdk"

    # Convert to QCOW2 for KubeVirt
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

# Main
main() {
    log "=== Palworld Windows VM Builder ==="
    echo ""

    check_prereqs
    build_image

    echo ""
    log "=== Build Complete ==="
    ok "VM image: $QCOW2_FILE"
    echo ""
    log "Next steps (run from macOS or any machine with kubectl/virtctl):"
    echo "  1. Copy the image to your cluster machine:"
    echo "     scp $QCOW2_FILE user@cluster-host:~/"
    echo "  2. Upload and deploy:"
    echo "     cd $(dirname "$SCRIPT_DIR")/kubevirt-windows"
    echo "     ./upload.sh --image $QCOW2_FILE"
}

main "$@"
