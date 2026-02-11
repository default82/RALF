# Phase 4 – Reverse Proxy & DNS (Caddy auf OPNsense)

Ziel: Alle Web-Dienste sind ueber lesbare URLs erreichbar (z.B. gitea.homelab.lan).
Caddy laeuft als **Plugin auf OPNsense** (os-caddy) – KEIN eigener LXC-Container.
Konfiguration erfolgt vollstaendig ueber die OPNsense REST API.

---

## 4.1 OPNsense Caddy Plugin vorbereiten

**Host:** opnsense | **IP:** 10.10.0.1

### Voraussetzungen
- [ ] OPNsense WebGUI-Port auf alternativen Port verschieben (z.B. 8443)
  - System → Settings → Administration → TCP Port: 8443
  - Caddy uebernimmt Port 80 und 443
- [ ] os-caddy Plugin installieren:
  - System → Firmware → Plugins → `os-caddy` installieren
  - ODER via API:
    ```bash
    curl -k -u "$API_KEY:$API_SECRET" \
      -X POST https://10.10.0.1:8443/api/core/firmware/install/os-caddy
    ```

### OPNsense API-Key erstellen
- [ ] System → Access → Users → [Admin-User] → API Keys → "+"
- [ ] Key + Secret herunterladen (Secret wird nur einmal angezeigt!)
- [ ] In Semaphore als Secrets hinterlegen:
  - `OPNSENSE_API_KEY`
  - `OPNSENSE_API_SECRET`
  - `OPNSENSE_URL=https://10.10.0.1:8443`

### Caddy aktivieren
- [ ] Via API:
  ```bash
  curl -k -u "$API_KEY:$API_SECRET" \
    -X POST https://10.10.0.1:8443/api/caddy/general/set \
    -H "Content-Type: application/json" \
    -d '{"general": {"enabled": "1"}}'
  ```
- [ ] Anwenden:
  ```bash
  curl -k -u "$API_KEY:$API_SECRET" \
    -X POST https://10.10.0.1:8443/api/caddy/service/reconfigure
  ```

---

## 4.2 Reverse-Proxy-Eintraege via API erstellen

### API-Workflow pro Dienst

Fuer jeden Dienst sind zwei API-Calls noetig:

**Schritt 1: Domain (Frontend) erstellen**
```bash
curl -k -u "$API_KEY:$API_SECRET" \
  -X POST https://10.10.0.1:8443/api/caddy/reverse_proxy/add_reverse_proxy \
  -H "Content-Type: application/json" \
  -d '{
    "reverse": {
      "enabled": "1",
      "FromDomain": "gitea.homelab.lan",
      "FromPort": "443",
      "Description": "Gitea – Self-hosted Git (P1)"
    }
  }'
```
→ Gibt UUID zurueck, z.B. `{"uuid": "abc-123-..."}`

**Schritt 2: Handle (Upstream/Backend) erstellen**
```bash
curl -k -u "$API_KEY:$API_SECRET" \
  -X POST https://10.10.0.1:8443/api/caddy/reverse_proxy/add_handle \
  -H "Content-Type: application/json" \
  -d '{
    "handle": {
      "enabled": "1",
      "reverse": "<domain-uuid>",
      "ToDomain": "10.10.20.12",
      "ToPort": "3000",
      "Description": "Gitea Backend"
    }
  }'
```

**Schritt 3: Validieren und anwenden**
```bash
curl -k -u "$API_KEY:$API_SECRET" \
  https://10.10.0.1:8443/api/caddy/service/validate

curl -k -u "$API_KEY:$API_SECRET" \
  -X POST https://10.10.0.1:8443/api/caddy/service/reconfigure
```

### Alle Reverse-Proxy-Eintraege

| Domain                    | Upstream-IP:Port       | Dienst       |
|---------------------------|------------------------|--------------|
| gitea.homelab.lan         | 10.10.20.12:3000       | Gitea        |
| semaphore.homelab.lan     | 10.10.100.15:3000      | Semaphore    |
| vault.homelab.lan         | 10.10.30.10:8080       | Vaultwarden  |
| grafana.homelab.lan       | 10.10.80.12:3000       | Grafana      |
| prometheus.homelab.lan    | 10.10.80.10:9090       | Prometheus   |
| netbox.homelab.lan        | 10.10.40.12:8000       | NetBox       |
| snipeit.homelab.lan       | 10.10.40.14:8080       | Snipe-IT     |
| n8n.homelab.lan           | 10.10.100.20:5678      | n8n          |
| synapse.homelab.lan       | 10.10.40.30:8008       | Synapse      |
| element.homelab.lan       | 10.10.40.32:8080       | Element      |

---

## 4.3 Ansible Playbook fuer Caddy-Konfiguration

Statt einer eigenen Rolle wird ein Playbook erstellt, das die OPNsense API
aufruft. Kein eigener Container, kein OpenTofu-Stack noetig.

### Playbook: `iac/ansible/playbooks/configure-caddy.yml`

```yaml
---
# Caddy Reverse Proxy auf OPNsense konfigurieren
# Verwendung: ansible-playbook playbooks/configure-caddy.yml \
#   --extra-vars "opnsense_api_key=KEY opnsense_api_secret=SECRET"

- name: RALF – Caddy Reverse Proxy via OPNsense API
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    opnsense_url: "https://10.10.0.1:8443"
    caddy_services:
      - { domain: "gitea.homelab.lan",      upstream: "10.10.20.12",  port: "3000", desc: "Gitea" }
      - { domain: "semaphore.homelab.lan",   upstream: "10.10.100.15", port: "3000", desc: "Semaphore" }
      - { domain: "vault.homelab.lan",       upstream: "10.10.30.10",  port: "8080", desc: "Vaultwarden" }
      - { domain: "grafana.homelab.lan",     upstream: "10.10.80.12",  port: "3000", desc: "Grafana" }
      - { domain: "prometheus.homelab.lan",  upstream: "10.10.80.10",  port: "9090", desc: "Prometheus" }
      - { domain: "netbox.homelab.lan",      upstream: "10.10.40.12",  port: "8000", desc: "NetBox" }
      - { domain: "snipeit.homelab.lan",     upstream: "10.10.40.14",  port: "8080", desc: "Snipe-IT" }
      - { domain: "n8n.homelab.lan",         upstream: "10.10.100.20", port: "5678", desc: "n8n" }
      - { domain: "synapse.homelab.lan",     upstream: "10.10.40.30",  port: "8008", desc: "Synapse" }
      - { domain: "element.homelab.lan",     upstream: "10.10.40.32",  port: "8080", desc: "Element" }

  tasks:
    - name: Bestehende Domains abfragen
      ansible.builtin.uri:
        url: "{{ opnsense_url }}/api/caddy/reverse_proxy/search_reverse_proxy"
        method: GET
        user: "{{ opnsense_api_key }}"
        password: "{{ opnsense_api_secret }}"
        force_basic_auth: true
        validate_certs: false
      register: existing_domains

    - name: Domain erstellen (falls nicht vorhanden)
      ansible.builtin.uri:
        url: "{{ opnsense_url }}/api/caddy/reverse_proxy/add_reverse_proxy"
        method: POST
        user: "{{ opnsense_api_key }}"
        password: "{{ opnsense_api_secret }}"
        force_basic_auth: true
        validate_certs: false
        body_format: json
        body:
          reverse:
            enabled: "1"
            FromDomain: "{{ item.domain }}"
            FromPort: "443"
            Description: "RALF – {{ item.desc }}"
      loop: "{{ caddy_services }}"
      loop_control:
        label: "{{ item.domain }}"
      when: "item.domain not in (existing_domains.json.rows | map(attribute='FromDomain') | list)"
      register: created_domains

    - name: Handle (Upstream) erstellen
      ansible.builtin.uri:
        url: "{{ opnsense_url }}/api/caddy/reverse_proxy/add_handle"
        method: POST
        user: "{{ opnsense_api_key }}"
        password: "{{ opnsense_api_secret }}"
        force_basic_auth: true
        validate_certs: false
        body_format: json
        body:
          handle:
            enabled: "1"
            reverse: "{{ item.uuid }}"
            ToDomain: "{{ caddy_services[idx].upstream }}"
            ToPort: "{{ caddy_services[idx].port }}"
            Description: "{{ caddy_services[idx].desc }} Backend"
      loop: "{{ created_domains.results | selectattr('json', 'defined') | map(attribute='json') | list }}"
      loop_control:
        index_var: idx
        label: "Handle fuer {{ caddy_services[idx].domain }}"
      when: item.uuid is defined

    - name: Konfiguration validieren
      ansible.builtin.uri:
        url: "{{ opnsense_url }}/api/caddy/service/validate"
        method: GET
        user: "{{ opnsense_api_key }}"
        password: "{{ opnsense_api_secret }}"
        force_basic_auth: true
        validate_certs: false

    - name: Konfiguration anwenden (reconfigure)
      ansible.builtin.uri:
        url: "{{ opnsense_url }}/api/caddy/service/reconfigure"
        method: POST
        user: "{{ opnsense_api_key }}"
        password: "{{ opnsense_api_secret }}"
        force_basic_auth: true
        validate_certs: false
```

### Aufgaben
- [ ] Playbook `iac/ansible/playbooks/configure-caddy.yml` erstellen
- [ ] Testen mit einem einzelnen Dienst (z.B. Gitea)
- [ ] Alle Dienste schrittweise hinzufuegen
- [ ] Pipeline: `pipelines/semaphore/configure-caddy.yaml`

---

## 4.4 DNS auf OPNsense konfigurieren

DNS-Eintraege ebenfalls via OPNsense API (Unbound DNS):

### API-Endpoint: `/api/unbound/settings/`

- [ ] Host-Overrides fuer alle Dienste erstellen (alle auf OPNsense-IP 10.10.0.1,
      da Caddy auf OPNsense laeuft):
  ```bash
  curl -k -u "$API_KEY:$API_SECRET" \
    -X POST https://10.10.0.1:8443/api/unbound/settings/addHostOverride \
    -H "Content-Type: application/json" \
    -d '{
      "host": {
        "enabled": "1",
        "hostname": "gitea",
        "domain": "homelab.lan",
        "server": "10.10.0.1",
        "description": "RALF – Gitea via Caddy"
      }
    }'
  ```

### Alle DNS-Eintraege (auf OPNsense-IP, da Caddy dort laeuft)

| Hostname                   | IP          | Beschreibung              |
|----------------------------|-------------|---------------------------|
| gitea.homelab.lan          | 10.10.0.1   | Via Caddy auf OPNsense    |
| semaphore.homelab.lan      | 10.10.0.1   | Via Caddy auf OPNsense    |
| vault.homelab.lan          | 10.10.0.1   | Via Caddy auf OPNsense    |
| grafana.homelab.lan        | 10.10.0.1   | Via Caddy auf OPNsense    |
| prometheus.homelab.lan     | 10.10.0.1   | Via Caddy auf OPNsense    |
| netbox.homelab.lan         | 10.10.0.1   | Via Caddy auf OPNsense    |
| snipeit.homelab.lan        | 10.10.0.1   | Via Caddy auf OPNsense    |
| n8n.homelab.lan            | 10.10.0.1   | Via Caddy auf OPNsense    |
| synapse.homelab.lan        | 10.10.0.1   | Via Caddy auf OPNsense    |
| element.homelab.lan        | 10.10.0.1   | Via Caddy auf OPNsense    |

Zusaetzlich direkte A-Records:

| Hostname                   | IP            | Beschreibung            |
|----------------------------|---------------|-------------------------|
| svc-postgres.homelab.lan   | 10.10.20.10   | Direkter DB-Zugriff     |
| svc-mail.homelab.lan       | 10.10.40.10   | SMTP/IMAP direkt        |
| ops-semaphore.homelab.lan  | 10.10.100.15  | Direkter Zugriff        |

- [ ] DNS-Ansible-Playbook erstellen: `iac/ansible/playbooks/configure-dns.yml`
- [ ] Gleiche Struktur wie Caddy-Playbook (OPNsense API, `ansible.builtin.uri`)

---

## 4.5 Smoke Test

### `tests/caddy/smoke.sh`
- [ ] HTTPS-Check ueber OPNsense fuer jeden konfigurierten Dienst:
  ```bash
  curl -sk https://gitea.homelab.lan --resolve gitea.homelab.lan:443:10.10.0.1
  ```
- [ ] Caddyfile via API abrufen und pruefen:
  ```bash
  curl -k -u "$API_KEY:$API_SECRET" \
    https://10.10.0.1:8443/api/caddy/diagnostics/caddyfile
  ```
- [ ] DNS-Aufloesung testen: `dig gitea.homelab.lan @10.10.0.1`

---

## 4.6 Spaeter: Externe Erreichbarkeit (otta.zone)

- [ ] Caddy-Domains fuer externe Zugriffe erweitern (gitea.otta.zone)
- [ ] OPNsense Port-Forwarding: 80/443 → localhost (Caddy laeuft lokal)
- [ ] Let's Encrypt statt interne CA fuer externe Domains

---

## Kein eigener Container noetig!

Da Caddy als OPNsense-Plugin laeuft:
- ~~OpenTofu Stack: `iac/stacks/caddy-fz/`~~ → NICHT NOETIG
- ~~Bootstrap Script: `bootstrap/create-caddy.sh`~~ → NICHT NOETIG
- ~~Ansible Role: `iac/ansible/roles/caddy/`~~ → NICHT NOETIG
- ~~Inventory-Eintrag fuer svc-caddy~~ → NICHT NOETIG

Stattdessen:
- [x] Ansible Playbook `configure-caddy.yml` (OPNsense API)
- [x] Ansible Playbook `configure-dns.yml` (OPNsense API)

---

## Benoetigte Credentials
- [ ] **OPNsense API Key** (System → Access → Users → API Keys)
- [ ] **OPNsense API Secret** (wird bei Erstellung angezeigt, einmal kopieren!)

## Abnahmekriterien
- [ ] Caddy-Plugin auf OPNsense aktiv
- [ ] HTTPS-Zugriff auf alle konfigurierten Domains funktioniert
- [ ] TLS-Zertifikate werden automatisch erstellt (interne CA)
- [ ] DNS-Aufloesung fuer alle .homelab.lan Domains funktioniert
- [ ] Alle Dienste ueber ihre .homelab.lan Domain erreichbar
