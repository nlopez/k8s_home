# KubeVirt Windows VM Builder

Build and manage Windows Server 2022 VM images for KubeVirt, pre-configured for Palworld Dedicated Server.

## What's Included

- **Packer template** — Automated Windows Server 2022 image build
- **Unattended install** — No manual interaction needed during OS install
- **Pre-installed software**:
  - SteamCMD (for Palworld server)
  - OpenSSH Server (for SSH access)
  - PowerShell Remoting (for WinRM/SSH)
  - RDP enabled
  - virtio drivers (for KubeVirt performance)
- **Build script** — One-command build and upload to Kubernetes
- **Management script** — Start/stop/status/vnc/rdp/ssh

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

### 1. Build the Image

```bash
cd scripts/kubevirt-windows

# Default: uses ~/Downloads/en-us_windows_server_2022.iso
./build.sh

# Or specify custom ISO path
./build.sh --iso /path/to/windows.iso
```

This will:
1. Create a VirtualBox VM with Windows Server 2022
2. Run unattended install + provisioning
3. Convert to QCOW2 format
4. Upload to Kubernetes via CDI
5. Deploy the VM

**Time:** 20-40 minutes (depends on machine speed)

### 2. Manage the VM

```bash
# Check status
./manage.sh status

# Start the VM
./manage.sh start

# Open VNC console (for initial setup)
./manage.sh vnc

# Setup RDP port-forward
./manage.sh rdp &
mstsc localhost  # Windows/macOS RDP client

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
| RDP | localhost (via port-forward) | 3389 | vagrant | vagrant |
| SSH | localhost (via port-forward) | 2222 | vagrant | vagrant |
| WinRM | localhost | 5985 | vagrant | vagrant |

## File Structure

```
scripts/kubevirt-windows/
├── build.sh              # Main build script
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

### Can't Connect via RDP/SSH
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
