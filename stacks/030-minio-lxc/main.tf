resource "proxmox_virtual_environment_container" "minio" {
  node_name     = var.node_name
  vm_id         = 3010
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

  operating_system {
    template_file_id = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    type             = "ubuntu"
  }

  # Imported legacy CTs can miss provider-state fields and force replacements.
  # Ignore immutable/create-time blocks during migration to Semaphore-managed runs.
  lifecycle {
    ignore_changes = [
      initialization,
      operating_system,
    ]
  }
}
