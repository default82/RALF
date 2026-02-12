# ============================================================
# PostgreSQL – Functional Zone
# OpenTofu Stack via Terragrunt
# ============================================================

# Root-Konfiguration einbinden
include "root" {
  path = find_in_parent_folders()
}

# --- Terraform Code Location + Hooks ---
terraform {
  source = "${get_terragrunt_dir()}/tofu"

  before_hook "backup_check" {
    commands = ["apply"]
    execute  = ["bash", "-c", "echo '==> PostgreSQL Stack: Pre-apply check'"]
  }

  after_hook "post_apply" {
    commands = ["apply"]
    execute  = ["bash", "-c", "echo '==> PostgreSQL Container deployed: CT 2010 (10.10.20.10)'"]
  }
}

# --- Dependencies ---
# PostgreSQL hat keine Dependencies (Foundation Service)
dependencies {
  paths = []
}

# --- Stack-Specific Inputs ---
inputs = {
  # Aus functional.tfvars
  ct_id        = 2010
  hostname     = "svc-postgres"
  ip_address   = "10.10.20.10/16"

  # Resources
  cores     = 2
  memory    = 2048
  disk_size = 16

  # Zone
  zone       = "functional"
  pg_version = 16
}
