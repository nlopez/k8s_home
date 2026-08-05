packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}

variable "iso_path" {
  type    = string
  default = "~/Downloads/en-us_windows_server_2022.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
}

source "virtualbox-iso" "windows" {
  vm_name              = "palworld-windows"
  communicator         = "winrm"
  floppy_files         = [
    "./files/Autounattend.xml",
    "./scripts/enable-winrm.ps1",
    "./scripts/shutdown.bat"
  ]
  guest_os_type        = "Windows2022_64"
  headless             = false
  iso_checksum         = var.iso_checksum
  iso_url              = var.iso_path
  disk_size            = "40960"
  shutdown_timeout     = "30m"
  cpus                 = 4
  memory               = 8192
  winrm_timeout        = "4h"
  winrm_username       = "vagrant"
  winrm_password       = "vagrant"
  winrm_use_ssl        = false
  winrm_insecure       = true
  keep_registered      = false
  vboxmanage           = [
    ["modifyvm", "{{ .Name }}", "--memory", "8192"],
    ["modifyvm", "{{ .Name }}", "--vram", "48"],
    ["modifyvm", "{{ .Name }}", "--cpus", "4"]
  ]
  shutdown_command     = "a:/shutdown.bat"
}

build {
  sources = ["source.virtualbox-iso.windows"]

  provisioner "powershell" {
    elevated_password = "vagrant"
    elevated_user     = "vagrant"
    scripts           = [
      "./scripts/customise.ps1"
    ]
  }
}
