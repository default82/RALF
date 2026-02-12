# Vaultwarden Deployment

## Übersicht

Vaultwarden ist ein Bitwarden-kompatibler Password Manager, geschrieben in Rust. Ressourcensparend und perfekt für Self-Hosting.

**Container:**
- CT-ID: 3010
- Hostname: svc-vaultwarden
- IP: 10.10.30.10/16
- Zone: Functional (30er Bereich = Security)
- Port: 8080

## Voraussetzungen

1. **PostgreSQL muss laufen:**
   ```bash
   pct exec 2010 -- systemctl is-active postgresql
   ```

2. **PostgreSQL Superuser-Passwort:** Für Datenbank-Anlage
3. **Vaultwarden Admin-Token:** Für Admin-Panel

## Deployment

### Schritt 1: Credentials vorbereiten

```bash
# PostgreSQL DB-Passwort (wird für User 'vaultwarden' angelegt)
export PG_PASS='VaultwardenDB123'

# Admin-Token generieren (für /admin Panel)
export VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -base64 48)

# Admin-Token anzeigen (SPEICHERN für später!)
echo "Admin Token: $VAULTWARDEN_ADMIN_TOKEN"
```

### Schritt 2: Bootstrap ausführen

```bash
bash /root/ralf/bootstrap/create-vaultwarden.sh
```

### Schritt 3: Verifikation

```bash
# Service-Status prüfen
pct exec 3010 -- systemctl status vaultwarden

# Port-Check
curl http://10.10.30.10:8080/

# Logs prüfen
pct exec 3010 -- tail -f /var/lib/vaultwarden/vaultwarden.log
```

## Erste Schritte nach Deployment

### 1. Ersten User anlegen

1. Browser öffnen: http://10.10.30.10:8080
2. "Create Account" klicken
3. Email + Master Password eingeben
4. Account erstellen

**WICHTIG:** Der erste Account hat keine speziellen Rechte. Admin-Zugriff erfolgt über `/admin`.

### 2. Admin Panel aufrufen

1. Browser öffnen: http://10.10.30.10:8080/admin
2. Admin Token eingeben (aus `$VAULTWARDEN_ADMIN_TOKEN`)
3. Admin Panel nutzen für:
   - User verwalten
   - Invitations versenden
   - Server-Einstellungen

### 3. Weitere User einladen

Da `SIGNUPS_ALLOWED=false`, müssen User eingeladen werden:

**Option A: Via Admin Panel**
1. Admin Panel öffnen
2. "Invite User" klicken
3. Email eingeben
4. Invitation-Link per Email (später, wenn SMTP konfiguriert)

**Option B: Manuell**
1. `SIGNUPS_ALLOWED=true` in `/etc/vaultwarden/config.env` setzen
2. Service neu starten: `systemctl restart vaultwarden`
3. User können sich selbst registrieren
4. Danach wieder `SIGNUPS_ALLOWED=false` setzen

## Konfiguration

### Config-Datei: `/etc/vaultwarden/config.env`

```bash
# Config bearbeiten
pct exec 3010 -- nano /etc/vaultwarden/config.env

# Service neu starten
pct exec 3010 -- systemctl restart vaultwarden
```

### Wichtige Settings

```env
# Signups erlauben (temporär, für erste User)
SIGNUPS_ALLOWED=true

# SMTP konfigurieren (für Invitations + 2FA)
SMTP_HOST=10.10.40.10
SMTP_PORT=587
SMTP_FROM=vaultwarden@homelab.lan
SMTP_USERNAME=vaultwarden
SMTP_PASSWORD=<smtp-pass>

# Domain (für Reverse Proxy)
DOMAIN=https://vault.homelab.lan

# 2FA/YubiKey (optional)
YUBICO_CLIENT_ID=
YUBICO_SECRET_KEY=
```

## Bitwarden Clients

### Browser Extension
1. Bitwarden Extension installieren (Chrome/Firefox)
2. Einstellungen öffnen
3. "Self-hosted" wählen
4. Server URL: `http://10.10.30.10:8080`
5. Mit Account einloggen

### Desktop App
1. Bitwarden Desktop herunterladen
2. Bei Anmeldung: "Self-hosted" wählen
3. Server URL: `http://10.10.30.10:8080`

### Mobile App
1. Bitwarden App (iOS/Android) installieren
2. Settings → "Self-hosted"
3. Server URL: `http://10.10.30.10:8080`

## Migration von bisherigen Credentials

### Credentials aus Bootstrap-Skripten

Alle Passwörter aus den Bootstrap-Skripten sollten nach Vaultwarden migriert werden:

1. **PostgreSQL:**
   - postgres superuser
   - semaphore DB-User
   - gitea DB-User
   - vaultwarden DB-User

2. **Semaphore:**
   - kolja Admin
   - ralf Admin

3. **Gitea:**
   - kolja Admin
   - ralf Admin
   - kolja Gitea-User (für HTTP Auth)

4. **Proxmox:**
   - API Token (root@pam!ralf-tofu)

### Import-Workflow

1. Vaultwarden Web-UI öffnen
2. Vault erstellen: "Homelab Infrastructure"
3. Für jeden Service einen Login-Eintrag erstellen:
   ```
   Name: PostgreSQL - semaphore User
   Username: semaphore
   Password: TestPass123Semaphore
   URL: postgresql://10.10.20.10:5432
   Notes: Semaphore DB Backend
   ```

4. Secure Notes für API Tokens:
   ```
   Name: Proxmox API Token
   Type: Secure Note
   Content:
     Token ID: root@pam!ralf-tofu
     Token Secret: <secret>
     URL: https://10.10.10.10:8006
   ```

## Backup

### Datenbank-Backup

```bash
# PostgreSQL Backup (empfohlen)
pct exec 2010 -- bash -lc "pg_dump -U vaultwarden vaultwarden > /tmp/vaultwarden-backup-$(date +%Y%m%d).sql"

# Backup herunterladen
pct pull 2010 /tmp/vaultwarden-backup-*.sql ./
```

### Container-Snapshot

```bash
# Snapshot erstellen
pct snapshot 3010 "backup-$(date +%Y%m%d)"

# Snapshots auflisten
pct listsnapshot 3010

# Rollback (falls notwendig)
pct stop 3010
pct rollback 3010 <snapshot-name>
pct start 3010
```

## Troubleshooting

### Service startet nicht

```bash
# Logs prüfen
pct exec 3010 -- journalctl -u vaultwarden -n 50

# Vaultwarden-Log
pct exec 3010 -- tail -f /var/lib/vaultwarden/vaultwarden.log

# Config-Syntax prüfen
pct exec 3010 -- cat /etc/vaultwarden/config.env
```

### Datenbank-Verbindung fehlschlägt

```bash
# PostgreSQL erreichbar?
pct exec 3010 -- pg_isready -h 10.10.20.10 -p 5432

# Credentials testen
pct exec 3010 -- psql -h 10.10.20.10 -U vaultwarden -d vaultwarden -c "SELECT 1;"
```

### Admin-Token vergessen

```bash
# Neues Token generieren
NEW_TOKEN=$(openssl rand -base64 48)

# In Config eintragen
pct exec 3010 -- bash -lc "sed -i 's/^ADMIN_TOKEN=.*/ADMIN_TOKEN=${NEW_TOKEN}/' /etc/vaultwarden/config.env"

# Service neu starten
pct exec 3010 -- systemctl restart vaultwarden

# Token anzeigen
echo "Neuer Admin Token: $NEW_TOKEN"
```

## Nächste Schritte

1. **Reverse Proxy (Caddy) einrichten:**
   - HTTPS für vault.homelab.lan
   - TLS-Zertifikat (Let's Encrypt oder Self-Signed)

2. **SMTP konfigurieren (Maddy Mail):**
   - Für Invitations
   - Für 2FA-Emails
   - Für Passwort-Reset

3. **Backup-Automatisierung:**
   - Tägliches PostgreSQL-Backup
   - Wöchentlicher Container-Snapshot

4. **Monitoring:**
   - Health-Check: `/api/alive`
   - Prometheus Exporter (optional)

5. **Alle Credentials migrieren:**
   - Bootstrap-Skripte durchgehen
   - Passwörter in Vaultwarden speichern
   - Dokumentation aktualisieren

## Dokumentation

- **Vaultwarden:** https://github.com/dani-garcia/vaultwarden
- **Bitwarden:** https://bitwarden.com/help/
- **Config Options:** https://github.com/dani-garcia/vaultwarden/wiki/Configuration-overview
