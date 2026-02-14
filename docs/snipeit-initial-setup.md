# Snipe-IT Initial Setup

## Status

✅ Container deployed (CT 4040, web-snipeit, 10.10.40.40:8080)
✅ Datenbank konfiguriert (MariaDB: 10.10.20.11)
✅ Admin-Account erstellt

## Admin-Zugang

**URL:** http://10.10.40.40:8080

**Credentials:**
- Username: `admin`
- Email: `admin@homelab.lan`
- Password: siehe `/var/lib/ralf/credentials.env` → `SNIPEIT_ADMIN_PASS`

## Setup-Optionen

### Option 1: Setup-Wizard durchlaufen

1. Gehe zu http://10.10.40.40:8080
2. Der Wizard zeigt "Setup Complete!" an
3. Klicke durch die letzten Schritte (Migrations, etc.)
4. Login mit den oben genannten Credentials

### Option 2: Direkt einloggen

1. Gehe zu http://10.10.40.40:8080/login
2. Login mit den oben genannten Credentials
3. Setup-Wizard wird übersprungen

## Konfiguration

Die Grundkonfiguration ist bereits in der `.env`-Datei gesetzt:

```bash
APP_ENV=production
APP_DEBUG=false
APP_TIMEZONE='Europe/Berlin'
APP_LOCALE=de_DE
DB_CONNECTION=mysql
DB_HOST=10.10.20.11
DB_DATABASE=snipeit
```

## Admin-Account erstellt via CLI

Der Admin-Account wurde mit dem Artisan-Kommando erstellt:

```bash
php artisan snipeit:create-admin \
  --username='admin' \
  --email='admin@homelab.lan' \
  --password='***' \
  --first_name='Admin' \
  --last_name='User'
```

## Weitere Konfiguration

Nach dem ersten Login können folgende Einstellungen vorgenommen werden:

1. **Site-Name:** "RALF Homelab - Asset Management"
2. **Währung:** EUR
3. **Sprache:** Deutsch (de_DE)
4. **Zeitzone:** Europe/Berlin

Diese Einstellungen können im Admin-Panel unter **Settings** angepasst werden.

## Nächste Schritte

1. ✅ Snipe-IT Web-UI aufrufen
2. ✅ Mit Admin-Account einloggen
3. Grundeinstellungen überprüfen/anpassen
4. Erste Asset-Kategorien anlegen
5. Locations/Standorte definieren
6. Assets erfassen

## Backups

- **Pre-Install Snapshot:** verfügbar
- **Post-Install Snapshot:** verfügbar
- **Rollback:** `pct rollback 4040 post-install`

## Troubleshooting

### Setup-Wizard startet nicht durch

Cache leeren:
```bash
pct exec 4040 -- bash -c "
cd /var/www/snipe-it
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear
"
```

### Login funktioniert nicht

Admin-Password aus credentials.env prüfen:
```bash
source /var/lib/ralf/credentials.env
echo $SNIPEIT_ADMIN_PASS
```

### Datenbank-Verbindung prüfen

```bash
pct exec 4040 -- bash -c "
cd /var/www/snipe-it
sudo -u www-data php artisan migrate:status
"
```
