# RALF Completion Design
**Datum:** 2026-02-14
**Autor:** Claude Sonnet 4.5
**Status:** Approved
**Typ:** Implementation Design

---

## Zusammenfassung

Vollständige Implementation aller fehlenden RALF-Komponenten von Phase 1 bis Phase 9. Hybrid-Ansatz mit 4 Waves: Foundation vervollständigen, Core Services deployen (Vaultwarden + Mail), Extended Services als Code erstellen, One-Liner-Deploy orchestrieren.

**Umfang:**
- 15+ Services (Full-Stack: IaC + Ansible + Pipelines + Tests + Docs)
- Phase 1-3: Deployment auf Proxmox
- Phase 4-9: Nur Infrastructure-as-Code
- Credential-Management: Generate → Vaultwarden-Migration

**Ressourcen:**
- System: 15 GB RAM, 81 GB Disk, 16 Cores ✅
- Arbeitsweise: Parallel mit Dependencies
- Vollständigkeit: Full-Stack Implementation

---

## 1. Architecture: Wave-Struktur

### Wave 1: Foundation (Phase 1)
**Ziel:** Bestehende P1-Services vollständig betriebsbereit machen

**Komponenten:**
- **Gitea Web-UI Setup:** Admin-Accounts (kolja, ralf), Organisation "RALF-Homelab"
- **Semaphore Config:** Zweiter Admin-Account, SSH-Keys, Repository-Anbindung, Environment-Variablen
- **Repo-Migration:** Git-Remote finalisieren, lokale Config aktualisieren
- **Terragrunt Root:** `iac/terragrunt.hcl` mit Stack-Dependencies
- **Credentials:** `generate-credentials.sh` ausführen → `/var/lib/ralf/credentials.env`

**Output:** Voll funktionsfähige Automatisierungs-Basis (Gitea + Semaphore + PostgreSQL)

---

### Wave 2: Core Services Deploy (Phase 2-3)
**Ziel:** Security & Communication deployed

**Parallel-Gruppen:**
- **Vaultwarden (CT 3010):** Full-Stack Implementation
- **Maddy Mail (CT 4010):** Full-Stack Implementation

**Deploy-Sequenz:**
1. Credentials aus `/var/lib/ralf/credentials.env` sourcen
2. Beide Services parallel deployen
3. Smoke-Tests ausführen
4. Credentials nach Vaultwarden migrieren
5. SMTP für bestehende Services konfigurieren

**Output:** Secrets-Management aktiv, interne Mail funktioniert

---

### Wave 3: Extended Services (Phase 4-9)
**Ziel:** Komplette IaC-Basis für alle weiteren Services

**Parallel-Gruppen nach Dependencies:**

**Gruppe A - Platform (Phase 6):**
- NetBox (CT 4012) - Asset Management
- Snipe-IT (CT 4014) - IT Asset Tracking
- Dependencies: Keine (können sofort erstellt werden)

**Gruppe B - Observability (Phase 5):**
- Prometheus (CT 8010) - Metrics
- Grafana (CT 8012) - Dashboards
- Loki (CT 8014) - Logs
- Dependencies: Phase 1-3 (brauchen Services zum Monitoren)

**Gruppe C - Communication (Phase 8):**
- Matrix/Synapse (CT 4030) - Chat Server
- Element (CT 4032) - Web Client
- Dependencies: Mail (für Notifications)

**Gruppe D - Automation (Phase 7):**
- n8n (CT 10020) - Workflow Engine
- Dependencies: Alle anderen Services (für Integrationen)

**WICHTIG:** Nur IaC-Code, keine Deployments

**Output:** 9 Services als produktionsreife IaC-Stacks

---

### Wave 4: Orchestration (Phase 9)
**Ziel:** One-Liner Deploy für gesamte Infrastruktur

**Komponenten:**
- Terragrunt `run-all` Orchestrierung
- Master-Pipeline in Semaphore (`deploy-all.yml`)
- Pre-Deploy Health-Checks (network-health erweitern)
- Post-Deploy Smoke-Tests (alle Services)
- Rollback-Mechanismus (Snapshot-basiert)

**Output:** `terragrunt run-all apply` deployed gesamtes RALF

---

### Dependencies-Graph
```
Wave 1 (Foundation)
    ↓
Wave 2 (Vaultwarden, Mail) - parallel
    ↓
Wave 3 - parallel nach Sub-Dependencies:
    ├─ Gruppe A (Platform) - keine Dependencies
    ├─ Gruppe B (Observability) - needs Wave 1-2
    ├─ Gruppe C (Communication) - needs Mail
    └─ Gruppe D (Automation) - needs all others
    ↓
Wave 4 (Orchestration)
```

---

## 2. Components: Full-Stack Definition

Jeder Service bekommt **7 Komponenten** nach CLAUDE.md Konventionen:

### 1. OpenTofu Stack (`iac/stacks/<service>-<zone>/`)
```
<service>-fz/  (oder -pg für Playground)
├── README.md              # Stack-Dokumentation
├── tofu/
│   ├── versions.tf        # Provider: BPG Proxmox >= 0.66.0
│   ├── variables.tf       # Inputs: ct_id, hostname, ip, gateway, memory, disk
│   ├── main.tf            # LXC Container Resource
│   └── outputs.tf         # IP, Hostname, URL
├── env/
│   └── functional.tfvars  # Non-secret values
└── terragrunt.hcl         # Dependencies + Remote State
```

**Standard-Container-Config:**
- Template: Ubuntu 24.04
- Memory: 1-2 GB (service-abhängig)
- Disk: 8-16 GB
- Unprivileged, nesting + keyctl enabled
- Static IP aus Netzwerk-Schema
- Pre-install Snapshot

---

### 2. Ansible Role (`iac/ansible/roles/<service>/`)
```
<service>/
├── tasks/main.yml         # Installation + Configuration
├── handlers/main.yml      # restart <service>
├── templates/
│   ├── config.j2          # Service-Konfiguration
│   └── service.j2         # Systemd Unit
├── files/                 # Static files (optional)
└── defaults/main.yml      # Default variables
```

**Standard-Tasks:**
1. Package installation oder Binary download
2. User creation (mit `common.sh` Library)
3. Directory setup
4. Configuration deployment (Templates mit Secrets)
5. Systemd service setup
6. Service enable + start
7. Health check

---

### 3. Ansible Playbook (`iac/ansible/playbooks/deploy-<service>.yml`)
```yaml
- name: Deploy <Service>
  hosts: <service-group>
  become: yes
  roles:
    - base                 # Immer zuerst
    - <service>            # Service-spezifisch
  vars:
    <service>_db_pass: "{{ lookup('env', 'SERVICE_DB_PASS') }}"
```

---

### 4. Semaphore Pipeline (`pipelines/semaphore/deploy-<service>.yaml`)
```yaml
version: v1.0
name: Deploy <Service>

blocks:
  - name: Network Health Check (Gatekeeper)
  - name: OpenTofu Init
  - name: OpenTofu Plan
  - name: OpenTofu Apply
  - name: Ansible Deploy
  - name: Smoke Test Post-Deploy
```

---

### 5. Smoke Test (`tests/<service>/smoke.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail

# Standard-Checks:
# 1. Ping-Check
# 2. TCP Port-Check (nc -zv)
# 3. HTTP/API-Check (curl)
# 4. Service-Status (pct exec systemctl is-active)

# Output: OK/FAIL/SKIP per Check
# Exit Code: 0 = all passed, 1 = any failed
```

---

### 6. Service-Steckbrief (`services/<service>.md`)
Basierend auf `SERVICE_TEMPLATE.md`:
- Kurzbeschreibung
- Technische Specs (Hostname, IP, Ports, CT-ID)
- Dependencies
- Konfiguration
- Betrieb (Start/Stop/Logs)
- Troubleshooting
- Backup-Strategie

---

### 7. Catalog-Eintrag (`catalog/projects/<service>.yaml`)
```yaml
id: <service_id>
name: <Human Name>
category: <from taxonomy>
provides:
  services:
    - name: <service>
      protocol: tcp|http|https
      default_port: <port>
  features: [<tags>]
requires:
  dependencies:
    - type: database
      engine: postgresql
      required: true
tags: [<priority>, <zone>]
```

**+ Update:** `catalog/index.yaml` mit neuem Service

---

## 3. Data Flow

### Credential-Fluss

**Phase 1: Initial Generation**
```
generate-credentials.sh
    ↓
/var/lib/ralf/credentials.env (600 permissions, nur root)
    ↓
source vor jedem Bootstrap-Script
    ↓
Container-Environment während Deployment
```

**Variablen (62 total):**
- PostgreSQL: 6 DB-Passwörter
- Admin-Accounts: kolja + ralf für alle Services (18 Passwörter)
- API-Tokens: 7 Service-Tokens
- Infrastructure: Proxmox API, SSH-Keys
- Server-Endpoints: IPs, Ports, URLs

**Phase 2: Migration nach Vaultwarden (nach Wave 2)**
```
/var/lib/ralf/credentials.env
    ↓
Manueller Import in Vaultwarden Web-UI
    ↓
Organisation "RALF Homelab" → Collections per Service
    ↓
Semaphore Environment zeigt auf Vaultwarden
```

**Phase 3: Vaultwarden-Integration (später)**
- Semaphore nutzt Vaultwarden API
- Keine Credentials aus Dateien
- Rotation über Vaultwarden UI

---

### Deployment-Fluss

**Standard Pattern:**
```
1. Terragrunt/OpenTofu
   ↓ erstellt Container

2. Pre-Install Snapshot
   ↓

3. Ansible Base Role
   ├─ APT packages
   ├─ Timezone + NTP
   ├─ SSH Keys
   └─ RALF-Marker
   ↓

4. Ansible Service Role
   ├─ Installation
   ├─ Configuration
   ├─ Systemd
   └─ Start
   ↓

5. Post-Install Snapshot
   ↓

6. Smoke Test
   ↓

7. Success → Inventory Update
   Failure → Rollback
```

---

### State Management

**OpenTofu State:**
- Local State: `terraform.tfstate` (pro Stack)
- Später: Remote State in Gitea

**Ansible State:**
- Keine State-Files (idempotent)
- Inventory als Single Source of Truth

**Inventory Updates nach Deployment:**
```yaml
# iac/ansible/inventory/hosts.yml
<service-group>:
  hosts:
    <hostname>:
      ansible_host: <ip>
      ralf_zone: functional|playground
      ralf_role: <service>
      ralf_ct_id: <ctid>
```

```bash
# inventory/runtime.env
<SERVICE>_IP=<ip>
<SERVICE>_PORT=<port>
```

---

### Database Provisioning

**PostgreSQL-Datenbanken werden automatisch erstellt:**

`provision-databases.yml` wird erweitert für:
- ✅ Semaphore (existiert)
- ✅ Gitea (existiert)
- 🆕 Vaultwarden
- 🆕 NetBox
- 🆕 Synapse
- 🆕 n8n

Pro Service:
```sql
CREATE USER <service> WITH PASSWORD '<pass>';
CREATE DATABASE <service> OWNER <service>;
GRANT ALL PRIVILEGES ON DATABASE <service> TO <service>;
```

---

### Network Health Gatekeeper

Alle Deployments werden blockiert bei Fehler in:
```
healthchecks/run-network-health.sh
    ↓
9 Kategorien (A-I):
    ├─ Core Connectivity
    ├─ DNS
    ├─ DHCP & Static IPs
    ├─ NTP
    ├─ Reverse Proxy
    ├─ Network Infra
    ├─ Observability
    ├─ IP Drift
    └─ Recovery Readiness
```

**Semaphore Pipelines:** Erste Block = network-health

---

## 4. Error Handling

### Snapshot-basierte Rollbacks

**Automatische Snapshots:**
```
Container erstellt
    ↓
Snapshot: "pre-install"
    ↓
Ansible ausführen
    ↓
Success → "post-install"
Failure → Rollback zu "pre-install"
```

**Rollback-Command:**
```bash
pct rollback <ctid> pre-install
pct start <ctid>
```

---

### Idempotenz-Prinzipien

Alle Scripts nutzen `bootstrap/lib/common.sh`:
- `container_exists()` - Check vor Erstellung
- `service_running_in_container()` - Überspringen wenn läuft
- `file_exists_in_container()` - Backup vor Overwrite
- `database_exists()` - Keine Duplikate
- `create_*_idempotent()` - Sichere Wiederholung

---

### Health-Check-Strategie

**Drei Ebenen:**

1. **Network-Level (Gatekeeper)**
   - `healthchecks/run-network-health.sh`
   - Blockiert alle Deployments bei Fehler

2. **Service-Level (Smoke Tests)**
   - Nach jedem Deployment
   - Ping, Port, HTTP, Service-Status

3. **Application-Level**
   - Service-spezifische API-Checks
   - `/api/alive`, `/api/version`, etc.

---

### Failure-Recovery

**Deployment-Fehler-Handling:**

| Phase | Fehler | Recovery |
|-------|--------|----------|
| OpenTofu | Container nicht erstellt | `pct destroy` + retry |
| Base Role | Partial Config | Rollback zu pre-install |
| Service Role | Service broken | Rollback (empfohlen) |
| Smoke Test | Service nicht erreichbar | Logs analysieren → Rollback |

**Credential-Fehler:**
```
credentials.env fehlt
    ↓
ERROR: "Run: bash bootstrap/generate-credentials.sh"
    ↓
Script stoppt
```

---

### Logging & Diagnostics

**Log-Locations:**
- Bootstrap: `/var/log/ralf-bootstrap.log`
- Ansible: Semaphore Output
- Services: `journalctl -u <service>`
- OpenTofu: `terraform.log`

**Diagnostic-Bundle bei Fehler:**
```bash
tar czf /tmp/diagnostic-<service>.tar.gz \
  /var/log/ralf-bootstrap.log \
  credentials.env.backup.* \
  terraform.tfstate \
  <(pct config <ctid>) \
  <(systemctl status <service>)
```

---

## 5. Testing Strategy

### Test-Pyramide

```
            ┌─────────────────┐
            │  End-to-End     │ One-Liner
            └─────────────────┘
          ┌───────────────────────┐
          │   Integration Tests   │ Service-zu-Service
          └───────────────────────┘
      ┌─────────────────────────────────┐
      │      Smoke Tests                │ Port, API, Status
      └─────────────────────────────────┘
  ┌─────────────────────────────────────────┐
  │        Syntax & Validation              │ bash -n, terraform validate
  └─────────────────────────────────────────┘
```

---

### Level 1: Syntax & Validation

**Vor jedem Commit:**
- `bash -n bootstrap/*.sh` - Bash Syntax
- `terraform validate` - OpenTofu Validation
- `ansible-playbook --syntax-check` - Ansible Syntax
- `yamllint` - YAML Linting

---

### Level 2: Smoke Tests

**Pro Service:** `tests/<service>/smoke.sh`

**Standard-Checks:**
1. Ping erreichbar
2. Port offen (nc -zv)
3. HTTP/API antwortet
4. Systemd service active

**Exit Codes:**
- 0 = alle Checks passed
- 1 = mindestens ein Check failed

**Wird ausgeführt:**
- Nach jedem Deployment
- In Semaphore Pipeline
- Manuell testbar

---

### Level 3: Integration Tests

**Service-zu-Service:**
- PostgreSQL → Service Connections
- SMTP Delivery (Mail → Services)
- Matrix → n8n Webhooks
- Grafana → Prometheus Data Source

**Wird ausgeführt:**
- Nach Wave 2
- Nach Wave 3
- Vor Wave 4

---

### Level 4: End-to-End

**One-Liner Deploy Test:**
```bash
# Vorbereitung:
- Snapshots aller Container
- terragrunt run-all plan
- ansible-playbook --check
- network-health validation

# Echter Deploy (optional):
- terragrunt run-all apply
- ansible deploy-all
- run-all-smoke-tests
```

---

### Testing-Workflow pro Wave

**Wave 1:** Git-Status, Semaphore Login, SSH-Keys, Terragrunt validate, Credentials

**Wave 2:** Syntax → Plan → Deploy → Smoke → Integration

**Wave 3:** Syntax → Validate → Dependency-Graph (KEINE Deployments)

**Wave 4:** run-all plan → Master-Pipeline → E2E Prep → Health-Check

---

### Test-Automatisierung

**Master-Script:** `tests/run-all-tests.sh`
- Level 1: Syntax Validation
- Level 2: Smoke Tests (deployed services)
- Level 3: Integration Tests
- Level 4: Network Health

**Ausführung:**
- Nach jedem Deployment
- Vor jedem git push
- Täglich via Cron (später)

---

## 6. Deliverables

### Wave 1 Deliverables
- [ ] Gitea Admin-Accounts + Organisation erstellt
- [ ] Semaphore vollständig konfiguriert
- [ ] Repo-Migration abgeschlossen
- [ ] `iac/terragrunt.hcl` erstellt
- [ ] `/var/lib/ralf/credentials.env` generiert
- [ ] Tests: Git API, Semaphore Login, SSH-Keys

### Wave 2 Deliverables
**Vaultwarden:**
- [ ] IaC Stack (`iac/stacks/vaultwarden-fz/`)
- [ ] Ansible Role (`iac/ansible/roles/vaultwarden/`)
- [ ] Playbook (`deploy-vaultwarden.yml`)
- [ ] Pipeline (`pipelines/semaphore/deploy-vaultwarden.yaml`)
- [ ] Smoke Test (`tests/vaultwarden/smoke.sh`)
- [ ] Service-Docs (`services/vaultwarden.md`)
- [ ] Catalog (`catalog/projects/vaultwarden.yaml`)
- [ ] Container deployed (CT 3010)
- [ ] Admin-Accounts (kolja, ralf)
- [ ] Credentials migriert

**Maddy Mail:**
- [ ] IaC Stack (`iac/stacks/mail-fz/`)
- [ ] Ansible Role (`iac/ansible/roles/maddy/`)
- [ ] Playbook (`deploy-mail.yml`)
- [ ] Pipeline (`pipelines/semaphore/deploy-mail.yaml`)
- [ ] Smoke Test (`tests/mail/smoke.sh`)
- [ ] Service-Docs (`services/mail.md`)
- [ ] Catalog (`catalog/projects/maddy.yaml`)
- [ ] Container deployed (CT 4010)
- [ ] Mail-Accounts (kolja, ralf)
- [ ] SMTP für Gitea/Semaphore konfiguriert

### Wave 3 Deliverables
**Pro Service (9 Services):**
- [ ] IaC Stack
- [ ] Ansible Role
- [ ] Playbook
- [ ] Pipeline
- [ ] Smoke Test
- [ ] Service-Docs
- [ ] Catalog-Eintrag

**Services:**
- [ ] NetBox (CT 4012)
- [ ] Snipe-IT (CT 4014)
- [ ] Prometheus (CT 8010)
- [ ] Grafana (CT 8012)
- [ ] Loki (CT 8014)
- [ ] Matrix/Synapse (CT 4030)
- [ ] Element (CT 4032)
- [ ] n8n (CT 10020)

**WICHTIG:** Nur Code, keine Deployments

### Wave 4 Deliverables
- [ ] `iac/terragrunt.hcl` run-all Config
- [ ] Master-Pipeline (`deploy-all.yml`)
- [ ] Pre-Deploy Health-Checks erweitert
- [ ] Post-Deploy Test-Suite (`run-all-smoke-tests.sh`)
- [ ] Rollback-Mechanismus dokumentiert
- [ ] E2E Test (`tests/e2e/one-liner-deploy.sh`)

---

## 7. Success Criteria

### Wave 1 Success
✅ Gitea: 2 Admins, Organisation "RALF-Homelab" existiert
✅ Semaphore: 2 Admins, SSH-Keys, Repo connected, Env-Vars gesetzt
✅ Terragrunt: `terragrunt run-all plan` funktioniert
✅ Credentials: 62 Variablen in `/var/lib/ralf/credentials.env`

### Wave 2 Success
✅ Vaultwarden: Web-UI erreichbar, Login funktioniert, API `/api/alive` OK
✅ Mail: SMTP Port 25+587 offen, IMAP 993 offen, Test-Mail zustellbar
✅ Integration: Gitea kann Mails versenden
✅ Migration: Alle Credentials in Vaultwarden gespeichert

### Wave 3 Success
✅ Alle 9 Services haben vollständige IaC-Stacks
✅ Alle Ansible Roles vorhanden und syntax-valid
✅ Alle Pipelines erstellt
✅ Alle Smoke-Tests geschrieben
✅ Alle Service-Docs + Catalog-Einträge vorhanden
✅ `terraform validate` passed für alle Stacks
✅ `ansible-playbook --syntax-check` passed für alle

### Wave 4 Success
✅ `terragrunt run-all plan` zeigt alle Services
✅ Master-Pipeline syntax-valid
✅ E2E Test (dry-run) erfolgreich
✅ Health-Checks erweitert
✅ Dokumentation: One-Liner-Deploy Anleitung

---

## 8. Timeline & Effort

**Geschätzte Wave-Größen:**
- Wave 1: ~15% (Foundation, Config)
- Wave 2: ~25% (2 Services full deploy)
- Wave 3: ~50% (9 Services nur Code)
- Wave 4: ~10% (Orchestration)

**Checkpoints:**
- Nach jeder Wave: Review & Validation
- Wave 2: Deployment-Tests kritisch
- Wave 3: Keine Deployments = weniger Fehleranfälligkeit
- Wave 4: Nur Vorbereitung, kein echter One-Liner-Deploy (auf Wunsch)

---

## 9. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Credential-Datei fehlt | Deployment blockt | Check + klare Fehlermeldung |
| Service startet nicht | Deployment failed | Rollback zu pre-install Snapshot |
| Resource-Knappheit | Container kann nicht erstellt werden | Ressourcen-Check vor jedem Deployment |
| Netzwerk-Fehler | Gatekeeper blockt | network-health vor jedem Deploy |
| Parallel-Konflikte | Race Conditions | Dependency-Graph strikt einhalten |
| Credits erschöpft | Projekt unvollständig | Checkpoints nach jeder Wave |

---

## 10. Nächste Schritte

Nach Approval dieses Designs:
1. ✅ Design-Dokument committed
2. 🔄 **Invoke writing-plans Skill** → Detaillierter Implementation Plan
3. 🚀 Execution des Plans (Wave für Wave)

---

**Erstellt:** 2026-02-14
**Approved:** 2026-02-14
**Nächster Schritt:** Implementation Planning
