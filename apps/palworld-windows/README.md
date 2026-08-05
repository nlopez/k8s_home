# Palworld Windows Server (Kubevirt)

Windows Server 2022 VM running Palworld Dedicated Server via SteamCMD.

## Architecture

- **VM**: Windows Server 2022 (4 vCPU, 16 GiB RAM)
- **Storage**:
  - OS disk: 80 GiB iSCSI (`nas1-mtank-iscsi`)
  - Game data: 20 GiB iSCSI (`nas1-mtank-iscsi`)
  - Save data: 1 GiB NFS (`nas1-mtank-nfs`)
- **Network**: NodePort (8211/UDP, 27015/UDP, 8212/TCP)
- **Backup**: Velero (10min, hourly, daily with REST API save hook)
- **Restart**: CronJob (daily 6:15 AM ET)

## Initial Setup (One-Time)

### 1. Apply manifests

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc-*.yaml
kubectl apply -f vm.yaml
```

### 2. Upload Windows Server 2022 ISO

```bash
virtctl image-upload pvc windows-iso-pvc --size 6Gi \
  --image-path=/path/to/en-us_windows_server_2022.iso \
  --insecure -n palworld-windows
```

> **Note**: You'll need to add the ISO PVC and CDROM to the VM manifest manually after upload.

### 3. Install Windows

```bash
# Start the VM
virtctl start palworld -n palworld-windows

# Connect via VNC
virtctl vnc palworld -n palworld-windows
```

Follow the Windows Server 2022 installation wizard.

### 4. Install VirtIO Drivers

After Windows install, attach the virtio-container-disk (already configured in the VM manifest) and install:
- `virtio-win-gt-x64.msi` (network, storage, and other drivers)
- `qemu-ga-x86_64.msi` (guest agent for Kubevirt)

### 5. Set up Palworld Server

Connect via RDP (`<node-ip>:30211` for the NodePort, or configure Tailscale):

```powershell
# 1. Install SteamCMD
Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile "C:\steamcmd.zip"
Expand-Archive -Path "C:\steamcmd.zip" -DestinationPath "C:\"

# 2. Download Palworld Dedicated Server
C:\steamcmd\steamcmd.exe +login anonymous +force_install_dir "C:\PalworldServer" +app_update 2394370 validate +quit

# 3. Create StartServer.bat
@"
@echo off
cd /d C:\PalworldServer
PalServer.exe -port=8211 -players=32 -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS
"@ | Out-File "C:\PalworldServer\StartServer.bat"

# 4. Create Windows Service
sc create "Palworld" binPath= "\"C:\PalworldServer\PalServer.exe\" -port=8211 -players=32 -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS" start= auto

# 5. Configure firewall
netsh advfirewall firewall add rule name="Palworld-Game" dir=in action=allow protocol=UDP localport=8211,27015
netsh advfirewall firewall add rule name="Palworld-REST" dir=in action=allow protocol=TCP localport=8212

# 6. Start the service
net start Palworld
```

### 6. Stop the VM

```bash
virtctl stop palworld -n palworld-windows
```

## Running the VM

```bash
# Start
virtctl start palworld -n palworld-windows

# Stop
virtctl stop palworld -n palworld-windows

# Check status
kubectl get vm palworld -n palworld-windows
kubectl get vmi -n palworld-windows -l app=palworld
```

## Access

- **Game**: `<node-ip>:30211` (UDP)
- **Query**: `<node-ip>:30015` (UDP)
- **REST API**: `<node-ip>:30212` (TCP)
- **RDP**: `<node-ip>:33389` (configure NodePort if needed)

## Maintenance

### Restart Server

The CronJob handles daily restarts at 6:15 AM ET. For manual restarts:

```bash
# Trigger save via REST API
curl http://<vm-pod-ip>:8212/save

# Stop and restart the VM
virtctl stop palworld -n palworld-windows
virtctl start palworld -n palworld-windows
```

### Edit Configuration

Edit `PalWorldSettings.ini` in the saved PVC:

```bash
# Mount the saved PVC to edit config
kubectl get pvc saved -n palworld-windows -o yaml
```

Or use the editor pattern from the container Palworld:
1. Scale up an editor pod with the saved PVC
2. Edit `PalWorldSettings.ini`
3. Scale down editor
4. Restart VM

### Backup

Velero schedules are configured for:
- Every 10 minutes (1h retention)
- Hourly (24h retention)
- Daily at 11:15 UTC (30 day retention, with REST API save hook)

## Troubleshooting

### VM won't start

```bash
# Check events
kubectl describe vm palworld -n palworld-windows
kubectl describe vmi -n palworld-windows -l app=palworld

# Check PVCs
kubectl get pvc -n palworld-windows
```

### Game server not responding

```bash
# Check if service is running
kubectl exec -it <vmi-pod> -n palworld-windows -- powershell "Get-Service Palworld"

# Check logs
kubectl logs -f <vmi-pod> -n palworld-windows
```

### RDP not working

```bash
# Check NodePort service
kubectl get svc palworld -n palworld-windows

# Check if port is open on node
nc -zv <node-ip> 30211
```

## Creating Template VMs (Optional)

If you want to create multiple VMs from a pre-built image, you can use CDI DataVolumes:

1. Build a Windows image with Packer + VirtualBox (see [rootisgod.com](https://www.rootisgod.com/2024/Running-Windows-VMs-in-Kubernetes-with-Kubevirt/))
2. Convert to QCOW2: `qemu-img convert -f vmdk -O qcow2 output.vmdk image.qcow2`
3. Host the QCOW2 file on a web server
4. Create a DataVolume pointing to the QCOW2 URL
5. Launch VMs from the DataVolume

This approach is useful for creating multiple identical VMs (e.g., multiple game servers) without repeating the Windows installation process.

## References

- [Kubevirt Windows VM Guide (Official)](https://kubevirt.io/2022/KubeVirt-installing_Microsoft_Windows_11_from_an_iso.html)
- [Running Windows VMs in Kubernetes with Kubevirt (rootisgod.com)](https://www.rootisgod.com/2024/Running-Windows-VMs-in-Kubernetes-with-Kubevirt/)
