# Phase 3 – Mail-Server (Maddy)

Ziel: Ein interner Mail-Server fuer homelab.lan, der E-Mail-Zustellung
zwischen allen RALF-Diensten und Benutzern ermoeglicht.

Maddy ist ein All-in-One Mail-Server (SMTP + IMAP) als einzelnes Binary,
ideal fuer LXC-Betrieb ohne Docker.

---

## 3.1 Maddy deployen

**Hostname:** svc-mail | **IP:** 10.10.40.10 | **CT-ID:** 4010

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/mail-fz/`
- [ ] `tofu/versions.tf` – Provider-Anforderungen
- [ ] `tofu/variables.tf` – Variablen:
  - `ct_id` (default: 4010)
  - `hostname` (default: "svc-mail")
  - `ip_address` (default: "10.10.40.10/16")
  - `gateway` (default: "10.10.0.1")
  - `memory` (default: 1024)
  - `disk_size` (default: 16)
  - `proxmox_api_url`, `proxmox_api_token` (sensitive)
- [ ] `tofu/main.tf` – LXC-Container
- [ ] `tofu/outputs.tf` – IP, Hostname
- [ ] `env/functional.tfvars`
- [ ] `README.md`

#### Terragrunt: `iac/stacks/mail-fz/terragrunt.hcl`
- [ ] Keine harten Abhaengigkeiten (standalone)

#### Ansible Role: `iac/ansible/roles/maddy/`
- [ ] `tasks/main.yml`:
  - Maddy-Binary herunterladen (aktuelle stabile Version)
  - Verzeichnisse erstellen: `/etc/maddy`, `/var/lib/maddy`
  - Konfiguration deployen: `/etc/maddy/maddy.conf`
  - TLS-Zertifikate generieren (self-signed fuer homelab.lan)
  - Systemd-Service erstellen
  - Dienst aktivieren und starten
  - Mail-Accounts erstellen (Kolja + Ralf)
- [ ] `handlers/main.yml`:
  - `restart maddy`
- [ ] `templates/maddy.conf.j2`:
  ```
  $(hostname) = svc-mail.homelab.lan
  $(primary_domain) = homelab.lan

  tls self_signed

  smtp tcp://0.0.0.0:25 {
    hostname $(hostname)
    deliver_to &local_routing
  }

  submission tcp://0.0.0.0:587 {
    hostname $(hostname)
    auth &local_authdb
    deliver_to &local_routing
  }

  imap tcp://0.0.0.0:993 {
    hostname $(hostname)
    auth &local_authdb
    storage &local_mailboxes
  }

  local_authdb table.pass_table {
    table sql_table {
      driver sqlite3
      dsn /var/lib/maddy/credentials.db
      table_name passwords
    }
  }

  local_mailboxes imapsql {
    driver sqlite3
    dsn /var/lib/maddy/mail.db
  }

  local_routing {
    deliver_to &local_mailboxes
  }
  ```
- [ ] `templates/maddy.service.j2`

#### Ansible Playbook: `iac/ansible/playbooks/deploy-mail.yml`
- [ ] Hosts: neuen Inventory-Eintrag `mail` erstellen
- [ ] Roles: base + maddy

#### Bootstrap Script: `bootstrap/create-mail.sh`
- [ ] CT-ID: 4010, IP: 10.10.40.10
- [ ] Ports: 25, 587, 993

#### Smoke Test: `tests/mail/smoke.sh`
- [ ] TCP-Check Port 25 (SMTP)
- [ ] TCP-Check Port 587 (Submission)
- [ ] TCP-Check Port 993 (IMAPS)
- [ ] Ping-Check
- [ ] SMTP-Handshake-Test:
  ```bash
  echo "EHLO test" | nc -w5 $MAIL_IP 25
  ```

#### Pipeline: `pipelines/semaphore/deploy-mail.yaml`
- [ ] Jobs: network-health → tofu → ansible → smoke

### Mail-Accounts erstellen
- [ ] Account: kolja@homelab.lan
  ```bash
  maddy creds create kolja@homelab.lan
  maddy imap-acct create kolja@homelab.lan
  ```
- [ ] Account: ralf@homelab.lan
  ```bash
  maddy creds create ralf@homelab.lan
  maddy imap-acct create ralf@homelab.lan
  ```

### Inventory erweitern
- [ ] `iac/ansible/inventory/hosts.yml`:
  ```yaml
  mail:
    hosts:
      svc-mail:
        ansible_host: 10.10.40.10
        ralf_zone: functional
        ralf_role: mail
        ralf_ct_id: 4010
  ```
- [ ] `inventory/hosts.yaml` – Host-Eintrag
- [ ] `inventory/runtime.env`:
  ```
  MAIL_IP=10.10.40.10
  MAIL_SMTP_PORT=25
  MAIL_SUBMISSION_PORT=587
  MAIL_IMAP_PORT=993
  MAIL_DOMAIN=homelab.lan
  ```

### DNS konfigurieren (OPNsense)
- [ ] A-Record: `svc-mail.homelab.lan → 10.10.40.10`
- [ ] MX-Record: `homelab.lan → svc-mail.homelab.lan` (Prioritaet 10)
- [ ] PTR-Record: `10.10.40.10 → svc-mail.homelab.lan`

### Service-Steckbrief erstellen
- [ ] `services/mail.md` basierend auf SERVICE_TEMPLATE.md

### Catalog-Eintrag erstellen
- [ ] `catalog/projects/maddy.yaml`
- [ ] `catalog/index.yaml` aktualisieren

### Alle Dienste mit SMTP konfigurieren
- [ ] Vaultwarden: SMTP-Einstellungen auf svc-mail zeigen
- [ ] Gitea: `app.ini` SMTP-Einstellungen hinzufuegen
- [ ] Semaphore: E-Mail-Benachrichtigungen konfigurieren
- [ ] Alle zukuenftigen Dienste: svc-mail als SMTP-Relay

### Benoetigte Credentials
- [ ] **Kolja Mail-Passwort** (kolja@homelab.lan)
- [ ] **Ralf Mail-Passwort** (ralf@homelab.lan)

### Abnahmekriterien
- [ ] SMTP-Zustellung intern funktioniert (Test-Mail senden)
- [ ] IMAP-Abruf funktioniert (Test-Mail empfangen)
- [ ] Beide Accounts koennen E-Mails senden und empfangen
- [ ] Andere Dienste koennen Benachrichtigungen senden
- [ ] Snapshot `pre-install` existiert
