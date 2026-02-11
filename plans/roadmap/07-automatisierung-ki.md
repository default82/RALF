# Phase 7 – Automatisierung & KI (n8n)

Ziel: n8n ist die zentrale Automatisierungsplattform, die alle RALF-Dienste
verbindet und KI-Workflows ermoeglicht. n8n ist das "Gehirn" von RALF –
es verarbeitet Events, orchestriert Aktionen und kommuniziert mit dem Operator.

---

## 7.1 n8n deployen

**Hostname:** ops-n8n | **IP:** 10.10.100.20 | **CT-ID:** 10020

### Voraussetzungen
- [ ] PostgreSQL laeuft + DB `n8n` + User `n8n` existieren
- [ ] Alle P1-Dienste laufen (Semaphore, PostgreSQL, Gitea)
- [ ] Mail-Server laeuft (fuer Benachrichtigungen)

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/n8n-pg/`
- [ ] Standard-Stack
- [ ] ct_id=10020, ip=10.10.100.20/16, memory=2048, disk=16

#### Terragrunt: `iac/stacks/n8n-pg/terragrunt.hcl`
- [ ] Dependency auf postgresql-fz

#### Ansible Role: `iac/ansible/roles/n8n/`
- [ ] `tasks/main.yml`:
  - Node.js 20 LTS installieren (NodeSource Repo)
  - n8n global installieren: `npm install -g n8n`
  - Verzeichnisse erstellen: `/var/lib/n8n`
  - Umgebungskonfiguration erstellen
  - Systemd-Service erstellen
  - Aktivieren und starten
- [ ] `handlers/main.yml`: restart n8n
- [ ] `templates/n8n.env.j2`:
  ```
  N8N_HOST=0.0.0.0
  N8N_PORT=5678
  N8N_PROTOCOL=http
  WEBHOOK_URL=https://n8n.homelab.lan/
  N8N_EDITOR_BASE_URL=https://n8n.homelab.lan/

  # Datenbank
  DB_TYPE=postgresdb
  DB_POSTGRESDB_HOST=10.10.20.10
  DB_POSTGRESDB_PORT=5432
  DB_POSTGRESDB_DATABASE=n8n
  DB_POSTGRESDB_USER=n8n
  DB_POSTGRESDB_PASSWORD={{ n8n_db_pass }}

  # E-Mail
  N8N_EMAIL_MODE=smtp
  N8N_SMTP_HOST=10.10.40.10
  N8N_SMTP_PORT=587
  N8N_SMTP_SENDER=n8n@homelab.lan

  # Sicherheit
  N8N_BASIC_AUTH_ACTIVE=true
  N8N_BASIC_AUTH_USER={{ n8n_admin_user }}
  N8N_BASIC_AUTH_PASSWORD={{ n8n_admin_pass }}

  # Ausfuehrung
  EXECUTIONS_MODE=regular
  GENERIC_TIMEZONE=Europe/Berlin
  ```
- [ ] `templates/n8n.service.j2`

#### Ansible Playbook: `iac/ansible/playbooks/deploy-n8n.yml`
- [ ] Hosts: Gruppe `automation`, oder neuer Host ops-n8n
- [ ] Roles: base + n8n

### Datenbank-Provisioning erweitern
- [ ] `provision-databases.yml` um n8n-Eintrag ergaenzen:
  ```yaml
  - name: n8n
    owner: n8n
    password: "{{ n8n_db_pass }}"
  ```

### Bootstrap + Test + Pipeline
- [ ] `bootstrap/create-n8n.sh` (CT-ID: 10020)
- [ ] `tests/n8n/smoke.sh` (HTTP 5678, /healthz)
- [ ] `pipelines/semaphore/deploy-n8n.yaml`

### Inventory + Service-Steckbrief
- [ ] hosts.yml: ops-n8n in Gruppe `automation`
- [ ] `services/n8n.md`
- [ ] runtime.env: N8N_IP, N8N_PORT

---

## 7.2 n8n-Workflows erstellen

### Admin-Accounts einrichten
- [ ] Erster Login → Owner-Account: kolja / kolja@homelab.lan
- [ ] Zweiten Account anlegen: ralf / ralf@homelab.lan (Admin)

### Credentials in n8n hinterlegen
- [ ] PostgreSQL (fuer direkte DB-Abfragen)
- [ ] Gitea API Token
- [ ] Grafana API Token
- [ ] Semaphore API Token (falls vorhanden)
- [ ] Matrix Access Token (Phase 8)
- [ ] Vaultwarden API (falls unterstuetzt)
- [ ] NetBox API Token

### Basis-Workflows erstellen

#### Workflow 1: Health-Check Dashboard
- [ ] Trigger: Alle 5 Minuten (Cron)
- [ ] HTTP-Requests an alle Dienste (Smoke-Check)
- [ ] Ergebnis in PostgreSQL speichern (health_log Tabelle)
- [ ] Bei Failure: E-Mail an kolja@homelab.lan
- [ ] Spaeter: Matrix-Nachricht an Kolja

#### Workflow 2: Backup-Orchestrierung
- [ ] Trigger: Taeglich 02:00 Uhr
- [ ] PostgreSQL pg_dump fuer alle Datenbanken
- [ ] Ergebnis loggen
- [ ] Bei Failure: Alarm

#### Workflow 3: Inventory-Sync
- [ ] Trigger: Taeglich oder bei Change
- [ ] NetBox API abfragen → aktuellen Stand holen
- [ ] Mit inventory/hosts.yaml vergleichen
- [ ] Bei Abweichung: Benachrichtigung

#### Workflow 4: Git-Webhook Handler
- [ ] Trigger: Gitea Webhook (Push auf main)
- [ ] Semaphore Pipeline starten (Deploy)
- [ ] Ergebnis an Kolja melden

#### Workflow 5: Dienst-Neustart bei Failure
- [ ] Trigger: Prometheus Alert Webhook
- [ ] Betroffenen Dienst identifizieren
- [ ] Restart via SSH oder Semaphore
- [ ] Ergebnis loggen und melden

### KI-Integration vorbereiten

#### Workflow 6: KI-Assistent (Claude/LLM)
- [ ] Trigger: Matrix-Nachricht von Kolja an Ralf-Bot
- [ ] Nachricht analysieren (Intent erkennen)
- [ ] Entsprechende Aktion ausfuehren:
  - Status-Abfragen → Health-Check + Antwort
  - Deploy-Anfragen → Semaphore Pipeline triggern
  - Analyse-Anfragen → Prometheus/Grafana Daten abfragen
  - Log-Anfragen → Loki abfragen
- [ ] Antwort an Matrix zurueckschicken
- [ ] **API-Key benoetigt:** Claude API oder alternatives LLM

#### Workflow 7: Automatische Incident-Erstellung
- [ ] Trigger: Prometheus Alert
- [ ] INCIDENT-Datei erstellen (nach Template)
- [ ] In Gitea committen
- [ ] Kolja benachrichtigen

### Benoetigte Credentials
- [ ] **n8n DB-Passwort**
- [ ] **n8n Admin-Passwort** (Kolja)
- [ ] **n8n Admin-Passwort** (Ralf)
- [ ] **Gitea API Token** (fuer Webhook + Git-Operationen)
- [ ] **NetBox API Token** (fuer Inventory-Sync)
- [ ] **Grafana API Token** (fuer Dashboard-Embedding)
- [ ] **Claude API Key** (oder alternatives LLM, fuer KI-Workflows)

### Abnahmekriterien
- [ ] n8n Web-UI erreichbar auf Port 5678
- [ ] Beide Admin-Accounts funktionieren
- [ ] Health-Check Workflow laeuft erfolgreich
- [ ] Backup-Workflow laeuft erfolgreich
- [ ] Git-Webhook funktioniert (Push → Pipeline)
- [ ] Dienst-Restart bei Failure funktioniert
