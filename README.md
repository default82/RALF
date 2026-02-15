# 🏠 RALF Homelab

> **Self-orchestrating homelab infrastructure platform**
> _Erst Fundament, dann Hände, dann Plan, dann Logik._

RALF ist eine selbstorchestrierende Homelab-Infrastruktur auf Basis von Proxmox LXC Containern. Alle Änderungen folgen einem kontrollierten Workflow: **Intent → Plan → Approval → Change**.

[![Gitea](https://img.shields.io/badge/Gitea-1.22.6-609926?logo=gitea)](http://10.10.20.12:3000)
[![Semaphore](https://img.shields.io/badge/Semaphore-2.16.51-orange)](http://10.10.100.15:3000)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](http://10.10.20.10:5432)
[![Dashboard](https://img.shields.io/badge/Dashy-Dashboard-00af87)](http://10.10.40.11:4000)

---

## 🚀 Quick Start

### Access Services

```bash
# Services
Gitea:     http://10.10.20.12:3000      (kolja / ralf)
Semaphore: http://10.10.100.15:3000     (kolja / ralf)
PostgreSQL: 10.10.20.10:5432            (postgres)
MariaDB:    10.10.20.11:3306            (root)
MinIO:      http://10.10.20.13:9000    (admin)
Proxmox:    https://10.10.10.10:8006    (root)

# Credentials
cat /var/lib/ralf/credentials.env
```

### Fresh Bootstrap

```bash
# 1. Generate Credentials
bash bootstrap/generate-credentials.sh > /var/lib/ralf/credentials.env
source /var/lib/ralf/credentials.env

# 2. Wave 1: Core Infrastructure
bash bootstrap/create-postgresql.sh   # CT 2010
bash bootstrap/create-mariadb.sh      # CT 2011
bash bootstrap/create-minio.sh        # CT 2013

# 3. Wave 2: Automation Core
bash bootstrap/create-gitea.sh        # CT 2012
bash bootstrap/create-and-fill-runner.sh  # CT 10015
```

---

## 📊 Status

**Current State:** Wave 2 Complete (2026-02-15)

### ✅ Wave 1: Core Infrastructure

| Service | CT-ID | IP | Port | Status |
|---------|-------|-----|------|--------|
| **PostgreSQL 16** | 2010 | 10.10.20.10 | 5432 | ✅ Running |
| **MariaDB 11.4** | 2011 | 10.10.20.11 | 3306 | ✅ Running |
| **MinIO** | 2013 | 10.10.20.13 | 9000, 9001 | ✅ Running |

### ✅ Wave 2: Automation Core

| Service | CT-ID | IP | Port | Status |
|---------|-------|-----|------|--------|
| **Gitea 1.22.6** | 2012 | 10.10.20.12 | 3000, 2222 | ✅ Running |
| **Semaphore 2.16.51** | 10015 | 10.10.100.15 | 3000 | ✅ Running |

### ⏳ Pending Deployment

| Service | CT-ID | IP | Priority | Wave |
|---------|-------|-----|----------|------|
| **Dashy** | 4001 | 10.10.40.11 | P1 | - |
| **Vaultwarden** | 3010 | 10.10.30.10 | P2 | 3 |
| **NetBox** | 4030 | 10.10.40.30 | P2 | 3 |
| **Snipe-IT** | 4040 | 10.10.40.40 | P2 | 3 |
| **n8n** | 4012 | 10.10.40.12 | P2 | 3 |

**Admin Users:** `kolja` + `ralf` (für alle Services)

### 📈 Resource Usage

- **RAM:** 2.6GB / 16GB (16% used)
- **Disk:** 7.9GB / 94GB (8% used)
- **Containers:** 5 deployed (Wave 1+2)
- **Headroom:** 84% RAM, 92% Disk available

### 📋 Geplant

- **P2:** Vaultwarden, NetBox, Snipe-IT
- **P3:** n8n, Matrix, Mail, Media-Server
- **P4:** Ollama AI, Monitoring (Prometheus, Grafana, Loki)

---

## 🏗️ Architektur

### Technologie-Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| **Virtualisierung** | Proxmox VE | LXC Container Host |
| **Provisioning** | OpenTofu 1.6+ | Declarative Infrastructure |
| **Config Management** | Ansible | Service Setup & Config |
| **Orchestration** | Semaphore | CI/CD Pipeline Execution |
| **Database** | PostgreSQL 16 | Persistent Backend |
| **Source Control** | Gitea 1.22.6 | Self-hosted Git |
| **Dashboard** | Dashy | Service Overview |

### Netzwerk-Schema

**Subnet:** `10.10.0.0/16` (alle Services mit statischen IPs)

| 3rd Octet | Category | CT-ID Range | Beispiel |
|-----------|----------|-------------|----------|
| **0** | Core / OPNsense | — | 10.10.0.1 (Gateway) |
| **10** | Network Infra | 1000-1099 | 10.10.10.10 (Proxmox) |
| **20** | Databases / DevTools | 2000-2099 | 10.10.20.10 (PostgreSQL) |
| **30** | Backup & Security | 3000-3099 | 10.10.30.10 (Vaultwarden) |
| **40** | Web & Admin | 4000-4099 | 10.10.40.11 (Dashy) |
| **80** | Monitoring & Logging | 8000-8099 | 10.10.80.10 (Prometheus) |
| **100** | Automation | 10000-10099 | 10.10.100.15 (Semaphore) |

**Zonen** (Flags, keine separaten Netze):
- **Functional (`-fz`):** Produktiv, muss stabil sein
- **Playground (`-pg`):** Experimente, darf brechen

---

## 🔧 Repository-Struktur

```
RALF/
├── docs/              Governance-Dokumente (Netzwerk, Konventionen)
├── catalog/           Machine-readable Service-Katalog (60 Services)
├── services/          Human-readable Service-Specs (Runbooks)
├── plans/             Intent → Plan Workflow-Artefakte
├── changes/           Change Records (Audit Trail)
├── incidents/         Incident Reports & Lessons Learned
├── healthchecks/      Network Health Gatekeeper
├── inventory/         Host Inventory & Runtime Config
├── iac/               Infrastructure as Code
│   ├── stacks/        OpenTofu Stacks (per Service)
│   └── ansible/       Playbooks, Roles, Inventory
├── bootstrap/         LXC Provisioning Scripts (Bash)
├── pipelines/         Semaphore Pipeline Definitions
└── tests/             Smoke & Acceptance Tests
```

---

## 📖 Nicht-verhandelbare Prinzipien

1. **Network First:** Keine Deployments ohne gesundes Netzwerk
2. **Controlled Change:** Intent → Plan → Approval → Change
3. **Rollback-fähig:** LXC Snapshots (`pre-install`)
4. **No Secrets in Repo:** Secrets in Semaphore Variables
5. **LXC First:** Keine Docker/Kubernetes
6. **Explicit over Implicit:** Statische IPs, feste CT-IDs

---

## 🛠️ Bootstrap-Reihenfolge

### Phase 1: Foundation (✅ Abgeschlossen)

```
1. Credentials generieren
   → /var/lib/ralf/credentials.env

2. PostgreSQL deployen (CT 2010)
   → bash bootstrap/create-postgresql.sh

3. Semaphore deployen (CT 10015)
   → bash bootstrap/create-and-fill-runner.sh

4. Gitea deployen (CT 2012)
   → bash bootstrap/create-gitea.sh

5. Repository nach Gitea pushen
   → git remote add gitea ssh://git@10.10.20.12:2222/kolja/ralf.git
   → git push gitea main

6. Dashy Dashboard deployen (CT 4001)
   → Automatisches Service-Discovery
```

### Phase 2: Platform Services (Geplant)

- Vaultwarden (Password Management)
- NetBox (IPAM & DCIM)
- Snipe-IT (Asset Management)

### Phase 3: Application Services (Geplant)

- n8n (Workflow Automation)
- Matrix/Synapse (Chat)
- Maddy (Mail Server)
- Media Server (*arr Stack)

### Phase 4: Observability (Geplant)

- Prometheus (Metrics)
- Grafana (Dashboards)
- Loki (Logs)

---

## 🧪 Testing

Alle Services haben Smoke Tests:

```bash
# PostgreSQL
bash tests/postgresql/smoke.sh

# Gitea
bash tests/gitea/smoke.sh

# Semaphore
curl -s http://10.10.100.15:3000 | grep -q "Semaphore"
```

**Conventions:**
- `set -euo pipefail` in allen Bash-Scripts
- Environment Variables mit `${VAR:-default}` Pattern
- Tests sind kumulativ (alle laufen durch)

---

## 📚 Wichtige Dokumente

| Dokument | Beschreibung |
|----------|--------------|
| [`CLAUDE.md`](CLAUDE.md) | AI Assistant Guide |
| [`docs/conventions.md`](docs/conventions.md) | Naming & Structural Rules |
| [`docs/network-baseline.md`](docs/network-baseline.md) | Network Architecture |
| [`inventory/hosts.yaml`](inventory/hosts.yaml) | Host Inventory |
| [`inventory/runtime.env`](inventory/runtime.env) | IPs, Ports, Endpoints |

---

## 🔐 Credentials & Security

**Credentials:** `/var/lib/ralf/credentials.env`
- 148 Zeilen, 62 Environment Variables
- Nicht im Git Repository
- Alle Services verwenden Two-Admin-Pattern (kolja + ralf)

**Pattern:**
```bash
source /var/lib/ralf/credentials.env
echo $GITEA_ADMIN1_USER      # kolja
echo $GITEA_ADMIN1_PASS      # <generiert>
```

**Passwort-Generator:**
- Vermeidet mehrdeutige Zeichen (0, O, 1, I, l)
- Nutzt Sonderzeichen: `$?%!@#&*`
- 24-40 Zeichen je nach Service

---

## 🚨 Change Governance

```
Intent (plans/INTENT-*.md)     "Was wollen wir?"
    ↓
Plan (plans/PLAN-*.md)         "Wie genau machen wir es?"
    ↓
Approval                        Human Gate
    ↓
Execution (pipelines/)          Semaphore führt aus
    ↓
Change Record (changes/)        "Was ist passiert?"
    ↓
Incident (bei Fehler)           "Was lief schief?"
```

---

## 🩺 Health Checks

Der Network Health Gatekeeper (`healthchecks/run-network-health.sh`) validiert 9 Kategorien:

- **A:** Core Connectivity (Gateway, Internet)
- **B:** DNS Resolution (Intern + Extern)
- **C:** DHCP & Static IP Compliance
- **D:** NTP Time Sync
- **E:** Reverse Proxy (Caddy)
- **F:** Network Infrastructure (TP-Link, Proxmox)
- **G:** Observability (Logs)
- **H:** IP Scheme Drift Detection
- **I:** Recovery Readiness (OPNsense Backup)

**Regel:** Jeder Fehler = keine Deploys, nur Analysis/Healing/Rollback.

---

## 🤝 Contributing

RALF ist ein Lernprojekt. Die Dokumentation ist bewusst auf Deutsch.

**Sprachen:**
- **Deutsch:** Dokumentation, Kommentare, Pläne
- **Englisch:** Code (Variable Names, Functions, YAML Keys)

**Workflow:**
1. Intent erstellen (`plans/INTENT-YYYYMMDD-XXX.md`)
2. Plan erstellen (`plans/PLAN-YYYYMMDD-XXX.md`)
3. Approval einholen
4. Code schreiben (OpenTofu + Ansible)
5. Tests schreiben
6. Pipeline erstellen
7. Change dokumentieren

---

## 📊 Dashboard

**Dashy:** http://10.10.40.11:4000

Features:
- ✅ Alle Services mit Status-Checks
- ✅ Nord Frost Theme
- ✅ Auto-Update alle 5 Minuten
- ✅ Responsive Layout
- ✅ Service-Kategorien (P1-P4)

**Config:** `/opt/dashy/user-data/conf.yml` (im Container CT 4001)

---

## 📞 Support

- **Gitea:** http://10.10.20.12:3000/kolja/ralf/issues
- **GitHub Mirror:** https://github.com/default82/RALF

---

## 📄 License

MIT License - siehe [LICENSE](LICENSE)

---

**Built with ❤️ and lots of YAML**
