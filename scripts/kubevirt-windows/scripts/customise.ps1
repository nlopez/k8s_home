# ============================================================
# Palworld Windows VM Customisation Script
# Pre-installs SteamCMD, enables SSH/WinRM, installs virtio
# ============================================================

Write-Host "=== Palworld Windows VM Customisation ===" -ForegroundColor Cyan

# ----------------------------------------------------------
# 1. Quality of Life Settings
# ----------------------------------------------------------
Write-Host "[1/7] Configuring QoL settings..." -ForegroundColor Yellow

# Show file extensions
reg.exe ADD HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced `
    /v HideFileExt /t REG_DWORD /d 0 /f > $null

# Enable QuickEdit in console
reg.exe ADD HKCU\Console /v QuickEdit /t REG_DWORD /d 1 /f > $null

# Show Run in Start menu
reg.exe ADD HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced `
    /v Start_ShowRun /t REG_DWORD /d 1 /f > $null

# Disable hibernation
reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power `
    /v HibernateFileSizePercent /t REG_DWORD /d 0 /f > $null
reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power `
    /v HibernateEnabled /t REG_DWORD /d 0 /f > $null

# Enable RDP
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" `
    /v fDenyTSConnections /t REG_DWORD /d 0 /f > $null
netsh advfirewall firewall set rule group="remote desktop" new enable=yes > $null

# ----------------------------------------------------------
# 2. Enable PowerShell Remoting (SSH alternative)
# ----------------------------------------------------------
Write-Host "[2/7] Enabling PowerShell remoting..." -ForegroundColor Yellow

# Set execution policy
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

# Enable PSRemoting
Enable-PSRemoting -Force -ErrorAction SilentlyContinue

# Configure WinRM for local access
winrm quickconfig -q -force 2>$null
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="120"}'

# Configure firewall for WinRM
netsh advfirewall firewall add rule name="WinRM-HTTP" `
    dir=in action=allow protocol=TCP localport=5985 > $null 2>&1
netsh advfirewall firewall add rule name="WinRM-HTTPS" `
    dir=in action=allow protocol=TCP localport=5986 > $null 2>&1

Set-Service winrm -startuptype "auto"
Restart-Service winrm -Force

# ----------------------------------------------------------
# 3. Install OpenSSH Server (for SSH access)
# ----------------------------------------------------------
Write-Host "[3/7] Installing OpenSSH Server..." -ForegroundColor Yellow

# Check if OpenSSH is already installed
$sshInstalled = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
if ($sshInstalled.State -ne "Installed") {
    Add-WindowsCapability -Online -Name $sshInstalled.Name | Out-Null
    Write-Host "  OpenSSH Server installed." -ForegroundColor Green
} else {
    Write-Host "  OpenSSH Server already installed." -ForegroundColor Gray
}

# Configure and start SSH service
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

# Allow SSH through firewall
netsh advfirewall firewall add rule name="OpenSSH-Server" `
    dir=in action=allow protocol=TCP localport=22 > $null 2>&1

# Generate host keys if they don't exist
if (-not (Test-Path "C:\ProgramData\ssh\ssh_host_rsa_key")) {
    ssh-keygen -A
}

# ----------------------------------------------------------
# 4. Install Chocolatey
# ----------------------------------------------------------
Write-Host "[4/7] Installing Chocolatey..." -ForegroundColor Yellow

Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Refresh environment
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# ----------------------------------------------------------
# 5. Install SteamCMD via Chocolatey
# ----------------------------------------------------------
Write-Host "[5/7] Installing SteamCMD..." -ForegroundColor Yellow

choco install steamcmd -y --no-progress | Out-Null

# Verify installation
if (Test-Path "C:\Program Files (x86)\Steam\steamcmd.exe") {
    Write-Host "  SteamCMD installed successfully." -ForegroundColor Green
} else {
    Write-Host "  SteamCMD not found, downloading manually..." -ForegroundColor Yellow
    $steamcmdUrl = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_latest.tar.gz"
    $steamcmdDest = "C:\steamcmd"
    New-Item -ItemType Directory -Path $steamcmdDest -Force | Out-Null
    
    # Download and extract SteamCMD
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $steamcmdUrl -OutFile "$steamcmdDest\steamcmd.tar.gz"
    tar -xzf "$steamcmdDest\steamcmd.tar.gz" -C $steamcmdDest
    Remove-Item "$steamcmdDest\steamcmd.tar.gz" -Force
    
    Write-Host "  SteamCMD installed to $steamcmdDest" -ForegroundColor Green
}

# Create a startup script for SteamCMD
$steamStartupPath = "C:\ProgramData\steamcmd-startup.ps1"
@"
# SteamCMD auto-start script for Palworld
# Run this to update/download the Palworld dedicated server
\$steamcmdPath = "C:\Program Files (x86)\Steam\steamcmd.exe"
if (-not (Test-Path \$steamcmdPath)) {
    \$steamcmdPath = "C:\steamcmd\steamcmd.exe"
}

# Login anonymously and install Palworld
& \$steamcmdPath +@force_install_dir C:\palworld-server +login anonymous +app_update 2394370 validate +quit
"@ | Out-File -FilePath $steamStartupPath -Encoding utf8

Write-Host "  Created SteamCMD startup script at $steamStartupPath" -ForegroundColor Green

# ----------------------------------------------------------
# 6. Create Palworld server directory structure
# ----------------------------------------------------------
Write-Host "[6/7] Creating Palworld server directories..." -ForegroundColor Yellow

$palworldDir = "C:\palworld-server"
New-Item -ItemType Directory -Path $palworldDir -Force | Out-Null
New-Item -ItemType Directory -Path "$palworldDir\Saved" -Force | Out-Null

# Create a default StartServer.bat
@"
@echo off
cd /d %~dp0
PalServer.exe -server -listen
pause
"@ | Out-File -FilePath "$palworldDir\StartServer.bat" -Encoding ascii

Write-Host "  Palworld server directory created at $palworldDir" -ForegroundColor Green

# ----------------------------------------------------------
# 7. Install virtio drivers
# ----------------------------------------------------------
Write-Host "[7/7] Installing virtio drivers..." -ForegroundColor Yellow

$virtioUrl = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win-guest-tools.exe"
$virtioDest = "C:\virtio-win-guest-tools.exe"

try {
    Invoke-WebRequest -Uri $virtioUrl -OutFile $virtioDest -UseBasicParsing
    Start-Process -FilePath $virtioDest -ArgumentList "/S" -Wait -NoNewWindow
    Remove-Item $virtioDest -Force -ErrorAction SilentlyContinue
    Write-Host "  virtio drivers installed." -ForegroundColor Green
} catch {
    Write-Host "  Could not download virtio drivers: $_" -ForegroundColor Red
    Write-Host "  You can install them manually later." -ForegroundColor Gray
}

# ----------------------------------------------------------
# Done
# ----------------------------------------------------------
Write-Host ""
Write-Host "=== Customisation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Available access methods:" -ForegroundColor White
Write-Host "  - RDP:   <vm-ip>:3389" -ForegroundColor White
Write-Host "  - SSH:   ssh vagrant@<vm-ip>" -ForegroundColor White
Write-Host "  - WinRM: Enter-PSSession -ComputerName <vm-ip>" -ForegroundColor White
Write-Host ""
Write-Host "Installed software:" -ForegroundColor White
Write-Host "  - SteamCMD: C:\Program Files (x86)\Steam\steamcmd.exe" -ForegroundColor White
Write-Host "  - virtio drivers" -ForegroundColor White
Write-Host ""
