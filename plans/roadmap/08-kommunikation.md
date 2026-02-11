# Phase 8 – Kommunikation (Matrix/Synapse + Element)

Ziel: Kolja kann mit RALF (Bot "Ralf") ueber Matrix/Element chatten.
RALF beantwortet Fragen, fuehrt Aktionen aus und meldet Stoerungen.
Dies ist die primaere Mensch-Maschine-Schnittstelle.

---

## 8.1 Matrix/Synapse deployen

**Hostname:** svc-synapse | **IP:** 10.10.40.30 | **CT-ID:** 4030

### Voraussetzungen
- [ ] PostgreSQL laeuft + DB `synapse` + User `synapse` existieren
- [ ] Mail-Server laeuft (fuer Registrierungsbestaetigung, optional)
- [ ] Caddy laeuft (fuer HTTPS-Zugriff)

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/synapse-fz/`
- [ ] Standard-Stack
- [ ] ct_id=4030, ip=10.10.40.30/16, memory=2048, disk=16

#### Terragrunt: `iac/stacks/synapse-fz/terragrunt.hcl`
- [ ] Dependency auf postgresql-fz

#### Ansible Role: `iac/ansible/roles/synapse/`
- [ ] `tasks/main.yml`:
  - Python3 + pip installieren
  - Synapse installieren: `pip install matrix-synapse`
  - Konfiguration generieren:
    ```bash
    python3 -m synapse.app.homeserver \
      --server-name homelab.lan \
      --config-path /etc/synapse/homeserver.yaml \
      --generate-config \
      --report-stats=no
    ```
  - Konfiguration anpassen (PostgreSQL, Registration, etc.)
  - Systemd-Service erstellen
  - Aktivieren und starten
  - Admin-User erstellen (Kolja):
    ```bash
    register_new_matrix_user -c /etc/synapse/homeserver.yaml \
      -u kolja -p <pass> -a http://localhost:8008
    ```
  - Admin-User erstellen (Ralf – der Bot):
    ```bash
    register_new_matrix_user -c /etc/synapse/homeserver.yaml \
      -u ralf -p <pass> -a http://localhost:8008
    ```
- [ ] `handlers/main.yml`: restart synapse
- [ ] `templates/homeserver.yaml.j2` (wichtige Abschnitte):
  ```yaml
  server_name: "homelab.lan"
  public_baseurl: "https://synapse.homelab.lan/"

  listeners:
    - port: 8008
      type: http
      resources:
        - names: [client, federation]

  database:
    name: psycopg2
    args:
      user: synapse
      password: "{{ synapse_db_pass }}"
      database: synapse
      host: 10.10.20.10
      port: 5432

  enable_registration: false
  registration_shared_secret: "{{ synapse_registration_secret }}"

  email:
    smtp_host: 10.10.40.10
    smtp_port: 587
    notif_from: "RALF Homelab <synapse@homelab.lan>"
  ```

### Datenbank-Provisioning erweitern
- [ ] `provision-databases.yml` um Synapse-Eintrag ergaenzen:
  ```yaml
  - name: synapse
    owner: synapse
    password: "{{ synapse_db_pass }}"
  ```
- [ ] WICHTIG: Synapse benoetigt LC_COLLATE und LC_CTYPE = 'C':
  ```sql
  CREATE DATABASE synapse
    ENCODING 'UTF8'
    LC_COLLATE='C'
    LC_CTYPE='C'
    TEMPLATE template0
    OWNER synapse;
  ```

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-synapse.yml`
- [ ] `bootstrap/create-synapse.sh` (CT-ID: 4030)
- [ ] `tests/synapse/smoke.sh`:
  - HTTP 8008 /_matrix/client/versions
  - HTTP 8008 /_synapse/admin/v1/server_version
  - Ping-Check
- [ ] `pipelines/semaphore/deploy-synapse.yaml`

### Inventory + Service-Steckbrief
- [ ] hosts.yml: Gruppe `communication`, Host svc-synapse
- [ ] `services/synapse.md`
- [ ] runtime.env: SYNAPSE_IP, SYNAPSE_PORT

---

## 8.2 Element Web deployen

**Hostname:** svc-element | **IP:** 10.10.40.32 | **CT-ID:** 4032

Element ist der Web-Client fuer Matrix. Rein statische Dateien.

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/element-fz/`
- [ ] Standard-Stack (kleiner Container)
- [ ] ct_id=4032, ip=10.10.40.32/16, memory=512, disk=4

#### Ansible Role: `iac/ansible/roles/element/`
- [ ] `tasks/main.yml`:
  - Nginx installieren (als statischer Webserver)
  - Element Web Release herunterladen und entpacken
  - `config.json` deployen
  - Nginx-Konfiguration
  - Aktivieren und starten
- [ ] `templates/config.json.j2`:
  ```json
  {
    "default_server_config": {
      "m.homeserver": {
        "base_url": "https://synapse.homelab.lan",
        "server_name": "homelab.lan"
      }
    },
    "brand": "RALF Homelab",
    "default_theme": "dark",
    "room_directory": {
      "servers": ["homelab.lan"]
    }
  }
  ```

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-element.yml`
- [ ] `bootstrap/create-element.sh` (CT-ID: 4032)
- [ ] `tests/element/smoke.sh` (HTTP 8080)
- [ ] `pipelines/semaphore/deploy-element.yaml`

### Inventory + Service-Steckbrief
- [ ] hosts.yml: svc-element in Gruppe `communication`
- [ ] `services/element.md`

---

## 8.3 RALF-Bot einrichten (Matrix + n8n)

Dies ist das Herzstuck: Der Bot-User "Ralf" in Matrix wird durch n8n
mit KI-Faehigkeiten ausgestattet.

### Matrix-Bot Setup
- [ ] Bot-User `ralf` ist bereits erstellt (8.1)
- [ ] Access-Token fuer Bot generieren:
  ```bash
  curl -XPOST -d '{"type":"m.login.password","user":"ralf","password":"<pw>"}' \
    "http://10.10.40.30:8008/_matrix/client/r0/login"
  ```
  → Access-Token speichern (fuer n8n)
- [ ] Raum erstellen: "#ralf-control:homelab.lan"
  - Kolja einladen
  - Ralf (Bot) einladen
- [ ] Raum erstellen: "#ralf-alerts:homelab.lan"
  - Fuer automatische Benachrichtigungen
- [ ] Raum erstellen: "#ralf-logs:homelab.lan"
  - Fuer ausfuehrliche Logs

### n8n-Workflows fuer Matrix

#### Workflow: Matrix Message Handler (Hauptworkflow)
- [ ] Trigger: Matrix Webhook oder Polling auf Raum #ralf-control
- [ ] Nachricht empfangen und parsen
- [ ] Intent erkennen (KI oder Regelbasiert):

  **Befehle die RALF verstehen soll:**

  | Befehl                    | Aktion                                      |
  |---------------------------|---------------------------------------------|
  | "status"                  | Alle Dienste pruefen, Zusammenfassung senden |
  | "status <dienst>"         | Einzelnen Dienst pruefen                     |
  | "deploy <dienst>"         | Semaphore-Pipeline starten                   |
  | "restart <dienst>"        | Dienst neu starten                           |
  | "logs <dienst>"           | Letzte Logs aus Loki zeigen                  |
  | "backup"                  | Backup-Workflow starten                      |
  | "health"                  | Network-Health-Check ausfuehren              |
  | "inventory"               | NetBox-Zusammenfassung zeigen                |
  | "hilfe"                   | Verfuegbare Befehle auflisten                |

- [ ] Aktion ausfuehren (via Sub-Workflows)
- [ ] Ergebnis als Matrix-Nachricht zurueckschicken

#### Workflow: Alert → Matrix
- [ ] Trigger: Prometheus Alertmanager Webhook
- [ ] Alert-Nachricht formatieren
- [ ] In #ralf-alerts posten

#### Workflow: Tagesbericht
- [ ] Trigger: Taeglich 08:00 Uhr
- [ ] Alle Dienste pruefen
- [ ] Zusammenfassung erstellen
- [ ] In #ralf-control posten:
  ```
  Guten Morgen, Kolja!
  RALF Tagesbericht (2026-02-12):
  - 14/14 Dienste online
  - Letzte Backups: OK (02:00)
  - Disk-Nutzung: 23% (svc-postgres), 12% (svc-gitea), ...
  - Keine offenen Incidents
  ```

### KI-Erweiterung (Claude API oder lokales LLM)
- [ ] Claude API-Key in n8n hinterlegen (oder lokales LLM wie Ollama)
- [ ] Workflow erweitern:
  - Unbekannte Befehle → an KI weiterleiten
  - KI kann RALF-Kontext (Dienste, IPs, Status) als System-Prompt bekommen
  - KI antwortet natuerlichsprachlich
  - Beispiel:
    - Kolja: "Warum ist Gitea langsam?"
    - Ralf: "Ich pruefe... CPU-Last auf svc-gitea ist bei 89%.
      PostgreSQL-Queries sind normal. Empfehlung: Container-Ressourcen
      erhoehen (aktuell 2GB RAM). Soll ich das machen?"
    - Kolja: "Ja, mach mal 4GB"
    - Ralf: "Aenderung geplant: RAM von svc-gitea auf 4GB erhoehen.
      Dafuer muss der Container neugestartet werden. Freigabe?"
    - Kolja: "Freigabe"
    - Ralf: "Aenderung wird ausgefuehrt... Fertig. Gitea laeuft
      wieder normal mit 4GB RAM."

### Benoetigte Credentials
- [ ] **Synapse DB-Passwort**
- [ ] **Synapse Registration Shared Secret**
- [ ] **Synapse Admin-Passwort** (Kolja)
- [ ] **Synapse Admin-Passwort** (Ralf/Bot)
- [ ] **Matrix Bot Access Token** (fuer n8n)
- [ ] **Claude API Key** (oder lokales LLM Setup)

### Abnahmekriterien
- [ ] Matrix/Synapse laeuft und ist ueber Element erreichbar
- [ ] Kolja kann sich in Element einloggen
- [ ] Bot "Ralf" ist im Raum #ralf-control
- [ ] Befehl "status" liefert Antwort im Chat
- [ ] Alerts erscheinen in #ralf-alerts
- [ ] Tagesbericht wird morgens gepostet
- [ ] KI-gesteuerte Konversation funktioniert
