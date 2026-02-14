# RALF Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete RALF homelab infrastructure from Phase 1-9, deploying core services (Vaultwarden, Mail) and creating IaC for all extended services.

**Architecture:** Hybrid-Waves approach - Foundation first (Phase 1 completion), then parallel Core Services deployment (Vaultwarden + Mail with full-stack), followed by parallel Extended Services IaC creation (9 services), and finally Orchestration layer for One-Liner deploy.

**Tech Stack:** OpenTofu 1.11+, Ansible 2.20+, Terragrunt 0.99+, Proxmox LXC, PostgreSQL 16, Bash 5+, Semaphore CI/CD

**Design Document:** `docs/plans/2026-02-14-ralf-completion-design.md`

---

## Wave 1: Foundation (Phase 1)

### Task 1: Generate Credentials

**Files:**
- Execute: `bootstrap/generate-credentials.sh`
- Creates: `/var/lib/ralf/credentials.env`

**Step 1: Verify script exists**

```bash
ls -lh bootstrap/generate-credentials.sh
```

Expected: File exists, executable

**Step 2: Run credential generator**

```bash
bash bootstrap/generate-credentials.sh
```

Expected: Creates `/var/lib/ralf/credentials.env` with 62 variables

**Step 3: Verify credentials file**

```bash
ls -l /var/lib/ralf/credentials.env
cat /var/lib/ralf/credentials.env | wc -l
```

Expected: File exists, 600 permissions, ~62+ lines

**Step 4: Source credentials to test**

```bash
source /var/lib/ralf/credentials.env
echo "Test: $POSTGRES_MASTER_PASS"
```

Expected: Variables loaded, passwords present

---

### Task 2: Gitea Web-UI Initial Setup

**Files:**
- Manual: Gitea Web-UI (http://10.10.20.12:3000)
- Verify: Gitea API

**Step 1: Verify Gitea is running**

```bash
curl -s http://10.10.20.12:3000/api/v1/version | jq
```

Expected: Version info returned

**Step 2: Access Web-UI and complete initial setup**

Manual Steps:
1. Open http://10.10.20.12:3000
2. Database: Use existing PostgreSQL settings
3. General Settings: Site Title "RALF Homelab"
4. Admin Account: kolja / kolja@homelab.lan / $KOLJA_GITEA_PASS
5. Click "Install Gitea"

**Step 3: Verify admin login**

```bash
curl -u kolja:$KOLJA_GITEA_PASS \
  http://10.10.20.12:3000/api/v1/user
```

Expected: User info for kolja returned

**Step 4: Create second admin account (ralf)**

Via Web-UI:
1. Login as kolja
2. Site Administration → User Accounts
3. Create New Account: ralf / ralf@homelab.lan / $RALF_GITEA_PASS
4. Check "Administrator"

**Step 5: Verify ralf account**

```bash
curl -u ralf:$RALF_GITEA_PASS \
  http://10.10.20.12:3000/api/v1/user
```

Expected: User info for ralf returned

**Step 6: Create Organization "RALF-Homelab"**

Via API:
```bash
curl -u kolja:$KOLJA_GITEA_PASS \
  -X POST http://10.10.20.12:3000/api/v1/orgs \
  -H "Content-Type: application/json" \
  -d '{
    "username": "RALF-Homelab",
    "description": "RALF Homelab Infrastructure",
    "visibility": "private"
  }'
```

Expected: Organization created, returns JSON

**Step 7: Verify organization exists**

```bash
curl -u kolja:$KOLJA_GITEA_PASS \
  http://10.10.20.12:3000/api/v1/orgs/RALF-Homelab
```

Expected: Organization info returned

---

### Task 3: Semaphore Second Admin Account

**Files:**
- Manual: Semaphore Web-UI (http://10.10.100.15:3000)

**Step 1: Verify Semaphore is running**

```bash
curl -s http://10.10.100.15:3000/api/ping
```

Expected: "pong" or similar response

**Step 2: Login as kolja and create ralf user**

Via Web-UI:
1. Open http://10.10.100.15:3000
2. Login as kolja
3. Team Settings → Users
4. Add User: ralf / ralf@homelab.lan / $RALF_SEMAPHORE_PASS
5. Role: Administrator

**Step 3: Verify ralf can login**

Manual: Login to Semaphore as ralf

Expected: Login successful, admin access visible

---

### Task 4: Semaphore SSH Keys Configuration

**Files:**
- Create: `/root/.ssh/ralf-ansible` (if not exists)
- Modify: Semaphore Key Store

**Step 1: Check if SSH key exists**

```bash
ls -l /root/.ssh/ralf-ansible*
```

If not exists, proceed to Step 2. If exists, skip to Step 4.

**Step 2: Generate SSH key pair**

```bash
ssh-keygen -t ed25519 \
  -f /root/.ssh/ralf-ansible \
  -C "ralf-ansible@homelab.lan" \
  -N ""
```

Expected: Key pair created

**Step 3: Verify key creation**

```bash
ls -lh /root/.ssh/ralf-ansible*
cat /root/.ssh/ralf-ansible.pub
```

Expected: Private and public keys exist

**Step 4: Add public key to all LXC containers**

```bash
for CTID in 2010 2012 10015; do
  echo "=== Container $CTID ==="
  pct exec $CTID -- bash -c "
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo '$(cat /root/.ssh/ralf-ansible.pub)' >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
  "
done
```

Expected: Public key added to all containers

**Step 5: Test SSH access**

```bash
ssh -i /root/.ssh/ralf-ansible root@10.10.20.10 "hostname"
ssh -i /root/.ssh/ralf-ansible root@10.10.20.12 "hostname"
ssh -i /root/.ssh/ralf-ansible root@10.10.100.15 "hostname"
```

Expected: All three connections successful, no password prompt

**Step 6: Add SSH key to Semaphore**

Via Web-UI:
1. Login to Semaphore
2. Key Store → New Key
3. Type: SSH
4. Name: "ralf-ansible"
5. Paste private key content from `/root/.ssh/ralf-ansible`
6. Save

**Step 7: Verify key in Semaphore**

Via Web-UI: Check Key Store, "ralf-ansible" should be listed

---

### Task 5: Semaphore Repository Connection

**Files:**
- Modify: Semaphore Projects

**Step 1: Add Git repository to Semaphore**

Via Web-UI:
1. Projects → New Project
2. Project Name: "RALF"
3. Repository URL: `ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git`
4. SSH Key: Select "ralf-ansible"
5. Branch: main
6. Create

**Step 2: Verify repository connection**

Via Web-UI: Project should show, no connection errors

**Step 3: Test repository pull**

Via Web-UI: Tasks → New Task → Select any playbook → Dry Run

Expected: Repository clones successfully

---

### Task 6: Semaphore Environment Variables

**Files:**
- Modify: Semaphore Environment (Project Settings)

**Step 1: Source credentials**

```bash
source /var/lib/ralf/credentials.env
```

**Step 2: Add Proxmox credentials to Semaphore**

Via Web-UI:
1. Project Settings → Environment
2. Add Variable: `PROXMOX_API_URL` = `https://10.10.10.10:8006/api2/json`
3. Add Secret: `PROXMOX_API_TOKEN_ID` = (value from credentials.env)
4. Add Secret: `PROXMOX_API_TOKEN_SECRET` = (value from credentials.env)

**Step 3: Add PostgreSQL credentials**

Add Variables:
- `POSTGRES_HOST` = `10.10.20.10`
- `POSTGRES_PORT` = `5432`
- `PG_SUPERUSER_PASS` = (secret, from credentials.env)

**Step 4: Add service database passwords**

Add Secrets:
- `SEMAPHORE_DB_PASS` = (from credentials.env)
- `GITEA_DB_PASS` = (from credentials.env)
- `VAULTWARDEN_DB_PASS` = (from credentials.env)
- `MAIL_DB_PASS` = (from credentials.env, if applicable)
- `NETBOX_DB_PASS` = (from credentials.env)
- `SYNAPSE_DB_PASS` = (from credentials.env)
- `N8N_DB_PASS` = (from credentials.env)

**Step 5: Add service admin passwords**

Add Secrets (Kolja):
- `KOLJA_GITEA_PASS`
- `KOLJA_GRAFANA_PASS`
- `KOLJA_NETBOX_PASS`
- `KOLJA_N8N_PASS`
- `KOLJA_SYNAPSE_PASS`
- `KOLJA_MAIL_PASS`

Add Secrets (Ralf):
- `RALF_GITEA_PASS`
- `RALF_GRAFANA_PASS`
- `RALF_NETBOX_PASS`
- `RALF_N8N_PASS`
- `RALF_SYNAPSE_PASS`
- `RALF_MAIL_PASS`

**Step 6: Add API tokens**

Add Secrets:
- `VAULTWARDEN_ADMIN_TOKEN`
- `NETBOX_SECRET_KEY`
- `SYNAPSE_REGISTRATION_SECRET`

**Step 7: Verify variables**

Via Web-UI: Project Settings → Environment
Expected: All variables and secrets listed

---

### Task 7: Repository Migration Finalization

**Files:**
- Verify: `.git/config`

**Step 1: Check current git remotes**

```bash
cd /root/ralf
git remote -v
```

Expected: origin points to Gitea, github-backup exists

**Step 2: Verify remote push works**

```bash
git pull origin main
```

Expected: Already up-to-date

**Step 3: Create migration note file**

```bash
cat > /root/ralf/MIGRATION.md <<'EOF'
# Repository Migration - GitHub → Gitea

**Datum:** 2026-02-12 (completed)
**Von:** https://github.com/default82/RALF.git
**Nach:** ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git

## Status: ✅ COMPLETED

## Änderungen:
- Git Remote "origin" zeigt auf Gitea (RALF-Homelab/ralf)
- GitHub-Remote "github-backup" (read-only backup)
- Alle Commits und Historie migriert
- Semaphore connected to Gitea repository

## Zugriff:
- **Gitea Web-UI:** http://10.10.20.12:3000/RALF-Homelab/ralf
- **Git Clone HTTPS:** http://10.10.20.12:3000/RALF-Homelab/ralf.git
- **Git Clone SSH:** ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git

## Credentials:
- Admin Users: kolja, ralf
- SSH Key: /root/.ssh/ralf-ansible
- Semaphore: Connected via SSH key

## Nächste Schritte:
- [x] Semaphore Git-Remote auf Gitea umgestellt
- [x] SSH-Keys für passwortlosen Zugriff eingerichtet
- [ ] GitHub-Repo auf read-only setzen (optional, später)
EOF
```

**Step 4: Commit migration note**

```bash
git add MIGRATION.md
git commit -m "docs: Repository migration completed

Migration von GitHub zu Gitea erfolgreich abgeschlossen.
Alle Services (Semaphore, lokale Entwicklung) nutzen Gitea als primary remote.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin main
```

Expected: Commit pushed to Gitea

---

### Task 8: Terragrunt Root Configuration

**Files:**
- Create: `iac/terragrunt.hcl`

**Step 1: Create root terragrunt.hcl**

```bash
cat > /root/ralf/iac/terragrunt.hcl <<'EOF'
# ============================================================================
# RALF Terragrunt Root Configuration
# ============================================================================
# Orchestriert alle OpenTofu-Stacks mit Dependencies
# Usage: terragrunt run-all plan|apply|destroy
# ============================================================================

# Remote State Configuration (local für jetzt, später Gitea)
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# Terraform Configuration
terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }
}

# Inputs für alle Child-Stacks
inputs = {
  # Proxmox Connection
  proxmox_api_url          = get_env("PROXMOX_API_URL", "https://10.10.10.10:8006/api2/json")
  proxmox_api_token_id     = get_env("PROXMOX_API_TOKEN_ID", "")
  proxmox_api_token_secret = get_env("PROXMOX_API_TOKEN_SECRET", "")

  # Network Configuration
  gateway           = "10.10.0.1"
  nameserver        = "10.10.0.1"
  searchdomain      = "homelab.lan"
  proxmox_node_name = "pve-deploy"

  # Storage
  storage_pool = "local-lvm"

  # Template
  template_name = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
EOF
```

**Step 2: Create stack-level terragrunt.hcl for postgresql-fz**

```bash
cat > /root/ralf/iac/stacks/postgresql-fz/terragrunt.hcl <<'EOF'
# PostgreSQL Stack Configuration
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./tofu"
}

dependencies {
  paths = []
}
EOF
```

**Step 3: Create stack-level terragrunt.hcl for semaphore-pg**

```bash
cat > /root/ralf/iac/stacks/semaphore-pg/terragrunt.hcl <<'EOF'
# Semaphore Stack Configuration
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./tofu"
}

dependency "postgresql" {
  config_path = "../postgresql-fz"
}

dependencies {
  paths = ["../postgresql-fz"]
}
EOF
```

**Step 4: Create stack-level terragrunt.hcl for gitea-fz**

```bash
cat > /root/ralf/iac/stacks/gitea-fz/terragrunt.hcl <<'EOF'
# Gitea Stack Configuration
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./tofu"
}

dependency "postgresql" {
  config_path = "../postgresql-fz"
}

dependencies {
  paths = ["../postgresql-fz"]
}
EOF
```

**Step 5: Test terragrunt configuration**

```bash
cd /root/ralf/iac
source /var/lib/ralf/credentials.env
terragrunt run-all validate
```

Expected: All stacks validate successfully

**Step 6: Test terragrunt plan (dry-run)**

```bash
cd /root/ralf/iac
terragrunt run-all plan --terragrunt-non-interactive
```

Expected: Plans for all 3 stacks, no errors (might show "no changes")

**Step 7: Commit Terragrunt configuration**

```bash
git add iac/terragrunt.hcl \
  iac/stacks/postgresql-fz/terragrunt.hcl \
  iac/stacks/semaphore-pg/terragrunt.hcl \
  iac/stacks/gitea-fz/terragrunt.hcl
git commit -m "feat: Terragrunt root configuration mit Dependencies

Root terragrunt.hcl orchestriert alle Stacks.
Stack-Dependencies:
- postgresql-fz: Basis (keine Dependencies)
- semaphore-pg: Abhängig von postgresql-fz
- gitea-fz: Abhängig von postgresql-fz

Usage: terragrunt run-all plan|apply

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin main
```

Expected: Commit pushed successfully

---

### Task 9: Wave 1 Validation

**Files:**
- Execute: Various validation commands

**Step 1: Validate Gitea setup**

```bash
echo "=== Gitea Validation ==="
curl -s http://10.10.20.12:3000/api/v1/version | jq
curl -u kolja:$KOLJA_GITEA_PASS http://10.10.20.12:3000/api/v1/user | jq .login
curl -u ralf:$RALF_GITEA_PASS http://10.10.20.12:3000/api/v1/user | jq .login
curl -u kolja:$KOLJA_GITEA_PASS http://10.10.20.12:3000/api/v1/orgs/RALF-Homelab | jq .username
```

Expected: All commands return valid data

**Step 2: Validate Semaphore setup**

```bash
echo "=== Semaphore Validation ==="
curl -s http://10.10.100.15:3000/api/ping
```

Manual: Check via Web-UI that both admins work, repository connected, variables set

**Step 3: Validate Terragrunt**

```bash
echo "=== Terragrunt Validation ==="
cd /root/ralf/iac
source /var/lib/ralf/credentials.env
terragrunt run-all validate
```

Expected: All validations pass

**Step 4: Validate Credentials**

```bash
echo "=== Credentials Validation ==="
test -f /var/lib/ralf/credentials.env && echo "✓ Credentials file exists"
test "$(stat -c %a /var/lib/ralf/credentials.env)" = "600" && echo "✓ Permissions correct (600)"
source /var/lib/ralf/credentials.env
test -n "$POSTGRES_MASTER_PASS" && echo "✓ Postgres password set"
test -n "$VAULTWARDEN_ADMIN_TOKEN" && echo "✓ Vaultwarden token set"
echo "Total credentials: $(grep -c export /var/lib/ralf/credentials.env)"
```

Expected: All checks pass, ~62 credentials

**Step 5: Create Wave 1 completion marker**

```bash
cat > /root/ralf/docs/WAVE1-COMPLETED.md <<'EOF'
# Wave 1 Completion Report

**Date:** $(date +%Y-%m-%d)
**Status:** ✅ COMPLETED

## Deliverables

### Gitea
- ✅ Web-UI Initial Setup abgeschlossen
- ✅ Admin-Accounts: kolja, ralf
- ✅ Organisation "RALF-Homelab" erstellt
- ✅ Repository erreichbar unter /RALF-Homelab/ralf

### Semaphore
- ✅ Zweiter Admin-Account (ralf) erstellt
- ✅ SSH-Key "ralf-ansible" generiert und hinterlegt
- ✅ Git-Repository verbunden (Gitea)
- ✅ Environment-Variablen gesetzt (Proxmox, DB-Passwords, Admin-Passwords, API-Tokens)

### Repository
- ✅ Migration von GitHub zu Gitea abgeschlossen
- ✅ Git-Remote "origin" zeigt auf Gitea
- ✅ Semaphore nutzt Gitea als Source

### Terragrunt
- ✅ Root-Konfiguration (iac/terragrunt.hcl) erstellt
- ✅ Stack-Dependencies definiert (postgresql → semaphore, gitea)
- ✅ `terragrunt run-all validate` erfolgreich

### Credentials
- ✅ generate-credentials.sh ausgeführt
- ✅ /var/lib/ralf/credentials.env erstellt (62 Variablen)
- ✅ Permissions: 600 (nur root)
- ✅ Alle Secrets in Semaphore hinterlegt

## Tests Passed
- ✅ Gitea API accessible
- ✅ Semaphore API accessible
- ✅ SSH-Key funktioniert für alle Container
- ✅ Terragrunt validates all stacks
- ✅ Credentials file loaded successfully

## Next: Wave 2 (Vaultwarden + Mail Deploy)
EOF

git add docs/WAVE1-COMPLETED.md
git commit -m "docs: Wave 1 Foundation completed

Alle Foundation-Tasks abgeschlossen:
- Gitea vollständig konfiguriert
- Semaphore mit Repository und Credentials verbunden
- Terragrunt orchestriert Stacks
- Credentials generiert und gesichert

Nächster Schritt: Wave 2 (Vaultwarden + Mail Deployment)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin main
```

Expected: Wave 1 completion documented and committed

---

## Wave 2: Core Services Deploy

### Task 10: Vaultwarden - OpenTofu Stack

**Files:**
- Create: `iac/stacks/vaultwarden-fz/tofu/versions.tf`
- Create: `iac/stacks/vaultwarden-fz/tofu/variables.tf`
- Create: `iac/stacks/vaultwarden-fz/tofu/main.tf`
- Create: `iac/stacks/vaultwarden-fz/tofu/outputs.tf`
- Create: `iac/stacks/vaultwarden-fz/env/functional.tfvars`
- Create: `iac/stacks/vaultwarden-fz/terragrunt.hcl`
- Create: `iac/stacks/vaultwarden-fz/README.md`

**Step 1: Create directory structure**

```bash
mkdir -p /root/ralf/iac/stacks/vaultwarden-fz/{tofu,env}
```

**Step 2: Write versions.tf**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/tofu/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure = true
  ssh {
    agent = true
  }
}
EOF
```

**Step 3: Write variables.tf**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/tofu/variables.tf <<'EOF'
# Proxmox Connection
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-deploy"
}

# Container Configuration
variable "ct_id" {
  description = "Container ID"
  type        = number
  default     = 3010
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "svc-vaultwarden"
}

variable "description" {
  description = "Container description"
  type        = string
  default     = "Vaultwarden Password Manager (Functional Zone)"
}

# Network Configuration
variable "ip_address" {
  description = "Static IP address with CIDR"
  type        = string
  default     = "10.10.30.10/16"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "10.10.0.1"
}

variable "nameserver" {
  description = "DNS server"
  type        = string
  default     = "10.10.0.1"
}

variable "searchdomain" {
  description = "DNS search domain"
  type        = string
  default     = "homelab.lan"
}

# Resources
variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 1024
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 8
}

# Storage
variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
  default     = "local-lvm"
}

variable "template_name" {
  description = "LXC template name"
  type        = string
  default     = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
EOF
```

**Step 4: Write main.tf**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/tofu/main.tf <<'EOF'
resource "proxmox_virtual_environment_container" "vaultwarden" {
  node_name = var.proxmox_node_name
  vm_id     = var.ct_id

  description = var.description
  tags        = ["ralf", "functional", "security", "vaultwarden"]

  # Operating System
  operating_system {
    template_file_id = "local:vztmpl/${var.template_name}"
    type             = "ubuntu"
  }

  # Resources
  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.storage_pool
    size         = var.disk_size
  }

  # Network
  network_interface {
    name = "eth0"
    firewall = false
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
      server  = var.nameserver
      domain  = var.searchdomain
    }
  }

  # Container Features
  features {
    nesting = true
    keyctl  = true
  }

  # Startup
  started    = true
  on_boot    = true
  unprivileged = true

  # Lifecycle
  lifecycle {
    ignore_changes = [
      disk,  # Prevent recreation on disk changes
      initialization,  # Prevent recreation on IP changes
    ]
  }
}
EOF
```

**Step 5: Write outputs.tf**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/tofu/outputs.tf <<'EOF'
output "ct_id" {
  description = "Container ID"
  value       = proxmox_virtual_environment_container.vaultwarden.vm_id
}

output "hostname" {
  description = "Container hostname"
  value       = proxmox_virtual_environment_container.vaultwarden.initialization[0].hostname
}

output "ip_address" {
  description = "Container IP address"
  value       = proxmox_virtual_environment_container.vaultwarden.initialization[0].ip_config[0].ipv4[0].address
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = "${proxmox_virtual_environment_container.vaultwarden.initialization[0].hostname}.homelab.lan"
}

output "url" {
  description = "Vaultwarden Web-UI URL"
  value       = "http://${split("/", proxmox_virtual_environment_container.vaultwarden.initialization[0].ip_config[0].ipv4[0].address)[0]}:8080"
}
EOF
```

**Step 6: Write functional.tfvars**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/env/functional.tfvars <<'EOF'
# Vaultwarden Functional Zone Configuration
ct_id       = 3010
hostname    = "svc-vaultwarden"
ip_address  = "10.10.30.10/16"
memory      = 1024
cores       = 2
disk_size   = 8
description = "Vaultwarden Password Manager (Functional Zone)"
EOF
```

**Step 7: Write terragrunt.hcl**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/terragrunt.hcl <<'EOF'
# Vaultwarden Stack Configuration
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "./tofu"
}

dependency "postgresql" {
  config_path = "../postgresql-fz"
}

dependencies {
  paths = ["../postgresql-fz"]
}

inputs = {
  # Values aus functional.tfvars werden automatisch geladen
}
EOF
```

**Step 8: Write README.md**

```bash
cat > /root/ralf/iac/stacks/vaultwarden-fz/README.md <<'EOF'
# Vaultwarden Stack (Functional Zone)

Vaultwarden ist ein Bitwarden-kompatibler Password Manager, implementiert in Rust.

## Container Specs

- **CT-ID:** 3010
- **Hostname:** svc-vaultwarden
- **IP:** 10.10.30.10
- **Zone:** Functional
- **Memory:** 1 GB
- **Disk:** 8 GB
- **Ports:** 8080 (HTTP)

## Dependencies

- PostgreSQL (10.10.20.10:5432)
- Datenbank: vaultwarden

## Deployment

```bash
cd /root/ralf/iac/stacks/vaultwarden-fz
source /var/lib/ralf/credentials.env

# Validate
terraform init
terraform validate

# Plan
terraform plan -var-file=env/functional.tfvars

# Apply
terraform apply -var-file=env/functional.tfvars

# Via Terragrunt
cd /root/ralf/iac
terragrunt run-all apply
```

## Post-Deployment

1. Ansible Role ausführen: `deploy-vaultwarden.yml`
2. Smoke Test: `bash tests/vaultwarden/smoke.sh`
3. Web-UI: http://10.10.30.10:8080
4. Admin-Panel: http://10.10.30.10:8080/admin (Token aus credentials.env)

## Rollback

```bash
pct rollback 3010 pre-install
pct start 3010
```
EOF
```

**Step 9: Validate OpenTofu configuration**

```bash
cd /root/ralf/iac/stacks/vaultwarden-fz/tofu
terraform init
terraform validate
```

Expected: "Success! The configuration is valid."

**Step 10: Test plan (dry-run)**

```bash
source /var/lib/ralf/credentials.env
terraform plan -var-file=../env/functional.tfvars
```

Expected: Plan shows container creation

**Step 11: Commit Vaultwarden Stack**

```bash
git add iac/stacks/vaultwarden-fz
git commit -m "feat: Vaultwarden OpenTofu Stack (Wave 2)

Full-Stack Component 1/7: IaC Stack

Container Specs:
- CT-ID: 3010
- IP: 10.10.30.10
- Memory: 1GB, Disk: 8GB
- Zone: Functional
- Dependency: PostgreSQL

Nächster Schritt: Ansible Role

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin main
```

Expected: Stack committed and pushed

---

### Task 11: Vaultwarden - Ansible Role

**Files:**
- Create: `iac/ansible/roles/vaultwarden/tasks/main.yml`
- Create: `iac/ansible/roles/vaultwarden/handlers/main.yml`
- Create: `iac/ansible/roles/vaultwarden/templates/vaultwarden.env.j2`
- Create: `iac/ansible/roles/vaultwarden/templates/vaultwarden.service.j2`
- Create: `iac/ansible/roles/vaultwarden/defaults/main.yml`

**Step 1: Create role directory structure**

```bash
mkdir -p /root/ralf/iac/ansible/roles/vaultwarden/{tasks,handlers,templates,defaults}
```

**Step 2: Write defaults/main.yml**

```bash
cat > /root/ralf/iac/ansible/roles/vaultwarden/defaults/main.yml <<'EOF'
---
# Vaultwarden Default Variables

vaultwarden_version: "1.32.7"
vaultwarden_user: "vaultwarden"
vaultwarden_group: "vaultwarden"
vaultwarden_home: "/var/lib/vaultwarden"
vaultwarden_config_dir: "/etc/vaultwarden"
vaultwarden_bin_path: "/usr/local/bin/vaultwarden"
vaultwarden_port: 8080

# Database (PostgreSQL)
vaultwarden_db_host: "10.10.20.10"
vaultwarden_db_port: 5432
vaultwarden_db_name: "vaultwarden"
vaultwarden_db_user: "vaultwarden"
vaultwarden_db_pass: ""  # From environment or vault

# Admin
vaultwarden_admin_token: ""  # From environment or vault
vaultwarden_domain: "https://vault.homelab.lan"

# Features
vaultwarden_signups_allowed: false
vaultwarden_invitations_allowed: true
vaultwarden_show_password_hint: false

# SMTP (optional, configured after Mail deployment)
vaultwarden_smtp_host: "10.10.40.10"
vaultwarden_smtp_port: 587
vaultwarden_smtp_from: "vaultwarden@homelab.lan"
vaultwarden_smtp_security: "starttls"
EOF
```

**Step 3: Write tasks/main.yml**

```bash
cat > /root/ralf/iac/ansible/roles/vaultwarden/tasks/main.yml <<'EOF'
---
# Vaultwarden Installation Tasks

- name: Install dependencies
  apt:
    name:
      - curl
      - sqlite3
      - ca-certificates
    state: present
    update_cache: yes

- name: Create vaultwarden user
  user:
    name: "{{ vaultwarden_user }}"
    system: yes
    home: "{{ vaultwarden_home }}"
    create_home: yes
    shell: /bin/bash
    state: present

- name: Create config directory
  file:
    path: "{{ vaultwarden_config_dir }}"
    state: directory
    owner: "{{ vaultwarden_user }}"
    group: "{{ vaultwarden_group }}"
    mode: '0755'

- name: Check if vaultwarden binary exists
  stat:
    path: "{{ vaultwarden_bin_path }}"
  register: vaultwarden_binary

- name: Download vaultwarden binary
  get_url:
    url: "https://github.com/dani-garcia/vaultwarden/releases/download/{{ vaultwarden_version }}/vaultwarden-{{ vaultwarden_version }}-linux-x86_64-musl.tar.gz"
    dest: "/tmp/vaultwarden.tar.gz"
    mode: '0644'
  when: not vaultwarden_binary.stat.exists

- name: Extract vaultwarden binary
  unarchive:
    src: "/tmp/vaultwarden.tar.gz"
    dest: "/tmp"
    remote_src: yes
  when: not vaultwarden_binary.stat.exists

- name: Install vaultwarden binary
  copy:
    src: "/tmp/vaultwarden"
    dest: "{{ vaultwarden_bin_path }}"
    owner: root
    group: root
    mode: '0755'
    remote_src: yes
  when: not vaultwarden_binary.stat.exists
  notify: restart vaultwarden

- name: Download web-vault
  get_url:
    url: "https://github.com/dani-garcia/bw_web_builds/releases/download/v2024.12.0/bw_web_v2024.12.0.tar.gz"
    dest: "/tmp/web-vault.tar.gz"
    mode: '0644'
  when: not vaultwarden_binary.stat.exists

- name: Extract web-vault
  unarchive:
    src: "/tmp/web-vault.tar.gz"
    dest: "{{ vaultwarden_home }}"
    owner: "{{ vaultwarden_user }}"
    group: "{{ vaultwarden_group }}"
    remote_src: yes
  when: not vaultwarden_binary.stat.exists

- name: Deploy vaultwarden configuration
  template:
    src: vaultwarden.env.j2
    dest: "{{ vaultwarden_config_dir }}/vaultwarden.env"
    owner: "{{ vaultwarden_user }}"
    group: "{{ vaultwarden_group }}"
    mode: '0600'
  notify: restart vaultwarden

- name: Deploy systemd service
  template:
    src: vaultwarden.service.j2
    dest: /etc/systemd/system/vaultwarden.service
    owner: root
    group: root
    mode: '0644'
  notify:
    - reload systemd
    - restart vaultwarden

- name: Enable and start vaultwarden
  systemd:
    name: vaultwarden
    enabled: yes
    state: started
    daemon_reload: yes

- name: Wait for vaultwarden to be ready
  wait_for:
    port: "{{ vaultwarden_port }}"
    delay: 2
    timeout: 30
EOF
```

**Step 4: Write handlers/main.yml**

```bash
cat > /root/ralf/iac/ansible/roles/vaultwarden/handlers/main.yml <<'EOF'
---
# Vaultwarden Handlers

- name: reload systemd
  systemd:
    daemon_reload: yes

- name: restart vaultwarden
  systemd:
    name: vaultwarden
    state: restarted
EOF
```

**Step 5: Write templates/vaultwarden.env.j2**

```bash
cat > /root/ralf/iac/ansible/roles/vaultwarden/templates/vaultwarden.env.j2 <<'EOF'
# Vaultwarden Configuration
# Managed by Ansible - Do not edit manually

## Database
DATABASE_URL=postgresql://{{ vaultwarden_db_user }}:{{ vaultwarden_db_pass }}@{{ vaultwarden_db_host }}:{{ vaultwarden_db_port }}/{{ vaultwarden_db_name }}

## Paths
DATA_FOLDER={{ vaultwarden_home }}
WEB_VAULT_FOLDER={{ vaultwarden_home }}/web-vault

## Network
ROCKET_ADDRESS=0.0.0.0
ROCKET_PORT={{ vaultwarden_port }}
DOMAIN={{ vaultwarden_domain }}

## Admin
ADMIN_TOKEN={{ vaultwarden_admin_token }}

## Features
SIGNUPS_ALLOWED={{ vaultwarden_signups_allowed | lower }}
INVITATIONS_ALLOWED={{ vaultwarden_invitations_allowed | lower }}
SHOW_PASSWORD_HINT={{ vaultwarden_show_password_hint | lower }}

## SMTP (optional)
{% if vaultwarden_smtp_host %}
SMTP_HOST={{ vaultwarden_smtp_host }}
SMTP_PORT={{ vaultwarden_smtp_port }}
SMTP_FROM={{ vaultwarden_smtp_from }}
SMTP_SECURITY={{ vaultwarden_smtp_security }}
{% endif %}

## Logging
LOG_FILE={{ vaultwarden_home }}/vaultwarden.log
LOG_LEVEL=info
EOF
```

**Step 6: Write templates/vaultwarden.service.j2**

```bash
cat > /root/ralf/iac/ansible/roles/vaultwarden/templates/vaultwarden.service.j2 <<'EOF'
[Unit]
Description=Vaultwarden Password Manager
Documentation=https://github.com/dani-garcia/vaultwarden
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User={{ vaultwarden_user }}
Group={{ vaultwarden_group }}
EnvironmentFile={{ vaultwarden_config_dir }}/vaultwarden.env
ExecStart={{ vaultwarden_bin_path }}
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={{ vaultwarden_home }}

[Install]
WantedBy=multi-user.target
EOF
```

**Step 7: Test Ansible syntax**

```bash
cd /root/ralf/iac/ansible
ansible-playbook --syntax-check roles/vaultwarden/tasks/main.yml
```

Expected: "playbook: roles/vaultwarden/tasks/main.yml"

**Step 8: Commit Vaultwarden Role**

```bash
git add iac/ansible/roles/vaultwarden
git commit -m "feat: Vaultwarden Ansible Role (Wave 2)

Full-Stack Component 2/7: Configuration Management

Features:
- Binary download + Web-Vault
- PostgreSQL-Backend
- Systemd service
- Idempotent installation
- Security hardening

Variables:
- vaultwarden_db_pass (from environment)
- vaultwarden_admin_token (from environment)

Nächster Schritt: Ansible Playbook

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin main
```

Expected: Role committed and pushed

---

**[NOTE: This plan continues with Tasks 12-50+ covering:]**

- Task 12: Vaultwarden Ansible Playbook
- Task 13: Vaultwarden Semaphore Pipeline
- Task 14: Vaultwarden Smoke Test
- Task 15: Vaultwarden Service Documentation
- Task 16: Vaultwarden Catalog Entry
- Task 17: Vaultwarden Deployment Execution
- Task 18-24: Mail Server (Maddy) - Full Stack (7 components)
- Task 25: Wave 2 Integration Tests
- Task 26: Credentials Migration to Vaultwarden
- Task 27-35: NetBox Full Stack
- Task 36-44: Snipe-IT Full Stack
- Task 45-53: Prometheus Full Stack
- Task 54-62: Grafana Full Stack
- Task 63-71: Loki Full Stack
- Task 72-80: Matrix/Synapse Full Stack
- Task 81-89: Element Full Stack
- Task 90-98: n8n Full Stack
- Task 99: Wave 3 Validation (all stacks syntax-checked)
- Task 100-105: Terragrunt One-Liner Orchestration
- Task 106-110: Master Pipeline (deploy-all.yml)
- Task 111-115: Comprehensive Test Suite
- Task 116: Wave 4 Validation
- Task 117: Project Completion Report

**Total Estimated Tasks: 117**
**Total Estimated Steps: 600+**

---

## Execution Strategy

Due to the massive scope, this plan should be executed in **checkpoint batches:**

### Checkpoint 1: Wave 1 (Tasks 1-9)
**Goal:** Foundation complete
**Duration:** 30-45 minutes
**Deliverables:** Gitea + Semaphore configured, Terragrunt working, Credentials generated

### Checkpoint 2: Wave 2 Part 1 - Vaultwarden (Tasks 10-17)
**Goal:** Vaultwarden fully deployed
**Duration:** 45-60 minutes
**Deliverables:** Vaultwarden running, Web-UI accessible, Admin accounts created

### Checkpoint 3: Wave 2 Part 2 - Mail (Tasks 18-24)
**Goal:** Mail server deployed
**Duration:** 45-60 minutes
**Deliverables:** Maddy running, SMTP/IMAP working, Test mail delivered

### Checkpoint 4: Wave 2 Completion (Tasks 25-26)
**Goal:** Integration + Migration
**Duration:** 20-30 minutes
**Deliverables:** Services communicate, Credentials in Vaultwarden

### Checkpoint 5-12: Wave 3 Services (Tasks 27-98)
**Goal:** All extended services as IaC
**Duration:** 4-6 hours (parallel creation possible)
**Deliverables:** 9 services × 7 components = 63 components as code

### Checkpoint 13: Wave 4 (Tasks 99-116)
**Goal:** Orchestration layer
**Duration:** 60-90 minutes
**Deliverables:** One-Liner deploy ready, Master pipeline, Test suite

### Checkpoint 14: Completion (Task 117)
**Goal:** Documentation and handoff
**Duration:** 15-20 minutes
**Deliverables:** Final report, metrics, success criteria validated

---

## Plan Completion

**Total Plan Size:** 117 Tasks, 600+ Steps
**Estimated Total Duration:** 8-12 hours (with parallelization)
**Checkpoints:** 14 major milestones
**Credit Usage:** High (expect 150k-180k tokens)

**This plan is saved to:** `docs/plans/2026-02-14-ralf-completion-plan.md`
