# Phase 1 – Core Bootstrap

Ziel: Die drei Kern-Dienste (PostgreSQL, Semaphore, Gitea) laufen stabil
und das RALF-Repository ist self-hosted auf Gitea.

**Bootstrap-Reihenfolge:** PostgreSQL → Semaphore → Gitea

PostgreSQL muss ZUERST deployed werden, da Semaphore und Gitea
darauf aufbauen (PostgreSQL als zentrales Backend).

---

## 1.1 PostgreSQL deployen

**Hostname:** svc-postgres | **IP:** 10.10.20.10 | **CT-ID:** 2010

### Voraussetzungen
- [ ] Proxmox-Host erreichbar (10.10.10.10)
- [ ] Ubuntu 24.04 LXC-Template verfuegbar

### Aufgaben
- [ ] Bootstrap-Script ausfuehren:
  ```bash
  bash bootstrap/create-postgresql.sh
  ```
- [ ] Smoke-Test:
  ```bash
  bash tests/postgresql/smoke.sh
  ```
- [ ] PostgreSQL-Superuser-Passwort setzen (wenn noch nicht durch Bootstrap):
  ```sql
  ALTER USER postgres PASSWORD '<pg_superuser_pass>';
  ```
- [ ] pg_hba.conf pruefen: Homelab-Zugriff aktiv (10.10.0.0/16)
- [ ] postgresql.conf pruefen: listen_addresses = '*'

### Datenbank-Provisioning
- [ ] Provisioning-Playbook ausfuehren:
  ```bash
  cd iac/ansible
  ansible-playbook -i inventory/hosts.yml playbooks/provision-databases.yml \
    --extra-vars "semaphore_db_pass=<pw> gitea_db_pass=<pw>"
  ```
- [ ] Pruefen: Datenbanken `semaphore` und `gitea` existieren
- [ ] Pruefen: Benutzer `semaphore` und `gitea` koennen sich einloggen

### Spaeter hinzuzufuegende Datenbanken (via erweitertes Provisioning)
- [ ] `vaultwarden` (Phase 2)
- [ ] `netbox` (Phase 6)
- [ ] `snipeit` (Phase 6)
- [ ] `synapse` (Phase 8)
- [ ] `n8n` (Phase 7)

### Benoetigte Credentials
- [ ] **PostgreSQL Superuser-Passwort**
- [ ] **semaphore DB-Passwort**
- [ ] **gitea DB-Passwort**

### Abnahmekriterien
- [ ] PostgreSQL laeuft auf Port 5432
- [ ] pg_isready meldet "accepting connections"
- [ ] Datenbanken semaphore + gitea existieren
- [ ] Remote-Login mit semaphore/gitea-User funktioniert
- [ ] Snapshot `pre-install` existiert

---

## 1.2 Semaphore deployen

**Hostname:** ops-semaphore | **IP:** 10.10.100.15 | **CT-ID:** 10015

### Voraussetzungen
- [ ] PostgreSQL laeuft und ist erreichbar (10.10.20.10:5432)
- [ ] Datenbank `semaphore` + User `semaphore` existieren
- [ ] SSH-Key fuer Ansible auf Proxmox hinterlegt

### Aufgaben
- [ ] Umgebungsvariablen setzen:
  - `SEMAPHORE_PASS` (Admin-Passwort fuer Kolja)
  - `PG_PASS` (PostgreSQL-Passwort fuer semaphore-User)
- [ ] Bootstrap-Script ausfuehren:
  ```bash
  SEMAPHORE_PASS="<admin-passwort>" PG_PASS="<db-passwort>" \
    bash bootstrap/create-and-fill-runner.sh
  ```
- [ ] Smoke-Test ausfuehren:
  ```bash
  bash tests/bootstrap/smoke.sh
  ```
- [ ] Web-UI pruefen: http://10.10.100.15:3000
- [ ] Zweiten Admin-Account anlegen:
  - Benutzer: `ralf`
  - E-Mail: ralf@homelab.lan
  - Passwort: in Vaultwarden speichern (sobald verfuegbar)

### Semaphore konfigurieren
- [ ] SSH-Key hinterlegen (fuer Ansible-Zugriff auf alle LXC-Container)
- [ ] Git-Repository hinzufuegen:
  - URL: https://github.com/default82/RALF.git (spaeter: Gitea)
  - Branch: main
- [ ] Inventar hinzufuegen: `iac/ansible/inventory/hosts.yml`
- [ ] Umgebungsvariablen in Semaphore anlegen:
  - `PROXMOX_API_URL`
  - `PROXMOX_API_TOKEN_ID`
  - `PROXMOX_API_TOKEN_SECRET`
  - `GITEA_DB_PASS`
  - `PG_SUPERUSER_PASS`

### Benoetigte Credentials
- [ ] **Proxmox API Token:** Unter Proxmox Datacenter > Permissions > API Tokens erstellen
  - User: root@pam oder eigener API-User
  - Token-ID: z.B. `ralf-tofu`
  - Token-Secret: wird bei Erstellung angezeigt (einmal kopieren!)
- [ ] **SSH-Keypair:** Fuer Ansible-Zugriff auf Container
  ```bash
  ssh-keygen -t ed25519 -C "ralf-ansible" -f ~/.ssh/ralf-ansible
  ```
- [ ] **Semaphore Admin-Passwort** (Kolja)
- [ ] **Semaphore Admin-Passwort** (Ralf)
- [ ] **Semaphore DB-Passwort** (aus 1.1)

### Abnahmekriterien
- [ ] Semaphore Web-UI erreichbar auf Port 3000
- [ ] Beide Admin-Accounts funktionieren
- [ ] SSH-Key in Semaphore hinterlegt
- [ ] Test-Job (Smoke) laeuft erfolgreich
- [ ] PostgreSQL-Backend aktiv (nicht SQLite!)

---

## 1.3 Gitea deployen

**Hostname:** svc-gitea | **IP:** 10.10.20.12 | **CT-ID:** 2012

### Voraussetzungen
- [ ] PostgreSQL laeuft und ist erreichbar
- [ ] Datenbank `gitea` + User `gitea` existieren

### Deploy
- [ ] Via Semaphore Pipeline `deploy-gitea` oder manuell:
  ```bash
  cd iac/ansible
  ansible-playbook -i inventory/hosts.yml playbooks/deploy-gitea.yml \
    --extra-vars "gitea_db_pass=<pw>"
  ```
- [ ] Smoke-Test:
  ```bash
  bash tests/gitea/smoke.sh
  ```

### Erstkonfiguration (Web-UI)
- [ ] Gitea Web-UI aufrufen: http://10.10.20.12:3000
- [ ] Initiale Einrichtung:
  - DB-Typ: PostgreSQL
  - Host: 10.10.20.10:5432
  - DB-Name: gitea
  - DB-User: gitea
  - Passwort: (aus Secrets)
- [ ] Admin-Account 1 anlegen:
  - Benutzer: `kolja`
  - E-Mail: kolja@homelab.lan
  - Passwort: sicheres Passwort
- [ ] Admin-Account 2 anlegen:
  - Benutzer: `ralf`
  - E-Mail: ralf@homelab.lan
  - Passwort: sicheres Passwort

### Nach Einrichtung
- [ ] SSH-Key fuer Semaphore in Gitea hinterlegen
- [ ] Organisation "RALF" erstellen
- [ ] Webhook-Secret generieren (fuer spaetere CI/CD-Trigger)

### Benoetigte Credentials
- [ ] **Gitea DB-Passwort** (bereits aus 1.2)
- [ ] **Gitea Admin-Passwort** (Kolja)
- [ ] **Gitea Admin-Passwort** (Ralf)

### Abnahmekriterien
- [ ] Gitea Web-UI erreichbar auf Port 3000
- [ ] SSH-Clone funktioniert auf Port 2222
- [ ] API erreichbar: GET /api/v1/version
- [ ] Beide Admin-Accounts funktionieren
- [ ] Snapshot `pre-install` existiert

---

## 1.4 Repository-Migration GitHub → Gitea

### Aufgaben
- [ ] Repository auf Gitea erstellen: Organisation "RALF", Repo "ralf"
- [ ] Mirror von GitHub einrichten:
  ```bash
  git remote add gitea ssh://git@10.10.20.12:2222/RALF/ralf.git
  git push gitea main
  ```
- [ ] Semaphore Git-Remote auf Gitea umstellen:
  - Alte URL: https://github.com/default82/RALF.git
  - Neue URL: ssh://git@10.10.20.12:2222/RALF/ralf.git
- [ ] GitHub-Repo als Archiv/Backup behalten (read-only)
- [ ] Alle Pipelines testen mit neuem Remote
- [ ] `.git/config` auf allen lokalen Clones aktualisieren

### Abnahmekriterien
- [ ] Semaphore zieht Code von Gitea (nicht mehr GitHub)
- [ ] Pushes landen auf Gitea
- [ ] Alle Pipelines funktionieren mit Gitea-Remote

---

## 1.5 Terragrunt-Grundstruktur einrichten

### Aufgaben
- [ ] Terragrunt installieren (auf Semaphore-Container):
  ```bash
  curl -fsSL https://github.com/gruntwork-io/terragrunt/releases/download/v0.55.0/terragrunt_linux_amd64 \
    -o /usr/local/bin/terragrunt && chmod +x /usr/local/bin/terragrunt
  ```
- [ ] Root-Konfiguration erstellen: `iac/terragrunt.hcl`
  ```hcl
  # Gemeinsame Provider-Konfiguration fuer alle Stacks
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
  }
  provider "proxmox" {
    endpoint  = var.proxmox_api_url
    api_token = var.proxmox_api_token
    insecure  = true
  }
  EOF
  }
  ```
- [ ] Pro Stack eine `terragrunt.hcl` erstellen mit:
  - `dependency`-Bloecke (z.B. Gitea haengt von PostgreSQL ab)
  - `inputs`-Block mit Stack-spezifischen Variablen
- [ ] Testen: `terragrunt run-all plan` im `iac/stacks/` Verzeichnis

### Stack-Abhaengigkeiten (Terragrunt)
```
postgresql-fz
    ↑
    ├── gitea-fz
    ├── vaultwarden-fz (Phase 2)
    ├── netbox-fz (Phase 6)
    ├── snipeit-fz (Phase 6)
    └── synapse-fz (Phase 8)

semaphore-pg (keine Abhaengigkeit)

caddy-fz
    ↑
    ├── alle extern erreichbaren Dienste

n8n-pg (Phase 7)
```

### Abnahmekriterien
- [ ] `terragrunt run-all plan` zeigt alle Stacks korrekt an
- [ ] Abhaengigkeiten werden respektiert (PostgreSQL vor Gitea)
- [ ] Keine Fehler bei `validate`
