# RALF Homelab - Credentials Management

## Übersicht

Alle Passwörter, Tokens und Secrets werden zentral in `/var/lib/ralf/credentials.env` verwaltet.

**Wichtig:** Diese Datei ist **NICHT** im Git-Repository und wird **NIE** committed!

### Passwort-Format (seit 2026-02-14)

Alle auto-generierten Passwörter folgen diesen Sicherheitsstandards:
- **Länge:** 32 Zeichen
- **Zeichensatz:** Großbuchstaben, Kleinbuchstaben, Ziffern, Sonderzeichen
- **Ausgeschlossen (ähnliche Zeichen):** `1, I, i, L, l, 0, O, o`
- **Ausgeschlossen (mehrdeutige Symbole):** `()[]{}|;:'",.<>/?~\``
- **Erlaubte Sonderzeichen:** `$?%!@#&*`

## Erste Einrichtung

### 1. Credentials generieren

```bash
bash bootstrap/generate-credentials.sh
```

Dies erstellt `/var/lib/ralf/credentials.env` mit:
- 62 auto-generierten Variablen
- PostgreSQL-Passwörtern für alle Datenbanken
- Admin-Accounts für alle Services (kolja + ralf)
- API-Tokens und Secrets
- Server-IPs und Ports

### 2. Credentials laden

Vor dem Ausführen eines Bootstrap-Skripts:

```bash
source /var/lib/ralf/credentials.env
bash bootstrap/create-gitea.sh
```

Oder direkt inline:

```bash
source /var/lib/ralf/credentials.env && bash bootstrap/create-gitea.sh
```

### 3. Credentials prüfen

```bash
source /var/lib/ralf/credentials.env
env | grep -E "(GITEA|POSTGRES|SEMAPHORE)_"
```

## Verfügbare Variablen

### PostgreSQL Datenbanken

- `POSTGRES_MASTER_PASS` - PostgreSQL Master-Passwort
- `GITEA_PG_PASS` - Gitea Datenbank
- `SEMAPHORE_PG_PASS` - Semaphore Datenbank
- `VAULTWARDEN_PG_PASS` - Vaultwarden Datenbank
- `N8N_PG_PASS` - n8n Datenbank
- `MATRIX_PG_PASS` - Matrix/Synapse Datenbank

### Service Admin-Accounts

**Gitea:**
- `GITEA_ADMIN1_USER`, `GITEA_ADMIN1_EMAIL`, `GITEA_ADMIN1_PASS`
- `GITEA_ADMIN2_USER`, `GITEA_ADMIN2_EMAIL`, `GITEA_ADMIN2_PASS`

**Semaphore:**
- `SEMAPHORE_ADMIN_USER`, `SEMAPHORE_ADMIN_EMAIL`, `SEMAPHORE_ADMIN_PASS`

**n8n:**
- `N8N_ADMIN1_USER`, `N8N_ADMIN1_EMAIL`, `N8N_ADMIN1_PASS`
- `N8N_ADMIN2_USER`, `N8N_ADMIN2_EMAIL`, `N8N_ADMIN2_PASS`
- `N8N_ENCRYPTION_KEY`

**Matrix/Synapse:**
- `MATRIX_ADMIN1_USER`, `MATRIX_ADMIN1_EMAIL`, `MATRIX_ADMIN1_PASS`
- `MATRIX_ADMIN2_USER`, `MATRIX_ADMIN2_EMAIL`, `MATRIX_ADMIN2_PASS`
- `MATRIX_REGISTRATION_SECRET`

**Mail:**
- `MAIL_ACCOUNT1_USER`, `MAIL_ACCOUNT1_EMAIL`, `MAIL_ACCOUNT1_PASS`
- `MAIL_ACCOUNT2_USER`, `MAIL_ACCOUNT2_EMAIL`, `MAIL_ACCOUNT2_PASS`

**Vaultwarden:**
- `VAULTWARDEN_ADMIN_TOKEN`

### Server-Informationen

Alle Server-IPs und Ports:
- `PG_HOST`, `PG_PORT`
- `GITEA_HOST`, `GITEA_HTTP_PORT`, `GITEA_SSH_PORT`
- `SEMAPHORE_HOST`, `SEMAPHORE_PORT`
- `VAULTWARDEN_HOST`, `VAULTWARDEN_PORT`
- `N8N_HOST`, `N8N_PORT`
- `MATRIX_HOST`, `MATRIX_PORT`
- `MAIL_HOST`, `MAIL_SMTP_PORT`, `MAIL_IMAP_PORT`
- `OLLAMA_HOST`, `OLLAMA_PORT`

## Credential-Rotation

### Neue Credentials generieren

```bash
bash bootstrap/generate-credentials.sh
```

Das Skript:
1. Warnt dich, dass bestehende Credentials überschrieben werden
2. Erstellt ein Backup: `credentials.env.backup.YYYYMMDD_HHMMSS`
3. Generiert neue Credentials
4. Setzt Permissions auf 600

### Backup wiederherstellen

```bash
cp /var/lib/ralf/credentials.env.backup.20260212_161430 \
   /var/lib/ralf/credentials.env
```

## Sicherheit

### Permissions

```bash
ls -l /var/lib/ralf/credentials.env
# -rw------- 1 root root (nur root kann lesen/schreiben)
```

### Backups

Automatische Backups bei jeder Neu-Generierung:
```bash
ls -l /var/lib/ralf/credentials.env.backup.*
```

### Git-Schutz

`.gitignore` schützt vor versehentlichem Commit:
```
/var/lib/ralf/credentials.env
credentials.env
*.env.backup.*
```

## Migration: Alte Skripte aktualisieren

### Vorher (manuelle Env-Variables):

```bash
export GITEA_ADMIN1_PASS="mein-passwort"
export PG_PASS="db-passwort"
bash bootstrap/create-gitea.sh
```

### Nachher (zentrale Credentials):

```bash
source /var/lib/ralf/credentials.env
bash bootstrap/create-gitea.sh
```

## Troubleshooting

### "CHANGE_ME_NOW" Error

```
ERROR: PG_PASS ist noch CHANGE_ME_NOW.
```

**Lösung:** Credentials generieren und laden:
```bash
bash bootstrap/generate-credentials.sh
source /var/lib/ralf/credentials.env
```

### Credentials nicht gefunden

```
bash: /var/lib/ralf/credentials.env: No such file or directory
```

**Lösung:** Credentials generieren:
```bash
bash bootstrap/generate-credentials.sh
```

### Alte Credentials nach Reboot

```
source /var/lib/ralf/credentials.env
```

Die Datei ist persistent (bleibt nach Reboot erhalten).

## Integration mit Vaultwarden

**TODO (Task #18):** Migration der Credentials nach Vaultwarden:
1. Vaultwarden Admin-Accounts anlegen (Task #17)
2. Credentials aus `credentials.env` nach Vaultwarden importieren
3. Bootstrap-Skripte auf Vaultwarden-API umstellen
4. Dokumentation aktualisieren (Task #19)

## Weitere Informationen

- Code-Analyse Report: `/tmp/code-analysis-report.md`
- Security Best Practices: Siehe CLAUDE.md
- Task-Liste: `TaskList` in der CLI
