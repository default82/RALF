# Ansible Role: Vaultwarden

Installiert und konfiguriert Vaultwarden (Bitwarden-kompatibler Password Manager) für RALF LXC-Container.

## Anforderungen

- Ubuntu 24.04 (Noble) oder 22.04 (Jammy)
- Ansible >= 2.15
- PostgreSQL-Server erreichbar (10.10.20.10:5432)
- Environment-Variablen: `VAULTWARDEN_PG_PASS`, `VAULTWARDEN_ADMIN_TOKEN`
- LXC Container mit `nesting=1` (für Docker)

## Installationsmethode

Diese Role installiert Vaultwarden als **Docker Container** (Official Method), optimiert für LXC-Container.

**Warum Docker?**
- Vaultwarden publiziert **keine Pre-Compiled Binaries**
- Docker ist die offizielle Deployment-Methode
- Updates einfacher (Pull-Strategie)
- Konsistent mit Official Documentation

**Komponenten:**
- Docker Engine + Docker Compose Plugin
- Vaultwarden Container (vaultwarden/server:{{ vaultwarden_version }})
- PostgreSQL Backend (extern: 10.10.20.10:5432)
- systemd-Integration (docker-compose managed)

## Role-Variablen

### Docker Image
```yaml
vaultwarden_docker_image: "vaultwarden/server"
vaultwarden_version: "1.32.7"
```

### Netzwerk
```yaml
vaultwarden_listen_address: "0.0.0.0"
vaultwarden_listen_port: 8080
vaultwarden_domain: "vault.homelab.lan"
```

### Datenbank
```yaml
vaultwarden_database_url: "postgresql://vaultwarden_user:PASSWORD@10.10.20.10:5432/vaultwarden"
```

### Sicherheit
```yaml
vaultwarden_signups_allowed: false    # Registrierung deaktiviert
vaultwarden_invitations_allowed: true  # Nur per Einladung
vaultwarden_admin_token: "..."         # Admin-Panel-Zugriff
```

### Backup
```yaml
vaultwarden_backup_enabled: true
vaultwarden_backup_dir: "/var/backups/vaultwarden"
vaultwarden_backup_retention_days: 7
```

## Abhängigkeiten

- PostgreSQL-Server muss laufen
- Datenbank `vaultwarden` wird NICHT automatisch erstellt (manuell oder via `provision-databases.yml`)
- LXC Container benötigt `nesting=1` für Docker

## Container-Konfiguration

**LXC Container Setup (Proxmox):**
```bash
pct set 3010 -features nesting=1,keyctl=1
```

Ohne `nesting=1` kann Docker nicht im LXC-Container laufen!

## Beispiel-Playbook

```yaml
---
- hosts: vaultwarden_servers
  become: yes
  roles:
    - role: vaultwarden
      vaultwarden_domain: "vault.homelab.lan"
      vaultwarden_signups_allowed: false
```

## Post-Installation

1. **Admin-Panel:** `http://10.10.30.10:8080/admin` (mit Admin-Token)
2. **Web Vault:** `http://10.10.30.10:8080`
3. **API:** `http://10.10.30.10:8080/api`
4. **Health Check:** `http://10.10.30.10:8080/alive`

## Datenbank-Setup

Vor dem Deployment muss die PostgreSQL-Datenbank manuell erstellt werden:

```bash
PGPASSWORD="$POSTGRES_MASTER_PASS" psql -h 10.10.20.10 -U postgres <<EOF
CREATE USER vaultwarden_user WITH PASSWORD '$VAULTWARDEN_PG_PASS';
CREATE DATABASE vaultwarden OWNER vaultwarden_user;
GRANT ALL PRIVILEGES ON DATABASE vaultwarden TO vaultwarden_user;
EOF
```

Oder via Ansible Playbook:
```bash
ansible-playbook playbooks/provision-databases.yml -e target=vaultwarden
```

## Idempotenz

Diese Role ist vollständig idempotent:
- Docker wird nur installiert wenn nicht vorhanden
- Docker Compose file wird nur überschrieben wenn geändert (Handler)
- Container-Restart nur bei Compose-File-Änderungen
- Verzeichnisse nur erstellt wenn nicht existent

## Service-Management

```bash
# Status prüfen
systemctl status vaultwarden

# Container-Logs ansehen
docker logs vaultwarden

# Container neu starten
systemctl restart vaultwarden

# Container stoppen/starten
systemctl stop vaultwarden
systemctl start vaultwarden

# Docker Compose direkt (im Install-Dir)
cd /opt/vaultwarden
docker compose logs -f
docker compose ps
```

## Sicherheits-Features

- Docker Container-Isolation
- Systemd-Integration (Restart on failure)
- Health Checks (alle 30s)
- Signups standardmäßig deaktiviert
- Admin-Token-geschützt
- PostgreSQL statt SQLite (bessere Datensicherheit)
- Resource Limits (CPU: 1 Core, Memory: 512MB)

## Performance

- Worker-Threads: 10 (konfigurierbar)
- Icon-Cache: 30 Tage TTL
- Resource Limits: 512MB RAM, 1 CPU
- Health Checks alle 30s

## Updates

Container-Updates via systemd:
```bash
systemctl restart vaultwarden
# systemd führt automatisch "docker compose pull" aus
```

Oder manuell:
```bash
cd /opt/vaultwarden
docker compose pull
docker compose up -d
```

## Troubleshooting

**Docker nicht installiert:**
```bash
docker --version
# Falls nicht installiert: Role erneut ausführen
```

**Container läuft nicht:**
```bash
docker ps -a
docker logs vaultwarden
```

**Datenbank-Verbindung:**
```bash
# Von Vaultwarden-Container aus
docker exec -it vaultwarden sh
apk add postgresql-client
psql "$DATABASE_URL" -c "SELECT 1"
```

**Port nicht erreichbar:**
```bash
ss -tlnp | grep 8080
curl http://localhost:8080/alive
```

## Bekannte Einschränkungen

- **Keine Pre-Compiled Binaries:** Vaultwarden publiziert nur Docker Images
- **Docker-in-LXC:** Benötigt `nesting=1` Feature
- **Resource Overhead:** Docker hat etwas mehr Memory-Overhead als Binary

## Migration von Binary zu Docker

**Falls bereits Binary-Installation existiert:**
1. Backup erstellen: `tar czf /tmp/vaultwarden-backup.tar.gz /var/lib/vaultwarden`
2. Service stoppen: `systemctl stop vaultwarden`
3. Binary-Installation entfernen
4. Diese Docker-Role ausführen
5. Data-Ordner wiederherstellen (falls nötig)

**Hinweis:** Docker-Container nutzt gleiche Data-Folder-Struktur wie Binary.

## Lizenz

MIT

## Autor

RALF Homelab Project

## Changelog

### v2.0.0 (2026-02-15)
- **BREAKING:** Migration von Binary zu Docker
- Docker Engine + Docker Compose Installation
- Official Vaultwarden Docker Image
- systemd-Integration für docker-compose
- Health Checks implementiert
- Resource Limits konfiguriert
- Idempotenz verbessert

### v1.0.0 (2026-02-14)
- Initial Release (Binary-based, nicht funktionsfähig)
