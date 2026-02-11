# Phase 5 – Observability (Prometheus, Grafana, Loki)

Ziel: Alle RALF-Dienste werden ueberwacht. Metriken, Logs und Alerts
sind zentral einsehbar. Bei Stoerungen wird automatisch benachrichtigt.

---

## 5.1 Prometheus deployen

**Hostname:** svc-prometheus | **IP:** 10.10.80.10 | **CT-ID:** 8010

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/prometheus-fz/`
- [ ] `tofu/versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`
- [ ] Variablen: ct_id=8010, hostname=svc-prometheus, ip=10.10.80.10/16
- [ ] Memory: 2048, Disk: 32 (Metriken brauchen Platz)
- [ ] `env/functional.tfvars`, `README.md`

#### Terragrunt: `iac/stacks/prometheus-fz/terragrunt.hcl`

#### Ansible Role: `iac/ansible/roles/prometheus/`
- [ ] `tasks/main.yml`:
  - Prometheus-Binary herunterladen
  - User + Verzeichnisse erstellen
  - Konfiguration deployen (`prometheus.yml`)
  - Systemd-Service erstellen
  - Aktivieren und starten
- [ ] `handlers/main.yml`: restart prometheus
- [ ] `templates/prometheus.yml.j2`:
  ```yaml
  global:
    scrape_interval: 30s
    evaluation_interval: 30s

  scrape_configs:
    - job_name: 'prometheus'
      static_configs:
        - targets: ['localhost:9090']

    - job_name: 'node-exporter'
      static_configs:
        - targets:
          - '10.10.20.10:9100'   # PostgreSQL
          - '10.10.20.12:9100'   # Gitea
          - '10.10.30.10:9100'   # Vaultwarden
          - '10.10.40.10:9100'   # Mail
          - '10.10.40.20:9100'   # Caddy
          - '10.10.80.10:9100'   # Prometheus
          - '10.10.80.12:9100'   # Grafana
          - '10.10.80.14:9100'   # Loki
          - '10.10.100.15:9100'  # Semaphore
          - '10.10.100.20:9100'  # n8n

    - job_name: 'postgresql'
      static_configs:
        - targets: ['10.10.20.10:9187']

    - job_name: 'caddy'
      static_configs:
        - targets: ['10.10.40.20:2019']
  ```

#### Node Exporter auf allen Containern (Ansible)
- [ ] Neue Rolle: `iac/ansible/roles/node-exporter/`
  - Binary herunterladen
  - Systemd-Service
  - Port 9100
- [ ] In `base` Role integrieren oder als separate Rolle
- [ ] Alle Playbooks um node-exporter erweitern

#### PostgreSQL Exporter
- [ ] Auf svc-postgres installieren (Port 9187)
- [ ] In postgresql-Rolle integrieren

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-prometheus.yml`
- [ ] `bootstrap/create-prometheus.sh` (CT-ID: 8010)
- [ ] `tests/prometheus/smoke.sh` (HTTP 9090, /api/v1/status/config)
- [ ] `pipelines/semaphore/deploy-prometheus.yaml`

### Inventory + Service-Steckbrief
- [ ] hosts.yml: Gruppe `monitoring`, Host svc-prometheus
- [ ] `services/prometheus.md`
- [ ] runtime.env: PROMETHEUS_IP, PROMETHEUS_PORT

---

## 5.2 Loki deployen

**Hostname:** svc-loki | **IP:** 10.10.80.14 | **CT-ID:** 8014

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/loki-fz/`
- [ ] Standard-Stack (variables, main, outputs, versions, tfvars)
- [ ] ct_id=8014, ip=10.10.80.14/16, memory=2048, disk=32

#### Ansible Role: `iac/ansible/roles/loki/`
- [ ] `tasks/main.yml`:
  - Loki-Binary herunterladen
  - User + Verzeichnisse
  - Konfiguration (`loki-config.yaml`)
  - Systemd-Service
- [ ] `templates/loki-config.yaml.j2`:
  ```yaml
  auth_enabled: false
  server:
    http_listen_port: 3100
  common:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    path_prefix: /var/lib/loki
  schema_config:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
  storage_config:
    filesystem:
      directory: /var/lib/loki/chunks
  ```

#### Promtail auf allen Containern
- [ ] Neue Rolle: `iac/ansible/roles/promtail/`
  - Binary herunterladen
  - Konfiguration (system logs → Loki)
  - Systemd-Service
- [ ] In base-Rolle integrieren oder separat
- [ ] Alle Container senden Logs an svc-loki:3100

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-loki.yml`
- [ ] `bootstrap/create-loki.sh` (CT-ID: 8014)
- [ ] `tests/loki/smoke.sh` (HTTP 3100, /ready)
- [ ] `pipelines/semaphore/deploy-loki.yaml`

### Inventory + Service-Steckbrief
- [ ] hosts.yml: svc-loki in Gruppe `monitoring`
- [ ] `services/loki.md`

---

## 5.3 Grafana deployen

**Hostname:** svc-grafana | **IP:** 10.10.80.12 | **CT-ID:** 8012

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/grafana-fz/`
- [ ] Standard-Stack
- [ ] ct_id=8012, ip=10.10.80.12/16, memory=1024, disk=16

#### Ansible Role: `iac/ansible/roles/grafana/`
- [ ] `tasks/main.yml`:
  - Grafana installieren (offizielles APT-Repo)
  - Konfiguration deployen (`grafana.ini`)
  - Datasources provisionieren (Prometheus + Loki)
  - Standard-Dashboards provisionieren
  - Aktivieren und starten
- [ ] `templates/grafana.ini.j2`:
  ```ini
  [server]
  http_port = 3000
  domain = grafana.homelab.lan
  root_url = https://grafana.homelab.lan

  [security]
  admin_user = kolja
  admin_password = {{ grafana_admin_pass }}

  [smtp]
  enabled = true
  host = 10.10.40.10:587
  from_address = grafana@homelab.lan

  [auth.anonymous]
  enabled = false
  ```
- [ ] `files/datasources.yaml`:
  ```yaml
  apiVersion: 1
  datasources:
    - name: Prometheus
      type: prometheus
      url: http://10.10.80.10:9090
      isDefault: true
    - name: Loki
      type: loki
      url: http://10.10.80.14:3100
  ```
- [ ] `files/dashboards/` – Standard-Dashboards:
  - RALF Overview (alle Dienste Status)
  - Node Exporter (CPU, RAM, Disk pro Container)
  - PostgreSQL Metrics
  - Netzwerk-Uebersicht

### Zweiten Admin-Account anlegen
- [ ] Via Grafana API nach Erststart:
  ```bash
  curl -X POST http://kolja:<pass>@10.10.80.12:3000/api/admin/users \
    -H "Content-Type: application/json" \
    -d '{"name":"ralf","email":"ralf@homelab.lan","login":"ralf","password":"<pass>"}'
  ```
- [ ] Ralf-User zum Admin machen:
  ```bash
  curl -X PUT http://kolja:<pass>@10.10.80.12:3000/api/admin/users/ralf/permissions \
    -H "Content-Type: application/json" \
    -d '{"isGrafanaAdmin": true}'
  ```

### Alerting konfigurieren
- [ ] Alert-Rules fuer kritische Dienste:
  - PostgreSQL down
  - Gitea down
  - Semaphore down
  - Disk > 85%
  - RAM > 90%
- [ ] Notification Channel: E-Mail an kolja@homelab.lan
- [ ] Spaeter: Matrix-Notification (Phase 8)

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-grafana.yml`
- [ ] `bootstrap/create-grafana.sh` (CT-ID: 8012)
- [ ] `tests/grafana/smoke.sh` (HTTP 3000, /api/health)
- [ ] `pipelines/semaphore/deploy-grafana.yaml`

### Inventory + Service-Steckbrief
- [ ] hosts.yml: svc-grafana in Gruppe `monitoring`
- [ ] `services/grafana.md`

### Benoetigte Credentials (Phase 5 gesamt)
- [ ] **Grafana Admin-Passwort** (Kolja)
- [ ] **Grafana Admin-Passwort** (Ralf)
- [ ] Keine fuer Prometheus und Loki (kein Auth im internen Netz)

### Abnahmekriterien (Phase 5 gesamt)
- [ ] Prometheus scrapt alle Targets erfolgreich
- [ ] Loki empfaengt Logs von allen Containern
- [ ] Grafana zeigt Metriken und Logs an
- [ ] RALF Overview Dashboard ist funktional
- [ ] Alerts fuer kritische Dienste sind aktiv
- [ ] Alle drei Dienste ueber Caddy erreichbar
