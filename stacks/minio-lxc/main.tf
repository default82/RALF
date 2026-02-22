terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

provider "proxmox" {}

variable "node_name"        { type = string }
variable "vm_id"            { type = number }
variable "hostname"         { type = string }
variable "datastore_id"     { type = string }
variable "bridge"           { type = string }
variable "ipv4_address"     { type = string } # z.B. 10.10.40.20/16 oder /24
variable "ipv4_gateway"     { type = string }
variable "ssh_pubkey"       { type = string }
variable "template_file_id" { type = string } # z.B. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst

resource "proxmox_virtual_environment_container" "minio" {
  node_name    = var.node_name
  vm_id        = var.vm_id
  description  = "minio-svc (managed by RALF)"
  unprivileged = true
  started      = true
  start_on_boot = true

  features { nesting = true }

  initialization {
    hostname = var.hostname
    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }
    user_account {
      keys = [trimspace(var.ssh_pubkey)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.bridge
  }

  disk {
    datastore_id = var.datastore_id
    size         = 16
  }

  operating_system {
    type             = "ubuntu"
    template_file_id = var.template_file_id
  }
}

output "minio_ipv4" {
  value = proxmox_virtual_environment_container.minio.ipv4
}
