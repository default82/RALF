# Caddy Deployment-Strategie für RALF

## Problem

OPNsense Caddy-Plugin erlaubt keine Config-Automation via API/Ansible.

## Lösung: Dedizierter Caddy LXC Container

### Architektur

```
┌─────────────────────────────────────────────────────────┐
│ Internet                                                 │
└────────────────┬────────────────────────────────────────┘
                 │
        ┌────────▼────────┐
        │   OPNsense      │
        │  10.10.0.1      │
        │ Firewall/Router │
        │                 │
        │ Port Forward:   │
        │ 80  → Caddy:80  │
        │ 443 → Caddy:443 │
        └────────┬────────┘
                 │
        ┌────────▼────────┐
        │   Caddy LXC     │
        │  10.10.40.20    │ ← Neue IP
        │  CT 4020        │
        │                 │
        │ Managed by:     │
        │ - Ansible       │
        │ - Git (Caddyfile)│
        └────────┬────────┘
                 │
        ┌────────┴────────┬──────────┬──────────┐
        │                 │          │          │
   ┌────▼────┐     ┌─────▼─────┐  ┌─▼────┐  ┌──▼──────┐
   │ Gitea   │     │ Semaphore │  │Dashy │  │Vaultwdn │
   │:3000    │     │:3000      │  │:4000 │  │:8080    │
   └─────────┘     └───────────┘  └──────┘  └─────────┘
```

### Vorteile

✅ **Vollständige Ansible-Kontrolle**
- Caddyfile als Jinja2-Template
- Versionierung in Git
- Idempotente Deployments

✅ **RALF-Prinzipien-konform**
- LXC-first
- Infrastructure as Code
- Snapshots für Rollback
- Keine manuelle Konfiguration

✅ **Einfache Wartung**
- Neue Services: Caddyfile ergänzen, `ansible-playbook` → fertig
- Kein Web-UI-Klicken mehr nötig
- Automatic HTTPS via Let's Encrypt

✅ **Bessere Kontrolle**
- Caddy-Version selbst bestimmen
- Custom Caddy-Module möglich
- Logging/Monitoring einfacher

### Nachteile

⚠️ **Ein Service mehr**
- Zusätzlicher Container zu verwalten
- Aber: Wird komplett von Ansible/Semaphore gemanaged

⚠️ **OPNsense Caddy-Plugin ungenutzt**
- Plugin kann deaktiviert bleiben
- Kein Problem, da dedizierter Container besser

---

## Implementation

### Container Specs

```yaml
CT-ID: 4020
IP: 10.10.40.11:4000
Hostname: svc-caddy
Zone: Functional (-fz)
Resources:
  Memory: 512 MB
  Cores: 1
  Disk: 4 GB
OS: Ubuntu 24.04
```

### Caddyfile Template (Ansible-managed)

```caddyfile
# Managed by Ansible - DO NOT EDIT MANUALLY
# Template: roles/caddy/templates/Caddyfile.j2

{
    email {{ caddy_acme_email }}
    log {
        level INFO
    }
}

{% for service in caddy_services %}
{{ service.domain }} {
    reverse_proxy {{ service.backend_ip }}:{{ service.backend_port }}

    log {
        output file /var/log/caddy/{{ service.name }}.log
    }

    {% if service.headers | default([]) %}
    header {
        {% for header in service.headers %}
        {{ header.key }} {{ header.value }}
        {% endfor %}
    }
    {% endif %}
}

{% endfor %}
```

### Ansible Playbook Struktur

```yaml
# playbooks/deploy-caddy.yml
---
- name: Deploy Caddy Reverse Proxy
  hosts: svc-caddy
  roles:
    - base
    - caddy

# roles/caddy/defaults/main.yml
---
caddy_version: "2.8.4"
caddy_acme_email: "{{ lookup('env', 'CADDY_ACME_EMAIL') }}"
caddy_services:
  - name: gitea
    domain: gitea.otta.zone
    backend_ip: 10.10.20.12
    backend_port: 3000

  - name: semaphore
    domain: semaphore.otta.zone
    backend_ip: 10.10.100.15
    backend_port: 3000

  - name: dashy
    domain: dashy.otta.zone
    backend_ip: 10.10.40.11
    backend_port: 4000

  - name: vaultwarden
    domain: vault.otta.zone
    backend_ip: 10.10.30.10
    backend_port: 8080
    headers:
      - key: "X-Frame-Options"
        value: "SAMEORIGIN"
```

### Ansible Tasks (Auszug)

```yaml
# roles/caddy/tasks/main.yml
---
- name: Install Caddy
  apt:
    deb: "https://github.com/caddyserver/caddy/releases/download/v{{ caddy_version }}/caddy_{{ caddy_version }}_linux_amd64.deb"
    state: present

- name: Create Caddy directories
  file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - /etc/caddy
    - /var/log/caddy
    - /var/lib/caddy

- name: Deploy Caddyfile
  template:
    src: Caddyfile.j2
    dest: /etc/caddy/Caddyfile
    owner: root
    group: root
    mode: '0644'
    validate: 'caddy validate --config %s'
  notify: Reload Caddy

- name: Enable and start Caddy
  systemd:
    name: caddy
    enabled: yes
    state: started

# roles/caddy/handlers/main.yml
---
- name: Reload Caddy
  systemd:
    name: caddy
    state: reloaded
```

---

## Migration von OPNsense Caddy → Eigener Container

### Schritt 1: Container deployen

```bash
cd /root/ralf
bash bootstrap/create-caddy.sh  # Neu zu erstellen
```

### Schritt 2: OPNsense anpassen

1. **Port-Forwards ändern**:
   - `80 → 10.10.40.20:80` (statt OPNsense selbst)
   - `443 → 10.10.40.20:443`

2. **Caddy-Plugin deaktivieren** (optional):
   - Services → Caddy → General Settings → Disabled

### Schritt 3: Ansible Deployment

```bash
cd /root/ralf/iac
ansible-playbook ansible/playbooks/deploy-caddy.yml
```

### Schritt 4: Testen

```bash
curl https://gitea.otta.zone
curl https://semaphore.otta.zone
curl https://dashy.otta.zone
curl https://vault.otta.zone
```

---

## Vorteile für RALF-Philosophie

### 1. Infrastructure as Code
✅ Caddyfile versioniert in Git
✅ Deklarative Service-Definition
✅ Reproduzierbare Deployments

### 2. Automation
✅ Semaphore kann Caddy-Änderungen deployen
✅ Kein manueller Web-UI-Zugriff nötig
✅ CI/CD-Pipeline-Integration möglich

### 3. Observability
✅ Strukturierte Logs pro Service
✅ Monitoring via Prometheus Exporter (Caddy-Plugin)
✅ Access-Logs für Analyse

### 4. Security
✅ Automatic HTTPS mit Let's Encrypt
✅ Security-Header zentral managebar
✅ Rate-Limiting konfigurierbar

---

## Neue Services hinzufügen

### Mit OPNsense Caddy (aktuell):
1. Web-UI öffnen
2. Domain anlegen (Formular)
3. Handler anlegen (Formular)
4. Apply klicken
5. Testen

**Zeit**: ~5 Minuten manuell

### Mit eigenem Caddy-Container:
1. `inventory/caddy_services.yml` bearbeiten:
   ```yaml
   - name: netbox
     domain: netbox.otta.zone
     backend_ip: 10.10.40.30
     backend_port: 8000
   ```
2. `ansible-playbook deploy-caddy.yml`
3. Git commit

**Zeit**: ~30 Sekunden, vollautomatisch

---

## Entscheidung

### Behalte OPNsense Caddy, wenn:
- ❌ Du nur 2-3 Services hast und selten änderst
- ❌ Web-UI-Konfiguration OK ist
- ❌ Keine Automation gewünscht

### Nutze eigenen Caddy-Container, wenn:
- ✅ **RALF-Prinzipien wichtig sind** (IaC, Automation)
- ✅ Viele Services (>5) zu managen
- ✅ Häufige Änderungen
- ✅ **Semaphore-Integration gewünscht**
- ✅ Config in Git versioniert sein soll

**Für RALF: Eigener Container = klare Empfehlung** ✅

---

## Timeline

| Phase | Dauer | Aufgaben |
|-------|-------|----------|
| **Phase 1: Vorbereitung** | 1h | Bootstrap-Skript schreiben, Ansible-Role erstellen |
| **Phase 2: Deployment** | 30min | Container erstellen, Caddy installieren, Caddyfile deployen |
| **Phase 3: Migration** | 30min | OPNsense Port-Forwards umleiten, DNS testen |
| **Phase 4: Cleanup** | 15min | OPNsense Caddy-Plugin deaktivieren |
| **Gesamt** | ~2-3h | Einmalig, dann vollautomatisch |

---

## Nächste Schritte

1. **Entscheidung**: Eigener Caddy-Container oder OPNsense-Plugin?
2. **Wenn eigener Container**: Bootstrap-Skript + Ansible-Role erstellen
3. **Wenn OPNsense-Plugin**: Web-UI-Guide befolgen (bereits erstellt)
