# Ansible Role: MariaDB

Installiert und konfiguriert MariaDB Server für RALF LXC-Container.

## Anforderungen

- Ubuntu 24.04 (Noble) oder 22.04 (Jammy)
- Ansible >= 2.15
- Collection: `community.mysql` (in requirements.yml definiert)

## Role-Variablen

### Netzwerk
```yaml
mariadb_port: 3306
mariadb_bind_address: "0.0.0.0"  # Remote-Verbindungen erlaubt
```

### Performance
```yaml
mariadb_max_connections: 200
mariadb_innodb_buffer_pool_size: "512M"
mariadb_query_cache_size: "32M"
```

### Datenbanken & Benutzer
```yaml
mariadb_databases:
  - name: snipeit_db
    encoding: utf8mb4
    collation: utf8mb4_unicode_ci

mariadb_users:
  - name: snipeit_user
    password: "{{ lookup('env', 'SNIPEIT_MYSQL_PASS') }}"
    priv: "snipeit_db.*:ALL"
    host: "%"
```

### Backup
```yaml
mariadb_backup_enabled: true
mariadb_backup_dir: "/var/backups/mariadb"
mariadb_backup_retention_days: 7
```

## Abhängigkeiten

Keine direkten Abhängigkeiten. Empfohlen wird die `base`-Role für grundlegende System-Setup.

## Beispiel-Playbook

```yaml
---
- hosts: mariadb_servers
  become: yes
  roles:
    - role: mariadb
      mariadb_databases:
        - name: snipeit_db
          encoding: utf8mb4
      mariadb_users:
        - name: snipeit_user
          password: "{{ lookup('env', 'SNIPEIT_MYSQL_PASS') }}"
          priv: "snipeit_db.*:ALL"
          host: "%"
```

## Idempotenz

Diese Role ist vollständig idempotent und kann beliebig oft ausgeführt werden:
- Installation erfolgt nur bei Bedarf
- Root-Passwort wird nur gesetzt wenn noch nicht vorhanden
- Datenbanken werden nur erstellt wenn nicht existent
- User werden nur erstellt wenn nicht existent

## Sicherheit

- Root-Passwort aus Environment-Variable (`MARIADB_ROOT_PASS`)
- Anonyme User werden entfernt
- Test-Datenbank wird entfernt
- Remote root-Login optional deaktivierbar

## Lizenz

MIT

## Autor

RALF Homelab Project
