# ============================================================
# RALF Terragrunt Root Configuration
# Shared configuration für alle OpenTofu Stacks
# ============================================================

# --- Local State (für Phase 1) ---
# TODO: Später auf S3-kompatiblen Remote State umstellen (MinIO)
locals {
  # Root-Pfad für alle Stacks
  root_dir = get_terragrunt_dir()

  # Parse Stack-Name aus Verzeichnis (z.B. "postgresql-fz")
  stack_name = basename(get_terragrunt_dir())

  # Common tags für alle Ressourcen
  common_tags = {
    managed_by = "ralf-terragrunt"
    repository = "RALF-Homelab/ralf"
    branch     = "main"
  }
}

# --- Remote State Configuration ---
# Lokaler State für jetzt, wird in Phase 2 auf MinIO umgestellt
remote_state {
  backend = "local"

  config = {
    path = "${get_parent_terragrunt_dir()}/terraform.tfstate.d/${path_relative_to_include()}/terraform.tfstate"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# --- Provider Configuration ---
# Wird in allen Stacks generiert
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
  required_version = ">= 1.6.0"
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent = false
  }
}
EOF
}

# --- Common Inputs ---
# Diese Werte werden an alle Child-Stacks weitergegeben
inputs = {
  # Proxmox Connection (aus Environment Variables)
  proxmox_api_url   = get_env("PROXMOX_API_URL", "https://10.10.10.10:8006/api2/json")
  proxmox_api_token = get_env("PROXMOX_API_TOKEN", "")
  proxmox_insecure  = true

  # Common Network Settings
  gateway       = "10.10.0.1"
  dns_server    = "10.10.0.1"
  search_domain = "homelab.lan"
  bridge        = "vmbr0"

  # Proxmox Node
  proxmox_node = "pve-deploy"

  # Template
  template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

  # Storage
  disk_storage = "local-lvm"
}

# --- Terragrunt Hooks ---
# Extra arguments für Terraform/OpenTofu
# Hinweis: Diese werden beim Aufruf von tofu/terraform automatisch angehängt
