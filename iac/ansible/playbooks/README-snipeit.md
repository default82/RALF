# Snipe-IT Ansible Deployment

## Quick Start

### 1. Secrets laden

```bash
source /var/lib/ralf/credentials.env
```

### 2. Playbook ausführen

```bash
cd /root/ralf/iac/ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-snipeit.yml
```

### 3. Zugriff

- **URL:** http://10.10.40.40:8080
- **Username:** `admin`
- **Password:** siehe `$SNIPEIT_ADMIN_PASS` in `credentials.env`

## Was wird deployed?

Das Playbook installiert und konfiguriert:

- ✅ PHP 8.3 + Nginx + MariaDB Client
- ✅ Composer (PHP Dependency Manager)
- ✅ Snipe-IT v8.3.7 (von GitHub)
- ✅ Alle PHP-Dependencies via Composer
- ✅ .env Konfiguration mit MariaDB-Verbindung
- ✅ Datenbank-Migrationen
- ✅ Admin-Account (automatisch erstellt)
- ✅ Nginx Virtual Host (Port 8080)
- ✅ Security Headers & Upload-Limits

## Erforderliche Secrets

Das Playbook erwartet folgende Environment-Variablen:

```bash
SNIPEIT_MYSQL_PASS      # MariaDB Password für User 'snipeit_user'
SNIPEIT_APP_KEY         # Laravel App Key (base64:...)
SNIPEIT_ADMIN_PASS      # Admin-Account Password
```

Diese sind in `/var/lib/ralf/credentials.env` gespeichert.

## Voraussetzungen

1. **Container:** CT 4040 muss existieren
2. **Datenbank:** MariaDB-Container (CT 2011) muss laufen
3. **DB Setup:** Datenbank `snipeit` mit User `snipeit_user` muss existieren

Das Bootstrap-Script `bootstrap/create-snipeit.sh` erstellt dies automatisch.

## Idempotenz

Das Playbook kann beliebig oft ausgeführt werden:

- Bestehende Installation wird aktualisiert (nicht neu installiert)
- Dependencies werden upgedatet
- Konfiguration wird aktualisiert
- Admin-User wird nur erstellt, wenn nicht vorhanden
- Migrationen laufen nur bei Bedarf

## Dry-Run (Check Mode)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/deploy-snipeit.yml --check
```

## Tags (für selektive Ausführung)

Noch nicht implementiert - TODO in zukünftiger Version.

## Rollback

Falls das Deployment fehlschlägt:

```bash
# Auf Pre-Install Snapshot zurücksetzen
pct rollback 4040 pre-install

# Oder Post-Install Snapshot (falls vorhanden)
pct rollback 4040 post-install
```

## Troubleshooting

### Playbook schlägt bei "Validiere erforderliche Secrets" fehl

```bash
# Prüfe ob credentials.env geladen wurde
echo $SNIPEIT_MYSQL_PASS
echo $SNIPEIT_APP_KEY
echo $SNIPEIT_ADMIN_PASS

# Falls leer: neu laden
source /var/lib/ralf/credentials.env
```

### Composer-Installation fehlgeschlagen

```bash
# SSH zum Container
pct enter 4040

# Manuell Composer installieren
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer
```

### Datenbank-Verbindung fehlgeschlagen

```bash
# Prüfe MariaDB-Container
pct status 2011

# Teste Verbindung vom Snipe-IT-Container
pct exec 4040 -- mysql -h 10.10.20.11 -u snipeit_user -p'***' -e 'SHOW DATABASES;'
```

### Admin-User wurde nicht erstellt

```bash
# Manuell erstellen
pct exec 4040 -- bash -c "
cd /var/www/snipe-it
source /var/lib/ralf/credentials.env
sudo -u www-data php artisan snipeit:create-admin \
  --username=admin \
  --email=admin@homelab.lan \
  --password=\$SNIPEIT_ADMIN_PASS \
  --first_name=Admin \
  --last_name=User
"
```

### Web-UI nicht erreichbar

```bash
# Prüfe Nginx
pct exec 4040 -- systemctl status nginx

# Prüfe PHP-FPM
pct exec 4040 -- systemctl status php8.3-fpm

# Prüfe Nginx-Logs
pct exec 4040 -- tail -50 /var/log/nginx/snipeit_error.log
```

## Vergleich: Bootstrap-Script vs. Ansible

| Aspekt | Bootstrap-Script | Ansible-Playbook |
|--------|-----------------|------------------|
| **Container-Erstellung** | ✅ Ja | ❌ Nein (manuell via pct/Terraform) |
| **Snapshots** | ✅ Pre/Post-Install | ❌ Nein (manuell) |
| **Idempotenz** | ✅ Ja | ✅ Ja |
| **Secrets-Management** | Environment-Variablen | Environment-Variablen + Vault-Ready |
| **Wiederverwendbar** | Bash-Skript | YAML-Deklarativ |
| **Testing** | Manuelle Smoke-Tests | Ansible-Facts + Post-Tasks |
| **Orchestrierung** | Sequenziell | Parallel + Dependencies |
| **CI/CD-Integration** | ❌ Schwierig | ✅ Einfach (Semaphore) |

**Empfehlung:**
- **Bootstrap-Script:** Initiales Setup, schnelles Deployment
- **Ansible-Playbook:** Updates, Konfigurationsänderungen, CI/CD

## Nächste Schritte

Nach erfolgreichem Deployment:

1. ✅ Login http://10.10.40.40:8080
2. Grundeinstellungen überprüfen:
   - Site-Name: "RALF Homelab - Asset Management"
   - Währung: EUR
   - Sprache: Deutsch
3. Asset-Kategorien anlegen
4. Locations/Standorte definieren
5. Erste Assets erfassen

## Integration mit Semaphore

TODO: Semaphore-Pipeline erstellen für automatisierte Deployments.

## Weitere Dokumentation

- **Role-Dokumentation:** `roles/snipeit/README.md`
- **Bootstrap-Script:** `bootstrap/create-snipeit.sh`
- **Setup-Anleitung:** `docs/snipeit-initial-setup.md`
