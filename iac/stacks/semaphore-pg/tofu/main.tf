# ============================================================
# Semaphore LXC – Playground Zone
# RALF Homelab – P1 Automation Runner
# ============================================================

resource "proxmox_virtual_environment_container" "semaphore" {
  node_name   = var.proxmox_node
  vm_id       = var.ct_id
  description = "Semaphore ${var.semaphore_version} – RALF Runner (${var.zone})"

  tags = ["ralf", "p1", var.zone, "automation"]

  unprivileged  = true
  start_on_boot = true

  operating_system {
    template_file_id = var.template
    type             = "ubuntu"
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.disk_storage
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.dns_server]
      domain  = var.search_domain
    }
  }

  features {
    nesting = true
    keyctl  = true
  }

  lifecycle {
    ignore_changes = [
      operating_system,
    ]
  }
}

# --- Snapshot before any configuration ---
resource "proxmox_virtual_environment_container_snapshot" "pre_install" {
  node_name     = var.proxmox_node
  container_id  = proxmox_virtual_environment_container.semaphore.vm_id
  snapshot_name = "pre-install"
  description   = "Snapshot vor Semaphore-Installation"
}
