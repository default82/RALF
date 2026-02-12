## Maddy Mail Server Deployment

## Übersicht

Maddy ist ein moderner All-in-One Mail-Server (SMTP + IMAP) als einzelnes Binary. Perfekt für Homelab-Betrieb ohne Docker.

**Container:**
- CT-ID: 4010
- Hostname: svc-mail
- IP: 10.10.40.10/16
- Zone: Functional (40er Bereich = Web & Admin)
- Ports: 25 (SMTP), 587 (Submission), 993 (IMAPS)

**Features:**
- SMTP (Port 25) - Mail-Empfang
- Submission (Port 587) - Authenticated Mail-Versand
- IMAP (Port 993) - Mail-Abruf für Clients
- SQLite Backend (Credentials + Mailboxen)
- Self-signed TLS für homelab.lan

## Voraussetzungen

1. **Keine Dependencies:** Maddy ist standalone
2. **Mail-Account-Passwörter:** Für kolja und ralf

## Deployment

### Schritt 1: Credentials vorbereiten

```bash
# Mail-Passwörter für beide Accounts
export MAIL_ACCOUNT1_PASS='KoljaMailPass123'
export MAIL_ACCOUNT2_PASS='RalfMailPass123'
```

### Schritt 2: Bootstrap ausführen

```bash
bash /root/ralf/bootstrap/create-mail.sh
```

**Output:**
- Container erstellt (CT 4010)
- Maddy 0.8.0 installiert
- Self-signed TLS-Zertifikat generiert
- Mail-Accounts angelegt (kolja@homelab.lan, ralf@homelab.lan)
- Systemd service aktiv

### Schritt 3: Verifikation

```bash
# Service-Status
pct exec 4010 -- systemctl status maddy

# Ports prüfen
pct exec 4010 -- ss -lntp | grep -E ':(25|587|993)'

# Logs prüfen
pct exec 4010 -- journalctl -u maddy -n 50
```

## Mail-Client-Konfiguration

### Thunderbird / Evolution

**IMAP (Eingehende Mail):**
```
Server:     10.10.40.10
Port:       993
Sicherheit: SSL/TLS
Benutzername: kolja@homelab.lan
Passwort:   <MAIL_ACCOUNT1_PASS>
```

**SMTP (Ausgehende Mail):**
```
Server:     10.10.40.10
Port:       587
Sicherheit: STARTTLS
Benutzername: kolja@homelab.lan
Passwort:   <MAIL_ACCOUNT1_PASS>
```

**Hinweis:** Self-signed Certificate muss akzeptiert werden!

### Test-Mail senden

```bash
# Von kolja an ralf
echo "Test-Mail von kolja" | mail -s "Test" -r kolja@homelab.lan ralf@homelab.lan

# Mail-Queue prüfen
pct exec 4010 -- /usr/local/bin/maddy queue list
```

## Mail-Account-Verwaltung

### Neuen Account erstellen

```bash
pct exec 4010 -- bash -lc "cd /var/lib/maddy && echo 'passwort' | sudo -u maddy /usr/local/bin/maddy creds create neuer@homelab.lan"
```

### Passwort ändern

```bash
pct exec 4010 -- bash -lc "cd /var/lib/maddy && echo 'neues-passwort' | sudo -u maddy /usr/local/bin/maddy creds password kolja@homelab.lan"
```

### Account löschen

```bash
pct exec 4010 -- bash -lc "cd /var/lib/maddy && sudo -u maddy /usr/local/bin/maddy creds remove kolja@homelab.lan"
```

### Alle Accounts auflisten

```bash
pct exec 4010 -- bash -lc "cd /var/lib/maddy && sudo -u maddy /usr/local/bin/maddy creds list"
```

## Service-Integration

### Vaultwarden SMTP konfigurieren

```bash
# /etc/vaultwarden/config.env in CT 3010
pct exec 3010 -- bash -lc "cat >>/etc/vaultwarden/config.env <<EOF

# SMTP via Maddy
SMTP_HOST=10.10.40.10
SMTP_PORT=587
SMTP_FROM=vaultwarden@homelab.lan
SMTP_SECURITY=starttls
SMTP_USERNAME=vaultwarden@homelab.lan
SMTP_PASSWORD=<vaultwarden-mail-pass>
EOF"

# Restart Vaultwarden
pct exec 3010 -- systemctl restart vaultwarden
```

**Hinweis:** Zuerst Mail-Account `vaultwarden@homelab.lan` in Maddy anlegen!

### Semaphore Notifications

```bash
# Semaphore kann via SMTP Notifications senden
# Settings → Email Alerts → SMTP Configuration:
# Server: 10.10.40.10:587
# From: semaphore@homelab.lan
# Username: semaphore@homelab.lan
# Password: <semaphore-mail-pass>
```

## Konfiguration

### Config-Datei: `/etc/maddy/maddy.conf`

```bash
# Config bearbeiten
pct exec 4010 -- nano /etc/maddy/maddy.conf

# Syntax-Check
pct exec 4010 -- /usr/local/bin/maddy run --dry-run

# Service neu starten
pct exec 4010 -- systemctl restart maddy
```

### Wichtige Settings

```
# Hostname
$(hostname) = svc-mail.homelab.lan

# Primary Domain
$(primary_domain) = homelab.lan

# TLS Certificate
tls file /etc/maddy/tls_cert.pem /etc/maddy/tls_key.pem

# Weitere Domains hinzufügen:
destination example.com {
    deliver_to &local_mailboxes
}
```

## TLS-Zertifikat erneuern

### Self-Signed (standard)

```bash
pct exec 4010 -- bash -lc "
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
  -nodes -keyout /etc/maddy/tls_key.pem -out /etc/maddy/tls_cert.pem \
  -subj '/CN=svc-mail.homelab.lan' \
  -addext 'subjectAltName=DNS:svc-mail.homelab.lan,DNS:homelab.lan'

chmod 600 /etc/maddy/tls_key.pem
chmod 644 /etc/maddy/tls_cert.pem
chown maddy:maddy /etc/maddy/tls_*.pem

systemctl restart maddy
"
```

### Let's Encrypt (für externe Domains)

```bash
# Certbot im Container installieren
pct exec 4010 -- apt-get install -y certbot

# Zertifikat anfordern (DNS oder HTTP challenge)
pct exec 4010 -- certbot certonly --standalone -d mail.example.com

# Maddy Config anpassen
pct exec 4010 -- bash -lc "sed -i 's|/etc/maddy/tls_cert.pem|/etc/letsencrypt/live/mail.example.com/fullchain.pem|' /etc/maddy/maddy.conf"
pct exec 4010 -- bash -lc "sed -i 's|/etc/maddy/tls_key.pem|/etc/letsencrypt/live/mail.example.com/privkey.pem|' /etc/maddy/maddy.conf"

# Service neu starten
pct exec 4010 -- systemctl restart maddy
```

## Monitoring & Logs

### Service-Status

```bash
# Systemd Status
pct exec 4010 -- systemctl status maddy

# Prozess-Check
pct exec 4010 -- ps aux | grep maddy
```

### Logs

```bash
# Journalctl (letzte 100 Zeilen)
pct exec 4010 -- journalctl -u maddy -n 100

# Live-Logs
pct exec 4010 -- journalctl -u maddy -f

# Nur Errors
pct exec 4010 -- journalctl -u maddy -p err
```

### Mail-Queue

```bash
# Wartende Mails anzeigen
pct exec 4010 -- bash -lc "cd /var/lib/maddy && sudo -u maddy /usr/local/bin/maddy queue list"

# Queue löschen
pct exec 4010 -- bash -lc "cd /var/lib/maddy && sudo -u maddy /usr/local/bin/maddy queue clear"
```

## Backup

### Mailboxen sichern

```bash
# SQLite Datenbanken sichern
pct exec 4010 -- bash -lc "
cd /var/lib/maddy
sqlite3 mail.db .dump > /tmp/maddy-mail-backup-\$(date +%Y%m%d).sql
sqlite3 credentials.db .dump > /tmp/maddy-creds-backup-\$(date +%Y%m%d).sql
"

# Backups herunterladen
pct pull 4010 /tmp/maddy-*.sql ./
```

### Container-Snapshot

```bash
# Snapshot erstellen
pct snapshot 4010 "backup-$(date +%Y%m%d)"

# Snapshots auflisten
pct listsnapshot 4010

# Rollback
pct stop 4010
pct rollback 4010 <snapshot-name>
pct start 4010
```

## Troubleshooting

### Service startet nicht

```bash
# Config-Syntax prüfen
pct exec 4010 -- /usr/local/bin/maddy run --dry-run

# Permissions prüfen
pct exec 4010 -- ls -la /var/lib/maddy
pct exec 4010 -- ls -la /etc/maddy

# SELinux/AppArmor (falls aktiviert)
pct exec 4010 -- dmesg | grep maddy
```

### Mail kommt nicht an

```bash
# Logs prüfen
pct exec 4010 -- journalctl -u maddy -f

# Queue prüfen
pct exec 4010 -- bash -lc "cd /var/lib/maddy && sudo -u maddy /usr/local/bin/maddy queue list"

# DNS-Check (MX Record)
dig MX homelab.lan
```

### IMAP-Login fehlschlägt

```bash
# Account existiert?
pct exec 4010 -- bash -lc "cd /var/lib/maddy && sudo -u maddy /usr/local/bin/maddy creds list"

# Passwort zurücksetzen
pct exec 4010 -- bash -lc "cd /var/lib/maddy && echo 'neues-passwort' | sudo -u maddy /usr/local/bin/maddy creds password kolja@homelab.lan"

# Logs prüfen
pct exec 4010 -- journalctl -u maddy | grep -i auth
```

### TLS-Fehler

```bash
# Zertifikat prüfen
pct exec 4010 -- openssl x509 -in /etc/maddy/tls_cert.pem -noout -text

# Permissions prüfen
pct exec 4010 -- ls -la /etc/maddy/tls_*.pem

# Neu generieren (siehe oben)
```

## Erweiterte Konfiguration

### Relay-Host (für externe Mails)

Wenn externe Mails über einen anderen SMTP-Server versendet werden sollen:

```conf
# In maddy.conf
remote_queue {
    target &remote_smtp
}

remote_smtp {
    targets smtp://external-smtp.example.com:587

    auth plain external-user external-pass
    tls opportunistic
}
```

### Spam-Filter (Rspamd)

```bash
# Rspamd im Container installieren
pct exec 4010 -- apt-get install -y rspamd

# Maddy Config erweitern
# siehe: https://maddy.email/tutorials/rspamd/
```

### Webmail (Optional)

Roundcube oder Rainloop als separater Container:
- CT 4012: svc-webmail (10.10.40.12:80)
- IMAP Backend: 10.10.40.10:993
- SMTP Backend: 10.10.40.10:587

## Nächste Schritte

1. **Mail-Clients konfigurieren:**
   - Thunderbird für kolja
   - Thunderbird für ralf
   - Test-Mails senden

2. **Service-Accounts anlegen:**
   - vaultwarden@homelab.lan (für Invitations)
   - semaphore@homelab.lan (für Notifications)
   - noreply@homelab.lan (für System-Mails)

3. **Vaultwarden SMTP konfigurieren:**
   - Mail-Account erstellen
   - config.env anpassen
   - Invitation-Test

4. **Backup-Automatisierung:**
   - Tägliches SQLite-Backup
   - Wöchentlicher Container-Snapshot

5. **Optional: Reverse Proxy für Webmail**

## Dokumentation

- **Maddy:** https://maddy.email/
- **Config Reference:** https://maddy.email/reference/config/
- **Tutorials:** https://maddy.email/tutorials/
