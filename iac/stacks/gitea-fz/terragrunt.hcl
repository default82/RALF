# ============================================================
# Gitea – Functional Zone
# OpenTofu Stack via Terragrunt
# ============================================================

# Root-Konfiguration einbinden
include "root" {
  path = find_in_parent_folders()
}

# --- Terraform Code Location + Hooks ---
terraform {
  source = "${get_terragrunt_dir()}/tofu"

  before_hook "check_dependencies" {
    commands = ["apply"]
    execute  = ["bash", "-c", "echo '==> Gitea Stack: Checking PostgreSQL dependency (10.10.20.10:5432)'"]
  }

  after_hook "post_apply" {
    commands = ["apply"]
    execute  = ["bash", "-c", "echo '==> Gitea Container deployed: CT 2012 (10.10.20.12:3000)'"]
  }
}

# --- Dependencies ---
# Gitea benötigt PostgreSQL als Backend
dependencies {
  paths = ["../postgresql-fz"]
}

# --- Stack-Specific Inputs ---
inputs = {
  # Aus functional.tfvars
  ct_id        = 2012
  hostname     = "svc-gitea"
  ip_address   = "10.10.20.12/16"

  # Resources
  cores     = 2
  memory    = 2048
  disk_size = 32

  # Zone
  zone = "functional"

  # Gitea-specific
  gitea_version = "1.22.6"
  gitea_http_port = 3000
  gitea_ssh_port  = 2222
}
