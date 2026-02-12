# ============================================================
# Semaphore – Playground Zone
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
    execute  = ["bash", "-c", "echo '==> Semaphore Stack: Checking PostgreSQL dependency (10.10.20.10:5432)'"]
  }

  after_hook "post_apply" {
    commands = ["apply"]
    execute  = ["bash", "-c", "echo '==> Semaphore Container deployed: CT 10015 (10.10.100.15:3000)'"]
  }
}

# --- Dependencies ---
# Semaphore benötigt PostgreSQL als Backend
dependencies {
  paths = ["../postgresql-fz"]
}

# --- Stack-Specific Inputs ---
inputs = {
  # Aus playground.tfvars
  ct_id        = 10015
  hostname     = "ops-semaphore"
  ip_address   = "10.10.100.15/16"

  # Resources
  cores     = 2
  memory    = 2048
  disk_size = 16

  # Zone
  zone = "playground"

  # Semaphore-specific
  semaphore_version = "2.10.22"
  semaphore_port    = 3000
}
