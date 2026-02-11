# Phase 2 – Sicherheit & Secrets (Vaultwarden)

Ziel: Alle Passwoerter und Secrets werden zentral in Vaultwarden verwaltet.
Kein Passwort liegt unverschluesselt auf irgendeinem System.

---

## 2.1 Vaultwarden deployen

**Hostname:** svc-vaultwarden | **IP:** 10.10.30.10 | **CT-ID:** 3010

### Voraussetzungen
- [ ] PostgreSQL laeuft
- [ ] Datenbank `vaultwarden` + User `vaultwarden` existieren

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/vaultwarden-fz/`
- [ ] `tofu/versions.tf` – Provider-Anforderungen (BPG Proxmox >= 0.66.0)
- [ ] `tofu/variables.tf` – Variablen:
  - `ct_id` (default: 3010)
  - `hostname` (default: "svc-vaultwarden")
  - `ip_address` (default: "10.10.30.10/16")
  - `gateway` (default: "10.10.0.1")
  - `memory` (default: 1024)
  - `disk_size` (default: 8)
  - `proxmox_api_url`, `proxmox_api_token` (sensitive)
- [ ] `tofu/main.tf` – LXC-Container-Resource:
  - Ubuntu 24.04 Template
  - Unprivileged, nesting + keyctl
  - Statische IP
  - Pre-install Snapshot
- [ ] `tofu/outputs.tf` – IP, Hostname, URL
- [ ] `env/functional.tfvars` – Nicht-geheime Werte
- [ ] `README.md` – Stack-Dokumentation

#### Terragrunt: `iac/stacks/vaultwarden-fz/terragrunt.hcl`
- [ ] Dependency auf `postgresql-fz`
- [ ] Inputs aus tfvars

#### Ansible Role: `iac/ansible/roles/vaultwarden/`
- [ ] `tasks/main.yml`:
  - Vaultwarden-Binary herunterladen (oder via Paket)
  - Web-Vault herunterladen (Frontend)
  - Konfiguration erstellen (`/etc/vaultwarden/config.env`)
  - Systemd-Service erstellen
  - Dienst aktivieren und starten
- [ ] `handlers/main.yml`:
  - `restart vaultwarden`
- [ ] `templates/config.env.j2`:
  ```
  DATABASE_URL=postgresql://vaultwarden:{{ vaultwarden_db_pass }}@10.10.20.10:5432/vaultwarden
  ADMIN_TOKEN={{ vaultwarden_admin_token }}
  DOMAIN=https://vault.homelab.lan
  SMTP_HOST=10.10.40.10
  SMTP_PORT=587
  SMTP_FROM=vaultwarden@homelab.lan
  SIGNUPS_ALLOWED=false
  INVITATIONS_ALLOWED=true
  ```
- [ ] `templates/vaultwarden.service.j2`

#### Ansible Playbook: `iac/ansible/playbooks/deploy-vaultwarden.yml`
- [ ] Hosts: neuen Inventory-Eintrag `security` erstellen
- [ ] Roles: base + vaultwarden
- [ ] Variablen: `vaultwarden_db_pass`, `vaultwarden_admin_token` via Secrets

#### Bootstrap Script: `bootstrap/create-vaultwarden.sh`
- [ ] Analog zu bestehenden Scripts (`set -euo pipefail`, Prechecks, Snapshots)
- [ ] CT-ID: 3010, IP: 10.10.30.10

#### Smoke Test: `tests/vaultwarden/smoke.sh`
- [ ] HTTP-Check auf Port 8080
- [ ] API-Check: GET /api/alive
- [ ] Ping-Check

#### Pipeline: `pipelines/semaphore/deploy-vaultwarden.yaml`
- [ ] Jobs: network-health → tofu-init → tofu-plan → tofu-apply → ansible-deploy → smoke-post

### Datenbank-Provisioning erweitern
- [ ] `provision-databases.yml` um Vaultwarden-Eintrag ergaenzen:
  ```yaml
  - name: vaultwarden
    owner: vaultwarden
    password: "{{ vaultwarden_db_pass }}"
  ```

### Inventory erweitern
- [ ] `iac/ansible/inventory/hosts.yml` – svc-vaultwarden hinzufuegen:
  ```yaml
  security:
    hosts:
      svc-vaultwarden:
        ansible_host: 10.10.30.10
        ralf_zone: functional
        ralf_role: security
        ralf_ct_id: 3010
  ```
- [ ] `inventory/hosts.yaml` – Host-Eintrag hinzufuegen
- [ ] `inventory/runtime.env` – Variablen hinzufuegen:
  ```
  VAULTWARDEN_IP=10.10.30.10
  VAULTWARDEN_PORT=8080
  ```

### Erstkonfiguration
- [ ] Admin-Panel aufrufen: http://10.10.30.10:8080/admin
- [ ] Admin-Token eingeben
- [ ] Benutzer einladen:
  - kolja@homelab.lan (Admin/Owner)
  - ralf@homelab.lan (Admin/Bot)
- [ ] SMTP-Einstellungen pruefen (nach Phase 3)
- [ ] Organisationen anlegen: "RALF Homelab"

### Secrets migrieren
- [ ] Alle bisherigen Passwoerter in Vaultwarden speichern:
  - PostgreSQL Superuser
  - Semaphore Admin (Kolja + Ralf)
  - Gitea Admin (Kolja + Ralf)
  - Alle DB-Passwoerter
  - Proxmox API Token
  - SSH-Keys
- [ ] Semaphore-Secrets auf Vaultwarden-Referenzen umstellen (falls API genutzt)

### Benoetigte Credentials
- [ ] **Vaultwarden Admin-Token** (fuer Admin-Panel, kein normaler Login)
- [ ] **vaultwarden DB-Passwort**
- [ ] **Kolja Master-Passwort** (Vaultwarden-Account)
- [ ] **Ralf Master-Passwort** (Vaultwarden-Account)

### Abnahmekriterien
- [ ] Vaultwarden Web-UI erreichbar
- [ ] Login mit Kolja + Ralf funktioniert
- [ ] Alle bisherigen Passwoerter sind in Vaultwarden gespeichert
- [ ] Snapshot `pre-install` existiert
