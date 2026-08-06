# KubeVirt Windows VM Builder

Build and manage Windows Server 2022 VM images for KubeVirt, pre-configured for Palworld Dedicated Server.

## What's Included

- **Packer template** — Automated Windows Server 2022 image build
- **Unattended install** — No manual interaction needed during OS install
- **Pre-installed software**:
  - SteamCMD (for Palworld server)
  - OpenSSH Server (for SSH access)
  - PowerShell Remoting (for WinRM/SSH)
  - virtio drivers (for KubeVirt performance)
- **Build script** — Build QCOW2 image on Windows host (VMware Fusion)
- **Upload script** — Upload and deploy from macOS (kubectl + virtctl)
- **Management script** — Start/stop/status/vnc/ssh

Built on Windows Server 2022 **Core** (no desktop shell) to keep the image slim — RDP is intentionally disabled; management is via SSH/WinRM.

## Prerequisites

### Local Machine
```bash
# macOS (Homebrew)
brew install packer virtualbox qemu kubectl

# Windows (Chocolatey)
choco install virtualbox packer qemu kubernetes-cli -y
```

### Kubernetes Cluster
- KubeVirt operator installed
- CDI (Containerized Data Importer) installed
- `kubectl` configured with cluster access
- `virtctl` CLI (from KubeVirt releases)

### Windows ISO
Download Windows Server 2022 ISO:
https://www.microsoft.com/en-gb/evalcenter/download-windows-server-2022

## Quick Start

### 1. Build the Image (on Windows host with VMware Fusion)

```bash
cd scripts/kubevirt-windows

# Default: uses ~/Downloads/en-us_windows_server_2022.iso
./build.sh

# Or specify custom ISO path
./build.sh --iso /path/to/windows.iso
```

This will:
1. Create a VMware VM with Windows Server 2022
2. Run unattended install + provisioning
3. Convert to QCOW2 format

**Time:** 20-40 minutes (depends on machine speed)

### 2. Upload & Deploy (from macOS)

Everything except the actual file upload is declarative (managed via ArgoCD):
- Namespace, PVCs, and VM manifest in `apps/palworld-windows/`
- CDI operator via `apps-helm/cdi/`
- KubeVirt via `bootstrap/kubevirt-manifests/`

Copy the built image to your macOS machine, then upload:

```bash
# Copy the qcow2 from the Windows host
scp user@windows-host:scripts/kubevirt-windows/output/palworld-windows.qcow2 ./output/

# Upload to the existing PVC
cd scripts/kubevirt-windows
./upload.sh

# Or specify a custom image path
./upload.sh --image /path/to/palworld-windows.qcow2

# Preview without running (--dry-run)
./upload.sh --dry-run
```

This will:
1. Create the `palworld-windows` namespace
2. Create a 40Gi PVC
3. Upload the image via `virtctl`
4. Wait for the DataVolume to be ready
5. Deploy the VM from the manifest

### 3. Manage the VM

```bash
# Check status
./manage.sh status

# Start the VM
./manage.sh start

# Open VNC console (for initial setup)
./manage.sh vnc

# SSH access
./manage.sh ssh &
ssh vagrant@localhost -p 2222

# Stop the VM
./manage.sh stop

# View logs
./manage.sh logs
```

## VM Access Credentials

| Method | Host | Port | Username | Password |
|--------|------|------|----------|----------|
| SSH | localhost (via port-forward) | 2222 | vagrant | vagrant |
| WinRM | localhost | 5985 | vagrant | vagrant |

## File Structure

```
scripts/kubevirt-windows/
├── build.sh              # Build QCOW2 image (Windows host)
├── upload.sh             # Upload & deploy from macOS
├── manage.sh             # VM management script
├── packer/
│   └── windows.pkr.hcl   # Packer template
├── files/
│   └── Autounattend.xml  # Windows unattended install
├── scripts/
│   ├── enable-winrm.ps1  # WinRM setup (runs during install)
│   ├── customise.ps1     # SteamCMD, SSH, virtio drivers
│   └── shutdown.bat      # Clean shutdown after build
└── output/               # Generated QCOW2 image
    └── palworld-windows.qcow2
```

## Customization

### Add More Software
Edit `scripts/customise.ps1` and add more Chocolatey packages:
```powershell
choco install notepadplusplus git vscode -y --no-progress
```

### Change VM Resources
Edit `packer/windows.pkr.hcl`:
```hcl
cpus    = 8      # Increase CPUs
memory  = 16384  # Increase RAM (MB)
disk_size = "81920"  # 80GB disk
```

### Change Admin Password
Edit `files/Autounattend.xml` — search for `vagrant` and replace with your password.

## Troubleshooting

### Build Fails with ISO Checksum Error
Update `iso_checksum` in `packer/windows.pkr.hcl` with the correct hash.

### VM Won't Start After Build
Check the DataVolume status:
```bash
kubectl get dv -n palworld-windows
kubectl describe dv palworld-os-disk -n palworld-windows
```

### Can't Connect via SSH
1. Wait 5-10 minutes after VM starts for services to initialize
2. Check VM status: `./manage.sh status`
3. View logs: `./manage.sh logs`
4. Try VNC console: `./manage.sh vnc` to verify Windows is running

### CDI Upload Stuck
Check upload proxy:
```bash
kubectl get pods -n cdi
kubectl port-forward -n cdi $(kubectl get pod -n cdi -l cdi.kubevirt.io=cdi-uploadproxy -o jsonpath='{.items[0].metadata.name}') 5000:5000
```

## License

Based on the approach from https://www.rootisgod.com/2024/Running-Windows-VMs-in-Kubernetes-with-Kubevirt/

Windows Server 2022 evaluation ISO from Microsoft.
