#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Palworld Windows VM Manager
# 
# Usage:
#   ./manage.sh [start|stop|restart|status|vnc|rdp|ssh|logs]
# ============================================================

NAMESPACE="palworld-windows"
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

# Check if VM exists
check_vm() {
    if ! kubectl get vm "$VM_NAME" -n "$NAMESPACE" &>/dev/null; then
        err "VM '$VM_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
}

# Start VM
cmd_start() {
    check_vm
    log "Starting VM..."
    virtctl start "$VM_NAME" -n "$NAMESPACE"
    ok "VM starting..."
    log "Waiting for VM to be ready..."
    kubectl wait vm "$VM_NAME" -n "$NAMESPACE" \
        --for=condition=Ready --timeout=5m 2>/dev/null || true
    ok "VM is starting"
}

# Stop VM
cmd_stop() {
    check_vm
    log "Stopping VM..."
    virtctl stop "$VM_NAME" -n "$NAMESPACE"
    ok "VM stopping..."
}

# Restart VM
cmd_restart() {
    check_vm
    log "Restarting VM..."
    virtctl restart "$VM_NAME" -n "$NAMESPACE"
    ok "VM restarting..."
    log "Waiting for VM to be ready..."
    kubectl wait vm "$VM_NAME" -n "$NAMESPACE" \
        --for=condition=Ready --timeout=5m 2>/dev/null || true
    ok "VM is ready"
}

# Show VM status
cmd_status() {
    check_vm
    echo ""
    log "VM Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl get vm "$VM_NAME" -n "$NAMESPACE" -o wide
    echo ""
    log "VM Details:"
    kubectl describe vm "$VM_NAME" -n "$NAMESPACE" | head -30
    echo ""
    log "Associated Pod:"
    kubectl get pods -n "$NAMESPACE" -l kubevirt.io/domain="$VM_NAME" -o wide 2>/dev/null || echo "  No pod found yet"
    echo ""
    log "DataVolume Status:"
    kubectl get dv -n "$NAMESPACE" 2>/dev/null || echo "  No DataVolumes found"
    echo ""
}

# Open VNC console
cmd_vnc() {
    check_vm
    log "Opening VNC console..."
    virtctl vnc "$VM_NAME" -n "$NAMESPACE"
}

# Setup SSH port-forward
cmd_ssh() {
    check_vm
    log "Setting up SSH port-forward (localhost:2222 → VM:22)..."
    kubectl port-forward -n "$NAMESPACE" \
        "$(kubectl get pod -n "$NAMESPACE" -l kubevirt.io/domain="$VM_NAME" -o jsonpath='{.items[0].metadata.name}')" \
        2222:22
}

# Show VM logs
cmd_logs() {
    check_vm
    local pod
    pod=$(kubectl get pod -n "$NAMESPACE" -l kubevirt.io/domain="$VM_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$pod" ]]; then
        log "VM Pod logs (tail -100):"
        kubectl logs "$pod" -n "$NAMESPACE" --tail=100
    else
        warn "No pod found for VM"
    fi
}

# Show usage
usage() {
    echo "Palworld Windows VM Manager"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start   Start the VM"
    echo "  stop    Stop the VM"
    echo "  restart Restart the VM"
    echo "  status  Show VM status"
    echo "  vnc     Open VNC console"
    echo "  ssh     Setup SSH port-forward (localhost:2222)"
    echo "  logs    Show VM pod logs"
    echo ""
    echo "Examples:"
    echo "  $0 start        # Start the VM"
    echo "  $0 status       # Check VM status"
    echo "  $0 ssh &        # Background SSH port-forward"
}

# Main
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    start)     cmd_start;;
    stop)      cmd_stop;;
    restart)   cmd_restart;;
    status)    cmd_status;;
    vnc)       cmd_vnc;;
    ssh)       cmd_ssh;;
    logs)      cmd_logs;;
    *)         err "Unknown command: $1"; usage; exit 1;;
esac
