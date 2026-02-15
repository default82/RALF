# Ansible Role: Dashy

Installiert und konfiguriert Dashy (modernes Dashboard) für RALF LXC-Container.

## Anforderungen

- Ubuntu 24.04 (Noble) oder 22.04 (Jammy)
- Ansible >= 2.15
- Mindestens 2GB RAM (npm install ist speicherintensiv)
- Internet-Zugang für npm Packages

## Installationsmethode

Diese Role installiert Dashy als **Git-Clone + npm dev server**, optimiert für schnelle Updates und Hot-Reload.

- Download: Git Clone von GitHub Repository
- Version: 3.1.1 (konfigurierbar via `dashy_version`)
- Runtime: Node.js 20 LTS + npm dev server
- Config: YAML-basiert in `/opt/dashy/user-data/conf.yml`

## Role-Variablen

### Installation
```yaml
dashy_repo_url: "https://github.com/Lissy93/dashy.git"
dashy_version: "3.1.1"  # Git tag or branch
dashy_install_dir: "/opt/dashy"
dashy_nodejs_version: "20"  # Node.js LTS
```

### Service
```yaml
dashy_listen_host: "0.0.0.0"
dashy_listen_port: 4000
dashy_node_env: "development"  # Use dev mode for hot-reload
```

### CORS Proxy (nginx)
```yaml
dashy_cors_proxy_enabled: true
dashy_cors_proxy_port: 8080
```

## CORS Proxy

Dashy benötigt einen CORS Proxy für Status-Checks externer Services. Diese Role installiert optional einen nginx-basierten CORS Proxy, der folgende Endpoints bereitstellt:

- `/gitea/` → `http://10.10.20.12:3000/`
- `/semaphore/` → `http://10.10.100.15:3000/`
- `/vault/` → `http://10.10.30.10:8080/`
- `/netbox/` → `http://10.10.40.30:8000/`
- `/snipeit/` → `http://10.10.40.40/`

**Zugriff:** `http://<dashy-ip>:8080/<service>/`

## Konfiguration

Die Dashy-Konfiguration erfolgt über `/opt/dashy/user-data/conf.yml`.

**Option 1: Manuelle Konfiguration**
```bash
# Nach Deployment
ansible <host> -m ansible.builtin.copy \
  -a "src=my-conf.yml dest=/opt/dashy/user-data/conf.yml"
ansible <host> -m ansible.builtin.systemd \
  -a "name=dashy state=restarted"
```

**Option 2: Template verwenden**
```yaml
# In Playbook
- role: dashy
  vars:
    dashy_config_template: "my-custom-conf.yml.j2"
```

Dann Template erstellen in `roles/dashy/templates/my-custom-conf.yml.j2`.

## Beispiel-Playbook

```yaml
---
- hosts: dashy_servers
  become: yes
  roles:
    - role: dashy
      dashy_version: "3.1.1"
      dashy_listen_port: 4000
      dashy_cors_proxy_enabled: true
```

## Post-Installation

1. **Dashboard:** `http://10.10.40.1:4000`
2. **CORS Proxy:** `http://10.10.40.1:8080`
3. **Config bearbeiten:**
   ```bash
   pct exec 4001 -- nano /opt/dashy/user-data/conf.yml
   pct exec 4001 -- systemctl restart dashy
   ```

## Idempotenz

Diese Role ist vollständig idempotent:
- Git Repository wird nur gecloned wenn nicht vorhanden
- npm install wird nur bei Änderungen ausgeführt
- Service-Restart nur bei Config-Änderungen (Handler)
- nginx nur installiert wenn `dashy_cors_proxy_enabled: true`

## Performance

- **npm install:** ~5-10 Minuten (timeout: 600s)
- **Dev Server Start:** ~30 Sekunden
- **Memory:** ~500MB im Betrieb
- **Hot-Reload:** Config-Änderungen erfordern Service-Restart

## Development Mode vs. Production

**Development Mode (default):**
- Hot-Reload aktiviert
- Webpack Dev Server
- Schnellere Iteration

**Production Mode:**
```yaml
dashy_node_env: "production"
dashy_listen_port: 80
```
- Optimized Build
- Bessere Performance
- Kein Hot-Reload

Für RALF Homelab ist **Development Mode empfohlen** (einfachere Updates).

## Troubleshooting

**npm install schlägt fehl:**
```bash
# Memory-Limit erhöhen
pct set 4001 -memory 4096
pct reboot 4001
```

**Service startet nicht:**
```bash
pct exec 4001 -- journalctl -u dashy -n 50
```

**CORS Errors:**
- Prüfe nginx läuft: `pct exec 4001 -- systemctl status nginx`
- Prüfe Port 8080 erreichbar: `curl http://10.10.40.1:8080`

## Lizenz

MIT

## Autor

RALF Homelab Project
