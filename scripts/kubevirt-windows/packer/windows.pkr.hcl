packer {
  required_plugins {
    vmware = {
      source  = "github.com/vmware/packer-plugin-vmware"
      version = "~> 1.1"
    }
  }
}

variable "iso_path" {
  type    = string
  default = "~/Downloads/en-us_windows_server_2022.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:ca2154211cb277ade7139173f802b6098781faa2513a15bd51fee4b2246991ed"
}

source "vmware-iso" "windows" {
  iso_checksum         = var.iso_checksum
  iso_url              = var.iso_path
  disk_size            = "40960"
  guest_os_type        = "windows2022-64"
  headless             = false
  floppy_files         = [
    "../files/autounattend.xml",
    "../scripts/enable-winrm.ps1",
    "../scripts/shutdown.bat"
  ]
  vm_name              = "palworld-windows"
  cpus                 = 4
  memory               = 8192
  communicator         = "winrm"
  winrm_username       = "vagrant"
  winrm_password       = "vagrant"
  winrm_timeout        = "4h"
  winrm_use_ssl        = false
  winrm_insecure       = true
  shutdown_timeout     = "30m"
  shutdown_command     = "shutdown /s /t 10"
  # Apple Silicon requirements
  cd_adapter           = "sata"
  disk_adapter_type  = "sata"
  network_adapter      = "e1000e"
}

build {
  sources = ["source.vmware-iso.windows"]

  provisioner "powershell" {
    elevated_password = "vagrant"
    elevated_user     = "vagrant"
    scripts           = [
      "../scripts/customise.ps1"
    ]
  }
}
