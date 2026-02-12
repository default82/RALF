# Semaphore Konfiguration

## Übersicht

Das Skript `configure-semaphore.sh` konfiguriert den Semaphore-Container vollständig:

1. ✅ Zweiten Admin-Account anlegen (ralf@homelab.lan)
2. ✅ SSH-Keypair für Ansible generieren (ed25519)
3. ✅ Git-Repository auf Gitea umstellen
4. ✅ SSH-Key in Semaphore hinterlegen
5. ✅ Ansible-Inventar hinzufügen
6. ✅ Environment Variables anlegen

## Voraussetzungen

**Erforderliche Credentials:**

Das Skript benötigt mehrere Passwörter und Tokens. Diese müssen als Umgebungsvariablen gesetzt werden:

```bash
# 1. Semaphore Admin-Passwörter
export ADMIN1_PASS='<kolja-semaphore-password>'    # Existierender Admin
export ADMIN2_PASS='<ralf-semaphore-password>'     # Neuer Admin

# 2. Gitea Credentials (für Repository-Zugriff)
export GITEA_USER='kolja'
export GITEA_PASS='<kolja-gitea-password>'

# 3. Proxmox API Token (für OpenTofu)
export PROXMOX_API_TOKEN_ID='root@pam!ralf-tofu'
export PROXMOX_API_TOKEN_SECRET='<proxmox-api-secret>'

# 4. Database Passwords (für Ansible Playbooks)
export GITEA_DB_PASS='TestPass123Gitea'           # Automatisch erkannt
export PG_SUPERUSER_PASS='<postgres-superuser-pass>'
```

## Automatisch erkannte Werte

Einige Credentials können aus bestehenden Configs gelesen werden:

```bash
# Gitea DB Password (aus /etc/gitea/app.ini)
pct exec 2012 -- bash -lc "grep 'PASSWD' /etc/gitea/app.ini"
# => TestPass123Gitea

# Semaphore DB Password (aus /etc/semaphore/config.json)
pct exec 10015 -- bash -lc "grep 'pass' /etc/semaphore/config.json"
# => TestPass123Semaphore
```

## Proxmox API Token erstellen

Falls noch kein API Token existiert:

1. Proxmox Web-UI öffnen: https://10.10.10.10:8006
2. Datacenter → API Tokens → Create
3. User: `root@pam`
4. Token ID: `ralf-tofu`
5. Privilege Separation: **deaktiviert** (für volle root-Rechte)
6. Token Secret kopieren und in `PROXMOX_API_TOKEN_SECRET` speichern

## Ausführung

### Schritt 1: Credentials setzen

```bash
# Credentials in einer Datei speichern (NICHT ins Git committen!)
cat > /root/.semaphore-credentials.env <<'EOF'
export ADMIN1_PASS='SicheresPasswort123'
export ADMIN2_PASS='SicheresPasswort456'
export GITEA_PASS='GiteaPass123'
export PROXMOX_API_TOKEN_ID='root@pam!ralf-tofu'
export PROXMOX_API_TOKEN_SECRET='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
export GITEA_DB_PASS='TestPass123Gitea'
export PG_SUPERUSER_PASS='PostgresSuper123'
EOF

chmod 600 /root/.semaphore-credentials.env
```

### Schritt 2: Skript ausführen

```bash
# Credentials laden
source /root/.semaphore-credentials.env

# Konfiguration ausführen
bash /root/ralf/bootstrap/configure-semaphore.sh
```

## Optionale Konfiguration

Alle Werte können überschrieben werden:

```bash
# Beispiel: Andere Git-Branch oder Repository
export GIT_REPO_URL='http://10.10.20.12:3000/RALF-Homelab/ralf.git'
export GIT_REPO_BRANCH='develop'

# Beispiel: Andere Semaphore-URL
export SEMAPHORE_URL='http://10.10.100.15:3000'
```

## Was das Skript tut

### 1. Admin-User anlegen
```bash
/usr/local/bin/semaphore user add \
  --admin \
  --login 'ralf' \
  --name 'Ralf' \
  --email 'ralf@homelab.lan' \
  --password '<ADMIN2_PASS>' \
  --config /etc/semaphore/config.json
```

### 2. SSH-Key generieren
```bash
ssh-keygen -t ed25519 \
  -C 'semaphore@ops-semaphore' \
  -f /root/.ssh/id_ed25519 \
  -N ''
```

### 3. Semaphore API Login
```bash
curl -X POST http://10.10.100.15:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"auth": "kolja", "password": "<ADMIN1_PASS>"}'
# => Session Cookie
```

### 4. SSH-Key in Semaphore
```bash
curl -X POST http://10.10.100.15:3000/api/keys \
  -H "Cookie: semaphore=<session>" \
  -d '{
    "name": "ansible-ssh",
    "type": "ssh",
    "ssh": {"private_key": "<id_ed25519>"}
  }'
```

### 5. Git Repository
```bash
curl -X POST http://10.10.100.15:3000/api/project/1/repositories \
  -H "Cookie: semaphore=<session>" \
  -d '{
    "name": "ralf",
    "git_url": "http://10.10.20.12:3000/RALF-Homelab/ralf.git",
    "git_branch": "main",
    "ssh_key_id": <git_key_id>
  }'
```

### 6. Ansible Inventory
```bash
curl -X POST http://10.10.100.15:3000/api/project/1/inventory \
  -H "Cookie: semaphore=<session>" \
  -d '{
    "name": "hosts",
    "inventory": "all:\n  hosts:\n    localhost:\n      ansible_connection: local\n",
    "ssh_key_id": <ssh_key_id>,
    "type": "static"
  }'
```

### 7. Environment Variables
```bash
# Für jede Variable:
curl -X POST http://10.10.100.15:3000/api/project/1/environment \
  -H "Cookie: semaphore=<session>" \
  -d '{
    "name": "PROXMOX_API_URL",
    "project_id": 1,
    "secret": "https://10.10.10.10:8006/api2/json"
  }'
```

## Verifikation

Nach erfolgreicher Ausführung:

```bash
# 1. SSH-Key prüfen
pct exec 10015 -- bash -lc "ls -la /root/.ssh/id_ed25519*"

# 2. Semaphore Web-UI öffnen
firefox http://10.10.100.15:3000

# 3. Login testen
# User: ralf / kolja
# Password: wie in ADMIN1_PASS / ADMIN2_PASS gesetzt

# 4. Repository, Keys, Inventory prüfen
# Project Settings → Repositories
# Project Settings → Key Store
# Project Settings → Inventory
# Project Settings → Environment
```

## Troubleshooting

### Login fehlgeschlagen
```bash
# Prüfe ob Admin1-User existiert
pct exec 10015 -- bash -lc "semaphore user list --config /etc/semaphore/config.json"

# Prüfe Semaphore-Service
pct exec 10015 -- systemctl status semaphore
```

### SSH-Key bereits vorhanden
```bash
# Entfernen und neu generieren
pct exec 10015 -- bash -lc "rm -f /root/.ssh/id_ed25519*"
bash /root/ralf/bootstrap/configure-semaphore.sh
```

### API Error 401 (Unauthorized)
- Passwort falsch
- Session Cookie abgelaufen
- Semaphore neu starten: `pct exec 10015 -- systemctl restart semaphore`

### Repository bereits existiert
Das Skript erkennt existierende Ressourcen und überspringt die Erstellung.

## Nächste Schritte

Nach erfolgreicher Konfiguration:

1. ✅ SSH Public Key auf Ziel-Hosts verteilen
2. ✅ Erste Pipeline anlegen (Deploy PostgreSQL)
3. ✅ Pipeline testen
4. ✅ Terragrunt-Setup (Task #15)

## Sicherheitshinweise

- **NIEMALS** Credentials ins Git committen
- Credentials-Datei mit `chmod 600` schützen
- Nach Ausführung: `unset` alle Umgebungsvariablen
- Semaphore Environment Variables sind encrypted in der Datenbank
