# Snipe-IT Ansible Role

Deployt Snipe-IT Asset Management System in einem LXC Container.

## Requirements

- Ubuntu 24.04 LXC Container
- MariaDB-Server (10.10.20.11:3306)
- Datenbank `snipeit` mit User `snipeit_user` muss existieren
- PHP 8.3, Nginx, Composer

## Role Variables

### Erforderlich (aus Vault/Environment):

```yaml
snipeit_db_pass: "***"           # MariaDB Password
snipeit_app_key: "base64:***"    # Laravel App Key
snipeit_admin_password: "***"    # Admin-Account Password
```

### Optional (mit Defaults):

```yaml
snipeit_version: "v8.3.7"
snipeit_db_host: "10.10.20.11"
snipeit_db_name: "snipeit"
snipeit_admin_username: "admin"
snipeit_app_url: "http://10.10.40.40:8080"
```

Siehe `defaults/main.yml` für alle verfügbaren Variablen.

## Dependencies

- Role `base` (für System-Grundkonfiguration)

## Example Playbook

```yaml
- hosts: snipeit
  become: yes
  roles:
    - base
    - snipeit
  vars:
    snipeit_db_pass: "{{ lookup('env', 'SNIPEIT_MYSQL_PASS') }}"
    snipeit_app_key: "{{ lookup('env', 'SNIPEIT_APP_KEY') }}"
    snipeit_admin_password: "{{ lookup('env', 'SNIPEIT_ADMIN_PASS') }}"
```

## Usage

### 1. Secrets laden

```bash
source /var/lib/ralf/credentials.env
```

### 2. Playbook ausführen

```bash
cd iac/ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-snipeit.yml
```

### 3. Login

- URL: http://10.10.40.40:8080
- Username: `admin`
- Password: siehe `SNIPEIT_ADMIN_PASS` in `credentials.env`

## Tasks

Die Role führt folgende Schritte aus:

1. **System-Pakete installieren:** PHP 8.3, Nginx, MariaDB Client, Composer
2. **Snipe-IT clonen:** Von GitHub, Version v8.3.7
3. **Composer Dependencies:** Installiert alle PHP-Dependencies
4. **.env Konfiguration:** Deployt aus Template
5. **Storage Setup:** Berechtigungen und Symlinks
6. **Datenbank-Migrationen:** `php artisan migrate`
7. **Admin-User erstellen:** Via `artisan snipeit:create-admin`
8. **Nginx konfigurieren:** Virtual Host auf Port 8080
9. **Services starten:** Nginx und PHP-FPM

## Idempotenz

Die Role ist vollständig idempotent:

- Composer wird nur installiert, wenn nicht vorhanden
- Git-Repository wird nur gecloned, wenn nicht vorhanden
- Dependencies werden upgedatet bei wiederholter Ausführung
- Migrationen laufen nur wenn nötig
- Admin-User wird nur erstellt, wenn nicht vorhanden
- Konfigurationen werden aktualisiert (idempotent via Templates)

## Handlers

- `restart nginx` - Nginx neustarten nach Config-Änderung
- `restart php-fpm` - PHP-FPM neustarten nach .env-Änderung
- `reload nginx` - Nginx reloaden (schneller als restart)

## Templates

### snipeit.env.j2

Generiert `/var/www/snipe-it/.env` mit:
- Datenbank-Verbindung zu MariaDB
- App-Key und URL
- Timezone, Locale (Europa/Berlin, de_DE)
- Cache/Session Settings
- Security Settings

### snipeit-nginx.conf.j2

Nginx Virtual Host Konfiguration:
- Port 8080
- PHP-FPM via Socket
- Security Headers
- Upload-Limit 100MB
- Logging

## Testing

Nach dem Deployment:

```bash
# Service-Status prüfen
ansible snipeit -m shell -a "systemctl status nginx php8.3-fpm"

# Web-UI erreichbar?
curl -I http://10.10.40.40:8080

# Admin-User existiert?
ansible snipeit -m shell -a "cd /var/www/snipe-it && php artisan tinker --execute='echo \Illuminate\Support\Facades\DB::table(\"users\")->where(\"username\", \"admin\")->count();'"
```

## Troubleshooting

### Composer-Installation fehlgeschlagen

```bash
ansible snipeit -m shell -a "composer --version"
```

### Datenbank-Verbindung testen

```bash
ansible snipeit -m shell -a "mysql -h 10.10.20.11 -u snipeit_user -p'***' -e 'SHOW DATABASES;'"
```

### Logs prüfen

```bash
ansible snipeit -m shell -a "tail -50 /var/log/nginx/snipeit_error.log"
ansible snipeit -m shell -a "tail -50 /var/www/snipe-it/storage/logs/laravel.log"
```

## License

Interner Gebrauch - RALF Homelab

## Author

RALF Infrastructure Team
