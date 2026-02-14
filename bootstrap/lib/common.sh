#!/usr/bin/env bash
# ============================================================================
# RALF Bootstrap Common Library
# ============================================================================
# Idempotente Helper-Funktionen für alle Bootstrap-Skripte
#
# Usage:
#   source "$(dirname "$0")/lib/common.sh"
# ============================================================================

# ============================================================================
# Basic Helper Functions
# ============================================================================

log() {
  echo -e "\n==> $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1"
    exit 1
  }
}

pct_exec() {
  # Support both calling patterns:
  # 1. pct_exec "$CTID" "command"  (new style with explicit CTID)
  # 2. pct_exec "command"           (old style with global $CTID)
  local ctid
  local cmd

  if [[ $# -eq 1 ]]; then
    # Old style: use global $CTID
    ctid="${CTID}"
    cmd="$1"
  else
    # New style: first arg is CTID
    ctid="$1"
    shift
    cmd="$*"
  fi

  pct exec "$ctid" -- bash -lc "$cmd"
}

# ============================================================================
# Container Functions
# ============================================================================

# Prüfe ob Container existiert
container_exists() {
  local ctid="$1"
  pct status "$ctid" >/dev/null 2>&1
}

# Prüfe ob Container läuft
container_running() {
  local ctid="$1"
  pct status "$ctid" 2>/dev/null | grep -q "running"
}

# Prüfe ob File in Container existiert
file_exists_in_container() {
  local ctid="$1"
  local filepath="$2"
  pct_exec "$ctid" "test -f '$filepath'" 2>/dev/null
}

# Prüfe ob Directory in Container existiert
dir_exists_in_container() {
  local ctid="$1"
  local dirpath="$2"
  pct_exec "$ctid" "test -d '$dirpath'" 2>/dev/null
}

# ============================================================================
# Database Functions
# ============================================================================

# Prüfe ob PostgreSQL-Datenbank existiert
database_exists() {
  local db_name="$1"
  local pg_host="${2:-10.10.20.10}"
  local pg_port="${3:-5432}"
  local pg_ctid="${4:-2010}"

  pct exec "$pg_ctid" -- bash -lc "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$db_name'\"" 2>/dev/null \
    | grep -q 1
}

# Prüfe ob PostgreSQL-User existiert
database_user_exists() {
  local db_user="$1"
  local pg_host="${2:-10.10.20.10}"
  local pg_port="${3:-5432}"
  local pg_ctid="${4:-2010}"

  pct exec "$pg_ctid" -- bash -lc "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_user WHERE usename='$db_user'\"" 2>/dev/null \
    | grep -q 1
}

# Erstelle PostgreSQL-Datenbank idempotent
create_database_idempotent() {
  local db_name="$1"
  local db_user="$2"
  local db_pass="$3"
  local pg_host="${4:-10.10.20.10}"
  local pg_port="${5:-5432}"
  local pg_ctid="${6:-2010}"

  # Prüfe ob Datenbank bereits existiert
  if database_exists "$db_name" "$pg_host" "$pg_port" "$pg_ctid"; then
    log "Datenbank '$db_name' existiert bereits - überspringe Erstellung"
    return 0
  fi

  log "Erstelle Datenbank '$db_name' mit User '$db_user'"

  # Erstelle User nur wenn er nicht existiert
  if ! database_user_exists "$db_user" "$pg_host" "$pg_port" "$pg_ctid"; then
    pct exec "$pg_ctid" -- bash -lc "sudo -u postgres psql -c \"CREATE USER ${db_user} WITH PASSWORD '${db_pass}';\"" 2>/dev/null || {
        echo "WARNUNG: User-Erstellung fehlgeschlagen (User existiert möglicherweise bereits)"
      }
  fi

  # Erstelle Datenbank
  pct exec "$pg_ctid" -- bash -lc "sudo -u postgres psql <<EOF
CREATE DATABASE ${db_name} OWNER ${db_user};
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
EOF"

  if database_exists "$db_name" "$pg_host" "$pg_port" "$pg_ctid"; then
    log "Datenbank '$db_name' erfolgreich erstellt"
  else
    echo "FEHLER: Datenbank-Erstellung fehlgeschlagen!"
    return 1
  fi
}

# ============================================================================
# Configuration File Functions
# ============================================================================

# Schreibe Config-Datei idempotent (mit Backup bei Existenz)
write_config_idempotent() {
  local ctid="$1"
  local target_path="$2"
  local content="$3"
  local backup_suffix="${4:-.backup.$(date +%Y%m%d_%H%M%S)}"

  # Prüfe ob Datei existiert
  if file_exists_in_container "$ctid" "$target_path"; then
    log "Config-Datei existiert bereits: $target_path"
    log "Erstelle Backup: ${target_path}${backup_suffix}"
    pct_exec "$ctid" "cp '$target_path' '${target_path}${backup_suffix}'"
  fi

  # Schreibe neue Config (oder überschreibe nach Backup)
  pct_exec "$ctid" "cat > '$target_path' <<'EOFCONFIG'
$content
EOFCONFIG"

  log "Config-Datei geschrieben: $target_path"
}

# Erstelle Config-Datei nur wenn sie nicht existiert
create_config_if_missing() {
  local ctid="$1"
  local target_path="$2"
  local content="$3"

  if file_exists_in_container "$ctid" "$target_path"; then
    log "Config-Datei existiert bereits: $target_path - überspringe"
    return 0
  fi

  log "Erstelle Config-Datei: $target_path"
  pct_exec "$ctid" "cat > '$target_path' <<'EOFCONFIG'
$content
EOFCONFIG"
}

# ============================================================================
# Git Functions
# ============================================================================

# Prüfe ob Git-Repository bereits gecloned ist
repo_exists() {
  local dir="$1"
  test -d "$dir/.git"
}

# Prüfe ob Git-Repository in Container existiert
repo_exists_in_container() {
  local ctid="$1"
  local dir="$2"
  dir_exists_in_container "$ctid" "$dir/.git"
}

# Clone Git-Repository idempotent
clone_repo_idempotent() {
  local ctid="$1"
  local repo_url="$2"
  local target_dir="$3"

  if repo_exists_in_container "$ctid" "$target_dir"; then
    log "Repository bereits gecloned: $target_dir"
    log "Führe 'git pull' aus..."
    pct_exec "$ctid" "cd '$target_dir' && git pull" || {
      echo "WARNUNG: git pull fehlgeschlagen"
    }
  else
    log "Clone Repository: $repo_url -> $target_dir"
    pct_exec "$ctid" "git clone '$repo_url' '$target_dir'"
  fi
}

# ============================================================================
# Snapshot Functions
# ============================================================================

# Erstelle Snapshot idempotent (nur wenn nicht vorhanden)
create_snapshot_idempotent() {
  local ctid="$1"
  local snapshot_name="$2"

  if pct listsnapshot "$ctid" 2>/dev/null | grep -q "$snapshot_name"; then
    log "Snapshot '$snapshot_name' existiert bereits - überspringe"
    return 0
  fi

  log "Erstelle Snapshot: $snapshot_name"
  pct snapshot "$ctid" "$snapshot_name"
}

# ============================================================================
# Service Functions
# ============================================================================

# Prüfe ob systemd Service in Container existiert
service_exists_in_container() {
  local ctid="$1"
  local service_name="$2"
  pct_exec "$ctid" "systemctl list-unit-files | grep -q '$service_name'" 2>/dev/null
}

# Prüfe ob systemd Service in Container läuft
service_running_in_container() {
  local ctid="$1"
  local service_name="$2"
  pct_exec "$ctid" "systemctl is-active --quiet '$service_name'" 2>/dev/null
}

# Enable und starte Service idempotent
enable_and_start_service() {
  local ctid="$1"
  local service_name="$2"

  log "Enable und starte Service: $service_name"
  pct_exec "$ctid" "systemctl enable --now '$service_name'" || {
    echo "WARNUNG: Service-Start fehlgeschlagen"
    return 1
  }

  # Warte kurz und prüfe Status
  sleep 2
  if service_running_in_container "$ctid" "$service_name"; then
    log "Service '$service_name' läuft"
  else
    echo "WARNUNG: Service '$service_name' läuft nicht!"
    pct_exec "$ctid" "systemctl status '$service_name' --no-pager" || true
    return 1
  fi
}

# ============================================================================
# User Functions
# ============================================================================

# Prüfe ob User in Container existiert
user_exists_in_container() {
  local ctid="$1"
  local username="$2"
  pct_exec "$ctid" "id -u '$username'" 2>/dev/null
}

# Erstelle System-User idempotent
create_user_idempotent() {
  local ctid="$1"
  local username="$2"
  local home_dir="${3:-/var/lib/$username}"
  local shell="${4:-/bin/bash}"

  if user_exists_in_container "$ctid" "$username"; then
    log "User '$username' existiert bereits - überspringe"
    return 0
  fi

  log "Erstelle User: $username (Home: $home_dir)"
  pct_exec "$ctid" "useradd --system --home-dir '$home_dir' --create-home --shell '$shell' '$username'"
}

# ============================================================================
# MySQL/MariaDB Functions
# ============================================================================

# Prüfe ob MySQL-Datenbank existiert
mysql_database_exists() {
  local db_name="$1"
  local mysql_host="${2:-10.10.20.11}"
  local mysql_port="${3:-3306}"
  local mysql_root_pass="${4:-$MARIADB_ROOT_PASS}"

  mysql -h "$mysql_host" -P "$mysql_port" -u root -p"$mysql_root_pass" \
    -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$db_name'" 2>/dev/null \
    | grep -q "$db_name"
}

# Prüfe ob MySQL-User existiert
mysql_user_exists() {
  local db_user="$1"
  local mysql_host="${2:-10.10.20.11}"
  local mysql_port="${3:-3306}"
  local mysql_root_pass="${4:-$MARIADB_ROOT_PASS}"

  mysql -h "$mysql_host" -P "$mysql_port" -u root -p"$mysql_root_pass" \
    -sse "SELECT User FROM mysql.user WHERE User='$db_user'" 2>/dev/null \
    | grep -q "$db_user"
}

# Erstelle MySQL-Datenbank idempotent (via MariaDB Container)
create_mysql_database_idempotent() {
  local db_name="$1"
  local db_user="$2"
  local db_pass="$3"
  local mysql_host="${4:-10.10.20.11}"
  local mysql_port="${5:-3306}"
  local mysql_root_pass="${6:-$MARIADB_ROOT_PASS}"
  local mysql_ctid="${7:-2011}"

  # Check via MariaDB container
  if pct exec "$mysql_ctid" -- mysql -u root -p"$mysql_root_pass" -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$db_name'" 2>/dev/null | grep -q "$db_name"; then
    log "MySQL-Datenbank '$db_name' existiert bereits - überspringe"
    return 0
  fi

  log "Erstelle MySQL-Datenbank '$db_name' mit User '$db_user'"

  pct exec "$mysql_ctid" -- bash -c "mysql -u root -p'$mysql_root_pass' <<'EOFMYSQL'
CREATE DATABASE ${db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'%';
FLUSH PRIVILEGES;
EOFMYSQL
"

  log "MySQL-Datenbank '$db_name' erstellt"
}

# ============================================================================
# End of Common Library
# ============================================================================
