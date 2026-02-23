resource "proxmox_virtual_environment_container" "synapse" {
  node_name     = var.node_name
  vm_id         = 11010
  unprivileged  = true
  started       = true
  start_on_boot = true
  features {
    nesting = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
    swap      = 0
  }

  disk {
    datastore_id = "local-lvm"
    size         = 32
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = "synapse"

    ip_config {
      ipv4 {
        address = "10.10.110.10/16"
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
}
