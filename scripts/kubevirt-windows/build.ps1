# ============================================================
# Palworld Windows VM Builder for KubeVirt
# 
# Prerequisites:
#   - Packer (packer.io) - choco install packer
#   - VMware Workstation Pro (vmware.com)
#   - qemu-img (part of qemu) - choco install qemu
#   - kubectl + CDI operator installed
#   - Windows Server 2022 ISO
#
# Usage:
#   .\build.ps1 -IsoPath "C:\ISOs\windows.iso"
# ============================================================

param(
    [string]$IsoPath = "$env:USERPROFILE\Downloads\en-us_windows_server_2022.iso"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Split-Path -Parent $ScriptDir
$PackerDir = Join-Path $ScriptDir "packer"
$OutputDir = Join-Path $ScriptDir "output"
$Qcow2File = Join-Path $OutputDir "palworld-windows.qcow2"

function Log { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $args" -ForegroundColor Cyan }
function Ok  { Write-Host "✓ $args" -ForegroundColor Green }
function Warn{ Write-Host "⚠ $args" -ForegroundColor Yellow }
function Err { Write-Host "✗ $args" -ForegroundColor Red; throw $args }

# Resolve ISO path
$IsoPath = $IsoPath -replace '^~', $env:USERPROFILE
$IsoPath = [System.IO.Path]::GetFullPath($IsoPath)

if (-not (Test-Path $IsoPath)) {
    Write-Host "  Download from: https://www.microsoft.com/en-gb/evalcenter/download-windows-server-2022"
    Write-Host "  Specify with: -IsoPath `"C:\path\to\windows.iso`""
    Err "Windows ISO not found: $IsoPath"
}

Ok "All prerequisites found"
Ok "ISO: $IsoPath"

# Check prerequisites
# Note: packer-plugin-vmware (used by windows.pkr.hcl) drives VMware Workstation
# via vmrun.exe, not vmware-cmd (which is an ESX/ESXi tool and isn't installed by
# Workstation Pro at all).
function Find-AndAddToPath {
    param([string]$Cmd, [string[]]$Candidates)
    if (Get-Command $Cmd -ErrorAction SilentlyContinue) { return }
    foreach ($candidate in $Candidates) {
        $found = if ($candidate -like "*.exe") { $candidate } else {
            (Get-ChildItem -Path $candidate -Filter "$Cmd.exe" -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName)
        }
        if ($found -and (Test-Path $found)) {
            $dir = Split-Path -Parent $found
            Warn "$Cmd.exe found at $dir but not on PATH; adding it for this session"
            $env:Path = "$env:Path;$dir"
            return
        }
    }
}

# vmrun: installed by Workstation Pro but not added to PATH by default.
$vmrunInstallPath = $null
foreach ($key in @(
    "HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation",
    "HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation"
)) {
    $vmrunInstallPath = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).InstallPath
    if ($vmrunInstallPath) { break }
}
$vmrunCandidates = @(
    $(if ($vmrunInstallPath) { Join-Path $vmrunInstallPath "vmrun.exe" }),
    "C:\Program Files\VMware\VMware Workstation\vmrun.exe",
    "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
) | Where-Object { $_ }
Find-AndAddToPath -Cmd "vmrun" -Candidates $vmrunCandidates

# qemu-img: scoop's qemu package doesn't shim it, only the qemu-system-* binaries.
Find-AndAddToPath -Cmd "qemu-img" -Candidates @(
    "$env:USERPROFILE\scoop\apps\qemu\current",
    "D:\Users\LocalUser\scoop\apps\qemu\current"
)

$requiredCmds = @('packer', 'qemu-img', 'kubectl', 'vmrun')
foreach ($cmd in $requiredCmds) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Err "$cmd is not installed (or not on PATH)"
    }
}

# Build image with Packer
Log "Building Windows image with Packer (VMware)..."
Log "This will take 20-40 minutes depending on your machine."
Write-Host ""

# Clean previous builds
if (Test-Path (Join-Path $PackerDir "output-windows")) {
    Remove-Item (Join-Path $PackerDir "output-windows") -Recurse -Force
}
if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Initialize Packer plugins
Push-Location $PackerDir
Log "Initializing Packer plugins..."
packer init .

# Run Packer with ISO path override
Log "Running Packer build..."
packer build -var "iso_path=$IsoPath" windows.pkr.hcl

# Find the output VMDK
# VMware writes the disk as a small descriptor file (disk.vmdk) plus a series of
# split 2GB extent files (disk-s001.vmdk, disk-s002.vmdk, ...) since the template
# uses split-sparse disk type. qemu-img needs the descriptor, not a raw extent -
# exclude the "-sNNN" extent files rather than just taking the alphabetically
# first *.vmdk (which is an extent, since '-' sorts before '.').
$vmdkFiles = Get-ChildItem -Path (Join-Path $PackerDir "output-windows") -Filter "*.vmdk" -File |
    Where-Object { $_.Name -notmatch '-s\d+\.vmdk$' }
if (-not $vmdkFiles) {
    Err "No VMDK descriptor found in output-windows/"
}
$vmdk = $vmdkFiles[0].FullName
Ok "Packer build complete: $vmdk"

# Convert to QCOW2
Log "Converting VMDK to QCOW2..."
qemu-img convert -f vmdk -O qcow2 $vmdk $Qcow2File

# Show info
$size = (Get-Item $Qcow2File).Length
Ok "QCOW2 image created: $Qcow2File ($([math]::Round($size/1MB, 1))MB)"

Pop-Location

# Upload to Kubernetes via CDI DataVolume
Log "Uploading image to Kubernetes via CDI..."

# Check if CDI is installed
if (-not (kubectl get cdi cdi -n cdi 2>$null)) {
    Write-Host "  Install CDI: kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.61.0/cdi-operator.yaml"
    Write-Host "               kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.61.0/cdi-cr.yaml"
    Err "CDI operator not found in cluster"
}

# Create namespace
kubectl create namespace palworld-windows --dry-run=client -o yaml | kubectl apply -f -

# Create PVC
Log "Creating PVC..."
@'
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
'@ | kubectl apply -f -
Ok "PVC created"

# Upload using virtctl
if (Get-Command virtctl -ErrorAction SilentlyContinue) {
    Log "Using virtctl to upload image..."
    virtctl upload disk --image="$Qcow2File" --pvc=palworld-os-disk `
        --namespace=palworld-windows --size=40Gi --wait-secs=600
    Ok "Image uploaded via virtctl"
} else {
    Err "virtctl not found. Install from: https://github.com/kubevirt/kubevirt/releases"
}

# Wait for DataVolume to complete
Log "Waiting for DataVolume to complete..."
kubectl wait dv palworld-os-disk -n palworld-windows `
    --for=condition=Ready --timeout=30m
Ok "DataVolume ready"

# Deploy the VM
Log "Deploying VM..."
kubectl apply -f (Join-Path $BaseDir "apps\palworld-windows\vm.yaml")
Ok "VM manifest applied"

# Wait for VM to start
Log "Waiting for VM to start..."
kubectl wait vm palworld -n palworld-windows `
    --for=condition=Ready --timeout=10m 2>$null

Ok "VM deployed! Access via:"
Write-Host "  SSH:   kubectl port-forward svc/palworld-windows 2222:22 -n palworld-windows"
Write-Host "  VNC:   virtctl vnc palworld -n palworld-windows"

Write-Host ""
Log "=== Build Complete ==="
Ok "VM image: $Qcow2File"
Ok "VM name: palworld (namespace: palworld-windows)"
