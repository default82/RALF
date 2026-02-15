# Ansible Role: NetBox

Installiert und konfiguriert NetBox (IPAM/DCIM) für RALF LXC-Container.

## Anforderungen

- Ubuntu 24.04 (Noble) oder 22.04 (Jammy)
- Ansible >= 2.15
- PostgreSQL-Server erreichbar (10.10.20.10:5432)
- Redis wird automatisch installiert (localhost)
- Mindestens 2GB RAM
- Environment-Variablen: `NETBOX_PG_PASS`, `NETBOX_SECRET_KEY`

## Was ist NetBox?

NetBox ist eine **IP Address Management (IPAM)** und **Data Center Infrastructure Management (DCIM)** Plattform. Es dient als "Single Source of Truth" für:

- IP-Adressen und Subnetze
- VLANs und VRFs
- Racks, Geräte und Verkabelung
- Schaltkreise und Provider
- Virtuelle Maschinen

## Installationsmethode

Diese Role installiert NetBox als **Python/Django Application** (kein Docker), optimiert für LXC-Container.

- Download: Official GitHub Release Tarball
- Version: 5.0.10 (konfigurierbar via `netbox_version`)
- Runtime: Python 3.12 + gunicorn WSGI Server
- Database: PostgreSQL (required)
- Cache: Redis (automatisch installiert)
- Web Server: nginx als Reverse Proxy

## Role-Variablen

### Installation
```yaml
netbox_version: "5.0.10"
netbox_install_dir: "/opt/netbox"
netbox_user: "netbox"
netbox_group: "netbox"
```

### Database (PostgreSQL)
```yaml
netbox_db_host: "10.10.20.10"
netbox_db_port: 5432
netbox_db_name: "netbox"
netbox_db_user: "netbox_user"
netbox_db_password: "{{ lookup('env', 'NETBOX_PG_PASS') }}"
```

### Redis (Cache)
```yaml
netbox_redis_host: "localhost"
netbox_redis_port: 6379
netbox_redis_database_tasks: 0      # Für Background Tasks
netbox_redis_database_caching: 1    # Für Caching
```

### Security
```yaml
netbox_secret_key: "{{ lookup('env', 'NETBOX_SECRET_KEY') }}"
netbox_allowed_hosts: ['*']
```

### Gunicorn (WSGI Server)
```yaml
netbox_gunicorn_bind: "0.0.0.0:8000"
netbox_gunicorn_workers: 4
netbox_gunicorn_timeout: 120
```

### nginx
```yaml
netbox_nginx_enabled: true
netbox_nginx_listen_port: 80
```

### Superuser (optional)
```yaml
netbox_create_superuser: true
netbox_superuser_username: "admin"
netbox_superuser_email: "admin@homelab.lan"
netbox_superuser_password: "{{ lookup('env', 'NETBOX_ADMIN_PASS') }}"
```

## Abhängigkeiten

### PostgreSQL-Datenbank

Die PostgreSQL-Datenbank muss **vor dem Deployment** erstellt werden:

```bash
PGPASSWORD="$POSTGRES_MASTER_PASS" psql -h 10.10.20.10 -U postgres <<EOF
CREATE USER netbox_user WITH PASSWORD '$NETBOX_PG_PASS';
CREATE DATABASE netbox OWNER netbox_user;
GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox_user;
EOF
```

Oder via Ansible Playbook:
```bash
ansible-playbook playbooks/provision-databases.yml -e target=netbox
```

### Secret Key

NetBox benötigt einen Secret Key für Kryptographie:

```bash
# Generieren (50+ Zeichen, zufällig)
openssl rand -base64 48

# In credentials.env speichern
echo "NETBOX_SECRET_KEY='<generated-key>'" >> /var/lib/ralf/credentials.env
```

## Beispiel-Playbook

```yaml
---
- hosts: netbox_servers
  become: yes
  roles:
    - role: netbox
      netbox_version: "5.0.10"
      netbox_create_superuser: true
```

## Post-Installation

1. **Web-UI:** `http://10.10.40.30` (nginx) oder `http://10.10.40.30:8000` (gunicorn direkt)
2. **Login:** Verwende Superuser-Credentials wenn `netbox_create_superuser: true`
3. **Admin-Panel:** `http://10.10.40.30/admin/`

## Deployment-Schritte (intern)

Diese Role führt automatisch folgende Schritte aus:

1. System-Packages installieren (Python, PostgreSQL client, Redis, nginx)
2. NetBox User/Group erstellen (uid 999, gid 990)
3. NetBox Tarball herunterladen und extrahieren
4. Python Virtual Environment erstellen (`/opt/netbox/venv`)
5. Python Dependencies installieren (`base_requirements.txt`)
6. Konfiguration deployen (`configuration.py`)
7. Database Migrations ausführen (`manage.py migrate`)
8. Static Files sammeln (`manage.py collectstatic`)
9. Superuser erstellen (optional, via Django Shell)
10. gunicorn systemd Service erstellen und starten
11. Redis konfigurieren (localhost-only)
12. nginx als Reverse Proxy konfigurieren

## Idempotenz

Diese Role ist vollständig idempotent:
- Tarball wird nur heruntergeladen wenn NetBox fehlt
- Migrations werden nur ausgeführt wenn nötig (`--no-input`)
- Static Files werden nur gesammelt bei Änderungen
- Superuser wird nur erstellt wenn nicht vorhanden
- Service-Restarts nur bei Config-Änderungen (Handler)

## Django Management Commands

Nützliche Commands für Post-Deployment:

```bash
# Shell Access
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py shell

# Superuser erstellen (manuell)
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py createsuperuser

# Migrations anzeigen
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py showmigrations

# Cache leeren
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py invalidate all
```

## Verzeichnisstruktur

```
/opt/netbox/
├── venv/                    # Python Virtual Environment
├── netbox/                  # Django Application
│   ├── manage.py           # Django Management CLI
│   ├── netbox/             # NetBox Core
│   │   └── configuration.py  # Main Config (deployed by Ansible)
│   ├── static/             # Collected Static Files
│   ├── media/              # User Uploads
│   ├── reports/            # Custom Reports
│   └── scripts/            # Custom Scripts
└── base_requirements.txt   # Python Dependencies
```

## Architektur

```
User → nginx (Port 80) → gunicorn (Port 8000) → Django/NetBox
                          ↓                      ↓
                     PostgreSQL           Redis (localhost:6379)
                    (10.10.20.10:5432)    ├─ DB 0: Tasks
                                          └─ DB 1: Caching
```

## Performance

- **Installation:** ~5-10 Minuten (Download + pip install + migrations)
- **Startup:** ~10-15 Sekunden
- **Memory:** ~800MB im Betrieb (4 gunicorn workers)
- **gunicorn Workers:** 4 (konfigurierbar)
- **Max Requests:** 5000 pro Worker (auto-restart)

## Troubleshooting

**Database Connection Error:**
```bash
# Prüfe PostgreSQL erreichbar
pct exec 4030 -- psql -h 10.10.20.10 -U netbox_user -d netbox -c "SELECT 1"

# Prüfe Datenbank existiert
PGPASSWORD="$POSTGRES_MASTER_PASS" psql -h 10.10.20.10 -U postgres -l | grep netbox
```

**Redis Connection Error:**
```bash
# Prüfe Redis läuft
pct exec 4030 -- systemctl status redis-server

# Test Redis
pct exec 4030 -- redis-cli ping
```

**Migrations Failed:**
```bash
# Zeige Migrations-Status
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py showmigrations

# Force Migrate
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py migrate --run-syncdb
```

**Service startet nicht:**
```bash
# Logs prüfen
pct exec 4030 -- journalctl -u netbox -n 100

# Manueller Test
pct exec 4030 -- sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py runserver 0.0.0.0:8001
```

## Sicherheits-Features

- Dedizierter System-User (kein Root)
- PostgreSQL-Passwörter aus Environment-Variablen
- Secret Key aus Environment-Variablen
- Redis nur auf localhost
- Systemd-Hardening (PrivateTmp)
- nginx als Application Firewall

## Lizenz

MIT

## Autor

RALF Homelab Project
