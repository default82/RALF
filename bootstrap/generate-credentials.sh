#!/usr/bin/env bash
set -euo pipefail

### =========================
### Zentrale Credential-Generierung für RALF Homelab
### =========================
###
### Dieses Skript generiert alle benötigten Passwörter und Tokens
### und speichert sie in /var/lib/ralf/credentials.env
###
### WICHTIG: Diese Datei ist NICHT im Git-Repository!
###
### Usage:
###   bash bootstrap/generate-credentials.sh
###   source /var/lib/ralf/credentials.env
###

CREDS_DIR="${CREDS_DIR:-/var/lib/ralf}"
CREDS_FILE="${CREDS_DIR}/credentials.env"

### =========================
### Helpers
### =========================

log() { echo -e "\n==> $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }
}

generate_password() {
  local length="${1:-32}"
  openssl rand -base64 "$length" | tr -d '\n'
}

generate_token() {
  local length="${2:-64}"
  openssl rand -base64 "$length" | tr -d '\n'
}

### =========================
### Preconditions
### =========================

need_cmd openssl
need_cmd date

log "RALF Homelab - Zentrale Credential-Generierung"

### =========================
### Erstelle Verzeichnis
### =========================

if [ ! -d "$CREDS_DIR" ]; then
  log "Erstelle Verzeichnis: $CREDS_DIR"
  mkdir -p "$CREDS_DIR"
  chmod 700 "$CREDS_DIR"
fi

### =========================
### Prüfe ob Credentials bereits existieren
### =========================

if [ -f "$CREDS_FILE" ]; then
  log "WARNUNG: $CREDS_FILE existiert bereits!"
  echo "Möchtest du die Credentials neu generieren? (Dies überschreibt alte Werte!)"
  echo "Drücke ENTER zum Überschreiben, Ctrl+C zum Abbrechen"
  read -r

  # Backup erstellen
  BACKUP_FILE="${CREDS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  log "Erstelle Backup: $BACKUP_FILE"
  cp "$CREDS_FILE" "$BACKUP_FILE"
  chmod 600 "$BACKUP_FILE"
fi

### =========================
### Generiere Credentials
### =========================

log "Generiere sichere Passwörter und Tokens..."

cat > "$CREDS_FILE" <<EOFCREDS
# ============================================================================
# RALF Homelab - Zentrale Credentials
# ============================================================================
# Generiert: $(date -Is)
# WARNUNG: Diese Datei enthält sensible Daten!
# ============================================================================

# ============================================================================
# PostgreSQL Database Passwords
# ============================================================================

# PostgreSQL Master Password (postgres user)
export POSTGRES_MASTER_PASS="$(generate_password 32)"

# Gitea Database
export GITEA_PG_PASS="$(generate_password 32)"

# Semaphore Database
export SEMAPHORE_PG_PASS="$(generate_password 32)"

# Vaultwarden Database
export VAULTWARDEN_PG_PASS="$(generate_password 32)"

# n8n Database
export N8N_PG_PASS="$(generate_password 32)"

# Matrix/Synapse Database
export MATRIX_PG_PASS="$(generate_password 32)"

# ============================================================================
# Service Admin Accounts
# ============================================================================

# Gitea Admin Accounts
export GITEA_ADMIN1_USER="kolja"
export GITEA_ADMIN1_EMAIL="kolja@homelab.lan"
export GITEA_ADMIN1_PASS="$(generate_password 24)"

export GITEA_ADMIN2_USER="ralf"
export GITEA_ADMIN2_EMAIL="ralf@homelab.lan"
export GITEA_ADMIN2_PASS="$(generate_password 24)"

# Semaphore Admin
export SEMAPHORE_ADMIN_USER="admin"
export SEMAPHORE_ADMIN_EMAIL="admin@homelab.lan"
export SEMAPHORE_ADMIN_PASS="$(generate_password 24)"

# Vaultwarden Admin Token
export VAULTWARDEN_ADMIN_TOKEN="$(generate_token 64)"

# n8n Admin Accounts
export N8N_ADMIN1_USER="kolja"
export N8N_ADMIN1_EMAIL="kolja@homelab.lan"
export N8N_ADMIN1_PASS="$(generate_password 24)"

export N8N_ADMIN2_USER="ralf"
export N8N_ADMIN2_EMAIL="ralf@homelab.lan"
export N8N_ADMIN2_PASS="$(generate_password 24)"

export N8N_ENCRYPTION_KEY="$(generate_password 40)"

# Matrix/Synapse Admin Accounts
export MATRIX_ADMIN1_USER="kolja"
export MATRIX_ADMIN1_EMAIL="kolja@homelab.lan"
export MATRIX_ADMIN1_PASS="$(generate_password 24)"

export MATRIX_ADMIN2_USER="ralf"
export MATRIX_ADMIN2_EMAIL="ralf@homelab.lan"
export MATRIX_ADMIN2_PASS="$(generate_password 24)"

export MATRIX_REGISTRATION_SECRET="$(generate_password 40)"
export MATRIX_SERVER_NAME="homelab.lan"
export MATRIX_DOMAIN="matrix.homelab.lan"

# ============================================================================
# Mail Accounts
# ============================================================================

export MAIL_ACCOUNT1_USER="kolja"
export MAIL_ACCOUNT1_EMAIL="kolja@homelab.lan"
export MAIL_ACCOUNT1_PASS="$(generate_password 24)"

export MAIL_ACCOUNT2_USER="ralf"
export MAIL_ACCOUNT2_EMAIL="ralf@homelab.lan"
export MAIL_ACCOUNT2_PASS="$(generate_password 24)"

# ============================================================================
# API Tokens & Secrets
# ============================================================================

# Gitea Secret Keys (werden auch in app.ini verwendet)
export GITEA_SECRET_KEY="$(generate_token 32)"
export GITEA_INTERNAL_TOKEN="$(generate_token 64)"

# ============================================================================
# Network & Infrastructure
# ============================================================================

# PostgreSQL Server
export PG_HOST="10.10.20.10"
export PG_PORT="5432"

# Gitea Server
export GITEA_HOST="10.10.20.12"
export GITEA_HTTP_PORT="3000"
export GITEA_SSH_PORT="2222"
export GITEA_DOMAIN="gitea.homelab.lan"

# Semaphore Server
export SEMAPHORE_HOST="10.10.100.15"
export SEMAPHORE_PORT="3000"

# Vaultwarden Server
export VAULTWARDEN_HOST="10.10.30.10"
export VAULTWARDEN_PORT="8080"
export VAULTWARDEN_DOMAIN="vault.homelab.lan"

# n8n Server
export N8N_HOST="10.10.40.11"
export N8N_PORT="5678"

# Matrix/Synapse Server
export MATRIX_HOST="10.10.40.12"
export MATRIX_PORT="8008"

# Mail Server
export MAIL_HOST="10.10.40.10"
export MAIL_SMTP_PORT="25"
export MAIL_IMAP_PORT="143"

# Ollama Server
export OLLAMA_HOST="10.10.40.13"
export OLLAMA_PORT="11434"

# ============================================================================
# Metadata
# ============================================================================

export RALF_CREDS_VERSION="1.0"
export RALF_CREDS_GENERATED="$(date -Is)"

# ============================================================================
# END OF CREDENTIALS
# ============================================================================
EOFCREDS

### =========================
### Setze Permissions
### =========================

chmod 600 "$CREDS_FILE"

log "Credentials erfolgreich generiert!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Datei: $CREDS_FILE"
echo "  Permissions: 600 (nur root lesbar)"
echo "  Größe: $(wc -l < "$CREDS_FILE") Zeilen"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Verwendung in Bootstrap-Skripten:"
echo "  source /var/lib/ralf/credentials.env"
echo "  bash bootstrap/create-gitea.sh"
echo ""
echo "WICHTIG: Diese Datei ist NICHT im Git-Repository!"
echo "         Erstelle Backups: /var/lib/ralf/credentials.env.backup.*"
echo ""
