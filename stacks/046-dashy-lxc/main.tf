resource "proxmox_virtual_environment_container" "dashy" {
  node_name     = var.node_name
  vm_id         = 4050
  unprivileged  = true
  started       = true
  start_on_boot = true
  features {
    nesting = true
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = "dashy"

    ip_config {
      ipv4 {
        address = "10.10.40.50/16"
        gateway = "10.10.0.1"
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  operating_system {
    template_file_id = var.lxc_template_id
    type             = "ubuntu"
  }

  lifecycle {
    ignore_changes = [
      initialization,
      operating_system,
    ]
  }
}
