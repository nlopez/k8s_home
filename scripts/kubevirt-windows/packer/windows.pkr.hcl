packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
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

source "qemu" "windows" {
  iso_checksum         = var.iso_checksum
  iso_url              = var.iso_path
  disk_size            = "40G"
  headless             = false
  floppy_files         = [
    "../files/Autounattend.xml",
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
  shutdown_command     = "a:/shutdown.bat"
  qemu_binary          = "qemu-system-x86_64"
  disk_interface       = "virtio"
  firmware             = "bios"
  machine_type         = "q35"
  headless             = false
  display_type         = "cocoa"
}

build {
  sources = ["source.qemu.windows"]

  provisioner "powershell" {
    elevated_password = "vagrant"
    elevated_user     = "vagrant"
    scripts           = [
      "../scripts/customise.ps1"
    ]
  }
}
