resource "proxmox_virtual_environment_container" "minio" {
  node_name    = var.node_name
  vm_id        = 3010
  unprivileged = true
  start_on_boot = true
  started       = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 2048
    swap      = 0
  }

  disk {
    datastore_id = "local-lvm"
    size         = 32
  }

  network_interface {
    bridge = "vmbr0"
    enabled = true
    name = "eth0"
  }

  operating_system {
    template_file_id = var.lxc_template_id
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
