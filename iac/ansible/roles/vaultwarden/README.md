# Ansible Role: Vaultwarden

Installiert und konfiguriert Vaultwarden (Bitwarden-kompatibler Password Manager) für RALF LXC-Container.

## Anforderungen

- Ubuntu 24.04 (Noble) oder 22.04 (Jammy)
- Ansible >= 2.15
- PostgreSQL-Server erreichbar (10.10.20.10:5432)
- Environment-Variablen: `VAULTWARDEN_PG_PASS`, `VAULTWARDEN_ADMIN_TOKEN`

## Installationsmethode

Diese Role installiert Vaultwarden als **Binary** (nicht Docker), speziell optimiert für LXC-Container.

- Download: Official GitHub Releases (musl-static Binary)
- Version: 1.32.0 (konfigurierbar via `vaultwarden_version`)
- Database: PostgreSQL (empfohlen für Produktion)
- Web Vault: Enthalten und aktiviert

## Role-Variablen

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
- Binary wird nur heruntergeladen wenn nicht vorhanden
- Config wird nur überschrieben wenn geändert (Handler)
- Service-Restart nur bei Config-Änderungen
- User/Verzeichnisse nur erstellt wenn nicht existent

## Sicherheits-Features

- Systemd-Hardening (PrivateTmp, ProtectHome, NoNewPrivileges)
- Dedizierter System-User (kein Root)
- Signups standardmäßig deaktiviert
- Admin-Token-geschützt
- PostgreSQL statt SQLite (bessere Datensicherheit)

## Performance

- Worker-Threads: 10 (konfigurierbar)
- Icon-Cache: 30 Tage TTL
- Attachments/Sends in separaten Ordnern

## Lizenz

MIT

## Autor

RALF Homelab Project
