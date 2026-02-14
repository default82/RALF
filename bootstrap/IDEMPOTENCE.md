# Bootstrap-Skripte: Idempotenz

## Übersicht

Alle Bootstrap-Skripte in `/root/ralf/bootstrap/` sind seit 2026-02-14 **idempotent** und können beliebig oft ausgeführt werden, ohne Fehler zu verursachen.

## Was bedeutet Idempotenz?

Ein Skript ist idempotent, wenn es:
- Mehrfach ausgeführt werden kann ohne Fehler
- Bestehende Ressourcen erkennt und überspringt
- Keine Daten verliert oder überschreibt (mit Backup)
- Immer zum gleichen Endzustand führt

## Implementierte Idempotenz-Patterns

### 1. Container-Erstellung

```bash
if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits -> ueberspringe create"
else
  # Container erstellen...
fi
```

**Verhalten:** Existierender Container → überspringen, neuer Container → erstellen

### 2. Datenbank-Erstellung

```bash
create_database_idempotent "$PG_DB" "$PG_USER" "$PG_PASS"
```

**Funktion aus `lib/common.sh`:**
- Prüft ob Datenbank existiert
- Erstellt User nur wenn nicht vorhanden
- Überspringt bei Existenz

**Betroffene Skripte:**
- `create-gitea.sh`
- `create-vaultwarden.sh`
- `create-n8n.sh`
- `create-matrix.sh`

### 3. Config-Dateien

```bash
# Erstelle Backup wenn Config bereits existiert
if [[ -f /etc/service/config.conf ]]; then
  BACKUP_FILE="/etc/service/config.conf.backup.$(date +%Y%m%d_%H%M%S)"
  echo "Config existiert bereits - erstelle Backup: $BACKUP_FILE"
  cp /etc/service/config.conf "$BACKUP_FILE"
fi

cat > /etc/service/config.conf <<EOF
...neue config...
EOF
```

**Verhalten:**
- Config existiert → Backup mit Timestamp erstellen
- Dann neue Config schreiben

**Backup-Format:** `*.backup.YYYYMMDD_HHMMSS`

**Betroffene Skripte:**
- `create-gitea.sh` (app.ini)
- `create-vaultwarden.sh` (config.env)
- `create-matrix.sh` (homeserver.yaml)
- `create-mail.sh` (maddy.conf)
- `create-n8n.sh` (n8n.service)
- `create-and-fill-runner.sh` (config.json)

### 4. Git-Repository clonen

```bash
if [[ -d /opt/repo/.git ]]; then
  echo 'Repository bereits gecloned - git pull'
  cd /opt/repo && git pull
else
  git clone https://... /opt/repo
fi
```

**Verhalten:** Repo existiert → `git pull`, sonst → `git clone`

**Betroffene Skripte:**
- `create-exo.sh`

### 5. VM-Erstellung (optional destruktiv)

```bash
FORCE_RECREATE="${FORCE_RECREATE:-false}"

if qm status "$VMID" >/dev/null 2>&1; then
  if [[ "$FORCE_RECREATE" == "true" ]]; then
    log "VM existiert -> loesche sie (FORCE_RECREATE=true)"
    qm stop "$VMID" 2>/dev/null || true
    qm destroy "$VMID"
  else
    log "VM existiert bereits - überspringe"
    exit 0
  fi
fi
```

**Verhalten:**
- Standard: VM existiert → exit 0
- Mit `FORCE_RECREATE=true`: VM löschen und neu erstellen

**Betroffene Skripte:**
- `create-ollama-vm.sh`

### 6. Snapshot-Strategie (unverändert)

```bash
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "pre-install"; then
  log "Snapshot pre-install existiert bereits"
else
  pct snapshot "$CTID" "pre-install"
fi
```

**Verhalten:** Snapshot existiert → überspringen, sonst → erstellen

**Alle Skripte:** Pre/Post-Install Snapshots bleiben erhalten!

## Zentrale Helper-Library

**Datei:** `/root/ralf/bootstrap/lib/common.sh`

**Wichtige Funktionen:**

```bash
# Basis-Helpers
log()                           # Logging
need_cmd()                      # Command-Check
pct_exec()                      # Container-Befehle (alte + neue Syntax)

# Container-Checks
container_exists()              # Prüft ob Container existiert
container_running()             # Prüft ob Container läuft
file_exists_in_container()      # Prüft Datei in Container
dir_exists_in_container()       # Prüft Verzeichnis in Container

# Datenbank-Funktionen
database_exists()               # Prüft ob DB existiert
database_user_exists()          # Prüft ob User existiert
create_database_idempotent()    # Erstellt DB idempotent

# Config-Management
write_config_idempotent()       # Schreibt Config mit Backup
create_config_if_missing()      # Erstellt Config nur wenn nicht vorhanden

# Git-Operationen
repo_exists()                   # Prüft ob Git-Repo existiert
repo_exists_in_container()      # Prüft Repo in Container
clone_repo_idempotent()         # Clone idempotent

# Snapshot-Management
create_snapshot_idempotent()    # Erstellt Snapshot nur wenn nicht vorhanden

# Service-Management
service_exists_in_container()   # Prüft ob Service existiert
service_running_in_container()  # Prüft ob Service läuft
enable_and_start_service()      # Enable + Start idempotent

# User-Management
user_exists_in_container()      # Prüft ob User existiert
create_user_idempotent()        # Erstellt User idempotent
```

## Verwendung

### Standard-Ausführung (idempotent)

```bash
# Ersten Start
bash bootstrap/create-gitea.sh

# Zweiten Start (ohne Fehler!)
bash bootstrap/create-gitea.sh
# → Container existiert → überspringe
# → Datenbank existiert → überspringe
# → Config existiert → Backup + neu schreiben
```

### VM mit Force-Recreate

```bash
# Normal: VM existiert → exit 0
bash bootstrap/create-ollama-vm.sh

# Force: VM löschen und neu erstellen
export FORCE_RECREATE=true
bash bootstrap/create-ollama-vm.sh
```

### Clean-Room-Test (Snapshot-Strategie)

```bash
# Kompletter Neuaufbau
pct destroy 2012
bash bootstrap/create-gitea.sh

# Rollback zu Snapshot
pct rollback 2012 pre-install
```

## Testing

### Test 1: Mehrfach-Ausführung

```bash
# Gitea zweimal deployen
bash bootstrap/create-gitea.sh
bash bootstrap/create-gitea.sh

# Erwartetes Verhalten:
# - Erster Lauf: Container + DB + Config erstellen
# - Zweiter Lauf: Container existiert, DB existiert, Config mit Backup
# - Kein Fehler!
```

### Test 2: Config-Backup

```bash
# Nach zweitem Lauf
pct exec 2012 -- ls -la /etc/gitea/app.ini*

# Erwartete Ausgabe:
# -rw-r----- 1 root git ... app.ini
# -rw-r----- 1 root git ... app.ini.backup.20260214_183045
```

### Test 3: Datenbank-Idempotenz

```bash
source /var/lib/ralf/credentials.env
source bootstrap/lib/common.sh

# Prüfen
database_exists "gitea"
echo $?  # 0 = existiert

# Nochmal erstellen (sollte überspringen)
create_database_idempotent "gitea" "gitea" "$GITEA_PG_PASS"
# Output: "Datenbank 'gitea' existiert bereits - überspringe"
```

## Migration von alten Skripten

**Vorher (nicht idempotent):**
```bash
# Fehler bei zweitem Lauf!
createdb gitea  # → ERROR: database already exists
cat > /etc/gitea/app.ini  # → überschreibt ohne Backup
```

**Nachher (idempotent):**
```bash
# Läuft immer ohne Fehler
create_database_idempotent "gitea" "gitea" "$PASS"  # → überspringe wenn existiert
# Config mit Backup-Check
```

## Git-Commit

Alle Änderungen in einem Commit:

```
Commit: 3ccc6b7
Titel: Idempotenz: Bootstrap-Skripte können mehrfach ausgeführt werden

Geänderte Dateien:
- bootstrap/lib/common.sh (neu)
- bootstrap/create-*.sh (8 Skripte)
```

## Weitere Informationen

- **Zentrale Credentials:** Siehe `CREDENTIALS.md`
- **Helper-Library:** Siehe `lib/common.sh`
- **Implementierungsplan:** Siehe `/root/.claude/plans/vectorized-puzzling-newt.md`
