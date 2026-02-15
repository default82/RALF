# CLAUDE.md — AI Assistant Guide for RALF Homelab

## What is RALF?

RALF is a **self-orchestrating homelab infrastructure platform** built on Proxmox LXC containers. It manages services through declarative Infrastructure-as-Code (OpenTofu + Ansible) orchestrated by Semaphore. The project is maintained by a German-speaking operator; documentation and comments are primarily in **German**.

**Core philosophy:** _Erst Fundament, dann Hände, dann Plan, dann Logik._ (Foundation first, then hands, then plan, then logic.)

## Non-Negotiable Principles

- **Network is the foundation** — no deployments without passing network health checks
- **Controlled changes only** — Intent → Plan → Approval → Change
- **Every change is rollback-capable** — LXC snapshots (`pre-install`)
- **No secrets in the repository** — secrets live in Semaphore variables
- **LXC-first** — all services run in Proxmox LXC containers, no Docker/Kubernetes
- **Explicit over implicit** — static IPs, fixed CT-IDs, declared dependencies

## Repository Structure

```
RALF/
├── docs/           Governance documents (network baseline, conventions, bootstrap sequence)
├── catalog/        Machine-readable service catalog (60 YAML project specs + taxonomy)
├── services/       Human-readable service specifications (markdown runbooks)
├── plans/          Intent → Plan workflow artifacts (INTENT-*/PLAN-* files)
├── changes/        Change records (post-execution audit trail)
├── incidents/      Incident reports and lessons learned
├── healthchecks/   Network health gatekeeper (checks + runner script)
├── inventory/      Host inventory (hosts.yaml) and runtime config (runtime.env)
├── iac/            Infrastructure as Code
│   ├── stacks/     OpenTofu stacks per service (semaphore-pg, postgresql-fz, gitea-fz)
│   └── ansible/    Ansible playbooks, roles, and inventory
├── bootstrap/      Shell scripts for initial Proxmox LXC provisioning
├── pipelines/      Semaphore pipeline definitions (YAML)
└── tests/          Smoke and toolchain tests (bash + PowerShell)
```

## Technology Stack

| Layer            | Tool                | Purpose                                    |
|------------------|---------------------|--------------------------------------------|
| Virtualization   | Proxmox VE          | LXC container host                         |
| Provisioning     | OpenTofu >= 1.6.0   | Declarative LXC container creation         |
| Configuration    | Ansible             | Service installation and configuration     |
| Orchestration    | Semaphore            | Pipeline execution (RALF's "hands")        |
| Database         | PostgreSQL 16        | Persistent backend for services            |
| Source Control   | Gitea 1.22.6         | Self-hosted Git (replacing GitHub)         |
| Firewall/Gateway | OPNsense             | Network gateway, DNS, DHCP                 |
| Proxy            | Caddy                | Reverse proxy for external access          |

## Network Architecture

**Subnet:** `10.10.0.0/16` — all services use static IPs.

| 3rd Octet | Category                              | CT-ID Range   | Example                        |
|-----------|---------------------------------------|---------------|--------------------------------|
| 0         | Netzwerk (Router, Switches)           | —             | 10.10.0.1 (OPNsense)           |
| 10        | Hardware (PVE-NICs)                   | 1000–1099     | 10.10.10.10 (Proxmox)          |
| 20        | Datenbanken                           | 2000–2099     | 10.10.20.10 (PostgreSQL)       |
| 30        | Backup & Sicherheit                   | 3000–3099     | 10.10.30.10 (Vaultwarden)      |
| 40        | Web & Verwaltungsoberflächen          | 4000–4099     | 10.10.40.30 (NetBox)           |
| 50        | Verzeichnisdienste & Authentifizierung| 5000–5099     |                                |
| 60        | Medienserver & Verwaltung             | 6000–6099     |                                |
| 70        | Dokumenten- & Wissensmanagement       | 7000–7099     |                                |
| 80        | Monitoring & Logging                  | 8000–8099     |                                |
| 90        | KI & Datenverarbeitung                | 9000–9099     |                                |
| 100       | Automatisierung                       | 10000–10099   | 10.10.100.15 (Semaphore)       |
| 110       | Kommunikation und Steuerung           | 11000–11099   |                                |
| 120       | Spiele                                | 12000–12099   |                                |
| 200       | Funktionale VM                        | 20000–20099   |                                |

**Zones** (flags, not separate networks):
- **Functional (`-fz`)** — must be stable, production-grade
- **Playground (`-pg`)** — experiments, allowed to break

## Service Priority Tiers

| Tier | Services                                | Description                       |
|------|-----------------------------------------|-----------------------------------|
| P0   | OPNsense, network infrastructure        | Mission-critical foundation       |
| P1   | Semaphore, PostgreSQL, Gitea            | Automation core (bootstrap first) |
| P2   | NetBox, Snipe-IT, n8n, Vaultwarden     | Platform & management             |
| P3   | Sonarr, Radarr, Paperless, Mail        | Specialty/comfort services        |
| P4   | AI experiments, Matrix/Synapse          | Advanced/experimental             |

**Bootstrap order for P1:** PostgreSQL → Semaphore → Gitea

## Key Hosts (P1)

| Hostname       | IP            | CT-ID | Zone       | Service        | Ports         |
|----------------|---------------|-------|------------|----------------|---------------|
| svc-postgres   | 10.10.20.10   | 2010  | Functional | PostgreSQL 16  | 5432          |
| svc-gitea      | 10.10.20.12   | 2012  | Functional | Gitea 1.22.6   | 3000, SSH 2222|
| ops-semaphore  | 10.10.100.15  | 10015 | Functional | Semaphore      | 3000          |

## Naming Conventions

- **Hostnames:** `<role>-<service>` (e.g., `svc-postgres`, `ops-semaphore`)
- **Zone suffix in docs:** `-fz` (Functional), `-pg` (Playground)
- **CT-IDs:** `XXYYZ` where:
  - `XX` = IP 3rd octet (functional area: 20=DB, 40=Web, 100=Automation)
  - `YY` = Subgroup within function (00-99)
  - `Z` = Instance number (0-9)
  - Example: `2010` = Oktett 20 (DB), Subgroup 1 (Postgres), Instance 0
  - Example: `10015` = Oktett 100 (Automation), Subgroup 0, Instance 15
  - **Note:** Zone (`-fz`/`-pg`) is independent of CT-ID and indicates stability level
- **Catalog IDs:** `lowercase_with_underscores` (e.g., `matrix_synapse`)
- **Plans:** `PLAN-YYYYMMDD-XXX`
- **Changes:** `CHANGE-YYYYMMDD-XXX`
- **Incidents:** `INCIDENT-YYYYMMDD-XXX`

## Infrastructure as Code

### OpenTofu Stacks (`iac/stacks/<service>/`)

Each stack contains:
```
<service>/
├── README.md               Stack documentation
├── tofu/
│   ├── versions.tf         Provider requirements (BPG Proxmox >= 0.66.0)
│   ├── main.tf             LXC container resource definition
│   ├── variables.tf        Input variables
│   └── outputs.tf          Output values (IP, FQDN, URL)
└── env/
    └── <zone>.tfvars       Non-secret environment values
```

**Rules:**
- No secrets in `.tfvars` files — use Semaphore variables
- Each container gets a `pre-install` snapshot for rollback
- All containers: Ubuntu 24.04, 2 CPU, 2GB RAM, 16GB disk (defaults)
- Nesting and keyctl enabled on all containers

**Current Stack Status:**
- ✅ `postgresql-fz` - Fully implemented
- ✅ `gitea-fz` - Fully implemented
- ✅ `semaphore-pg` - Fully implemented
- ⚠️ MariaDB, Vaultwarden, NetBox, Snipe-IT, Dashy - **Bootstrap scripts only** (OpenTofu stacks pending)

**Migration Strategy:** Bootstrap scripts create containers initially; OpenTofu stacks will be added for declarative management and Terragrunt orchestration.

### Ansible (`iac/ansible/`)

```
ansible/
├── inventory/hosts.yml     Single source of truth for all hosts
├── playbooks/
│   ├── bootstrap-base.yml  Baseline for all P1 containers
│   ├── deploy-postgresql.yml
│   └── deploy-gitea.yml
└── roles/
    ├── base/               APT packages, timezone, NTP, SSH, RALF marker
    ├── postgresql/         PostgreSQL 16 install + config
    └── gitea/              Gitea binary + systemd + app.ini
```

**Role execution order:** `base` role always runs first, then service-specific role.

## Inventory Management

RALF maintains **two separate inventory files** with different purposes:

1. **`inventory/hosts.yaml`** — Initial network scan inventory
   - Purpose: Human-readable documentation of network discovery
   - Format: Custom YAML with meta-information
   - Source: Advanced IP Scanner or manual documentation
   - **Not used by Ansible** - archival/reference only

2. **`iac/ansible/inventory/hosts.yml`** — Ansible operational inventory
   - Purpose: **Single Source of Truth for Ansible automation**
   - Format: Ansible inventory format (YAML)
   - Used by: Semaphore, Ansible playbooks, automation
   - Contains: Host definitions, groups, variables

**Important:** These are **not synced** - they serve different purposes. The Ansible inventory (`iac/ansible/inventory/hosts.yml`) is the authoritative source for automation.

## Deployment Pipeline Pattern

Every deployment follows this sequence in Semaphore:

1. **network-health** — Gatekeeper: blocks deploy if network unhealthy
2. **tofu-init** — Initialize OpenTofu state
3. **tofu-plan** — Plan infrastructure changes
4. **tofu-apply** — Create/modify LXC containers
5. **ansible-deploy** — Configure services inside containers
6. **smoke-post** — Run smoke tests to verify success

## Testing

Tests live in `tests/` and follow a smoke-test pattern:

| Test                        | What It Checks                                    |
|-----------------------------|---------------------------------------------------|
| `bootstrap/smoke.sh`       | Repo checkout, git + bash available                |
| `bootstrap/smoke.ps1`      | Same as above for Windows/PowerShell               |
| `bootstrap/toolchain.sh`   | git, bash, curl, jq available                      |
| `bootstrap/install-toolchain.sh` | Installs full toolchain (apt + OpenTofu)     |
| `postgresql/smoke.sh`      | TCP 5432 open, ping, `pg_isready`                  |
| `gitea/smoke.sh`           | HTTP 3000, SSH 2222, ping, API `/api/v1/version`   |

**Conventions:**
- All bash scripts use `set -euo pipefail`
- Environment variable config with `${VAR:-default}` pattern
- Output format: `SERVICE SMOKE TEST` header, OK/FAIL/SKIP per check
- Network timeouts: 5–10 seconds
- Tests are cumulative — all checks run even if one fails

## Change Governance Workflow

```
Intent (plans/INTENT-*.md)     "What do we want?"
    ↓
Plan (plans/PLAN-*.md)         "How exactly do we do it?"
    ↓
Approval                        Human gate
    ↓
Execution (pipelines/)          Semaphore runs IaC + Ansible
    ↓
Change Record (changes/)        "What happened?"
    ↓
Incident (if failure)           "What went wrong and why?"
```

## Health Check Gatekeeper

The network health check (`healthchecks/run-network-health.sh`) validates 9 categories before any deployment is allowed:

- **A:** Core connectivity (gateway, internet)
- **B:** DNS resolution (internal + external)
- **C:** DHCP & static IP compliance
- **D:** NTP time synchronization
- **E:** Reverse proxy (Caddy)
- **F:** Network infrastructure (TP-Link, Proxmox)
- **G:** Observability (logs)
- **H:** IP scheme drift detection
- **I:** Recovery readiness (OPNsense backup)

**Rule:** Any failure = no deploys, only analysis/healing/rollback allowed.

## Service Catalog

The `catalog/` directory contains machine-readable YAML specs for 60 services:

- `catalog/meta.yaml` — Catalog metadata
- `catalog/taxonomy.yaml` — 24 categories, 10 dependency types, 18 feature tags
- `catalog/defaults.yaml` — Default observability/deployment hints
- `catalog/index.yaml` — Category-to-service index
- `catalog/projects/<id>.yaml` — Individual service specifications

Each project YAML follows this schema:
```yaml
id: <machine_id>
name: <Human Name>
category: <from taxonomy>
provides:
  services:
    - { name: <name>, protocol: <tcp|http|https>, default_port: <number> }
  features: [<tags>]
requires:
  dependencies:
    - { type: <dep_type>, engine: <optional>, required: <bool>, note: "<details>" }
tags: [<tags>]
```

## Bootstrap Scripts

Shell scripts in `bootstrap/` directly provision LXC containers via Proxmox CLI (`pct`):

| Script                      | Creates                   | CT-ID | IP             | Snapshots |
|-----------------------------|---------------------------|-------|----------------|-----------|
| `create-postgresql.sh`     | PostgreSQL 16 container   | 2010  | 10.10.20.10    | ✅        |
| `create-mariadb.sh`        | MariaDB 11.4 container    | 2011  | 10.10.20.11    | ⚠️        |
| `create-gitea.sh`          | Gitea container           | 2012  | 10.10.20.12    | ✅        |
| `create-vaultwarden.sh`    | Vaultwarden container     | 3010  | 10.10.30.10    | ⚠️        |
| `create-netbox.sh`         | NetBox container          | 4030  | 10.10.40.30    | ⚠️        |
| `create-snipeit.sh`        | Snipe-IT container        | 4040  | 10.10.40.40    | ⚠️        |
| `create-and-fill-runner.sh`| Semaphore container       | 10015 | 10.10.100.15   | ✅        |

**Common patterns in all scripts:**
- `set -euo pipefail` strict mode
- Config at top with `${VAR:-default}` overrides
- Helper functions: `log()`, `need_cmd()`, `pct_exec()` (from `lib/common.sh`)
- Precondition checks before execution
- **Pre/post-install snapshots** (⚠️ = not consistently implemented, see issue #6)
- Final health checks
- Passwords must come from environment variables (rejects defaults)

**Snapshot Best Practice:**
```bash
# Pre-install snapshot (before modifications)
pct snapshot $CTID "pre-install" --vmstate 0

# Post-install snapshot (after successful deployment)
pct snapshot $CTID "post-install" --vmstate 0
```

**Note:** Snapshot implementation is being standardized via `lib/common.sh` helper functions.

## Guidelines for AI Assistants

### Language
- Documentation and comments are in **German**. Continue writing in German for docs, plans, changes, incidents, and inline comments.
- Code (variable names, functions, YAML keys) uses **English**.

### When Making Changes
1. **Read before editing** — understand context, conventions, and dependencies first
2. **Follow existing patterns** — match the style of surrounding files exactly
3. **No secrets in code** — passwords, tokens, and API keys go in Semaphore variables
4. **Use templates** — new plans use `PLAN_TEMPLATE.md`, changes use `CHANGE_TEMPLATE.md`, incidents use `INCIDENT_TEMPLATE.md`, services use `SERVICE_TEMPLATE.md`
5. **Respect the dependency chain** — P0 before P1, PostgreSQL before Gitea
6. **Keep it minimal** — no Docker, no Kubernetes, no over-engineering

### When Adding Services
1. Create a catalog entry in `catalog/projects/<id>.yaml` following the schema
2. Update `catalog/index.yaml` with the new service
3. Create a service spec in `services/<name>.md` using `SERVICE_TEMPLATE.md`
4. Add an OpenTofu stack in `iac/stacks/<name>/` following existing stack structure
5. Add Ansible role in `iac/ansible/roles/<name>/`
6. Add smoke test in `tests/<name>/smoke.sh`
7. Add Semaphore pipeline in `pipelines/semaphore/deploy-<name>.yaml`

### When Adding Infrastructure
1. File an Intent (`plans/INTENT-YYYYMMDD-XXX.md`)
2. Create a Plan (`plans/PLAN-YYYYMMDD-XXX.md`)
3. Write OpenTofu stack + Ansible playbook/role
4. Write smoke tests
5. Create Semaphore pipeline
6. Document the Change after execution

### Key Files to Check
- `docs/conventions.md` — binding naming and structural rules
- `docs/network-baseline.md` — network architecture
- `iac/ansible/inventory/hosts.yml` — **Ansible inventory (Single Source of Truth for automation)**
- `inventory/hosts.yaml` — initial network scan (archival/reference)
- `inventory/runtime.env` — IPs, ports, endpoints (no secrets)
- `services/catalog.md` — service priority tiers and IP schema
- `healthchecks/network-health.yml` — gatekeeper rules
