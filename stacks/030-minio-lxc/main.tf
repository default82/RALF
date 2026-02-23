resource "proxmox_virtual_environment_container" "minio" {
  node_name     = var.node_name
  vm_id         = 3010
  unprivileged  = true
  start_on_boot = true

  operating_system {
    template_file_id = "local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
    # ggf. auch nötig/gewünscht je nach Provider-Version:
    # type = "ubuntu"
  }

  cpu {
    cores = 1
    # architecture = "amd64"   # optional, falls du es explizit willst
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 32
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = "minio"

    ip_config {
      ipv4 {
        address = "10.10.30.10/16"
        gateway = "10.10.0.1"
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }
}
