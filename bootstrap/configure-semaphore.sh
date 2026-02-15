#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG
### =========================

CTID="${CTID:-10015}"
SEMAPHORE_URL="${SEMAPHORE_URL:-http://10.10.100.15:3000}"

# Admin User 1 (bereits angelegt)
ADMIN1_USER="${ADMIN1_USER:-kolja}"
ADMIN1_EMAIL="${ADMIN1_EMAIL:-kolja@homelab.lan}"
ADMIN1_PASS="${ADMIN1_PASS:-CHANGE_ME_NOW}"

# Admin User 2 (neu)
ADMIN2_USER="${ADMIN2_USER:-ralf}"
ADMIN2_NAME="${ADMIN2_NAME:-Ralf}"
ADMIN2_EMAIL="${ADMIN2_EMAIL:-ralf@homelab.lan}"
ADMIN2_PASS="${ADMIN2_PASS:-CHANGE_ME_NOW}"

# Git Repository (Gitea)
GIT_REPO_URL="${GIT_REPO_URL:-http://10.10.20.12:3000/RALF-Homelab/ralf.git}"
GIT_REPO_NAME="${GIT_REPO_NAME:-ralf}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

# Gitea Credentials (für Repository-Zugriff)
GITEA_USER="${GITEA_USER:-kolja}"
GITEA_PASS="${GITEA_PASS:-CHANGE_ME_NOW}"

# Environment Variables (Semaphore)
PROXMOX_API_URL="${PROXMOX_API_URL:-https://10.10.10.10:8006/api2/json}"
PROXMOX_API_TOKEN_ID="${PROXMOX_API_TOKEN_ID:-CHANGE_ME_NOW}"
PROXMOX_API_TOKEN_SECRET="${PROXMOX_API_TOKEN_SECRET:-CHANGE_ME_NOW}"
GITEA_DB_PASS="${GITEA_DB_PASS:-CHANGE_ME_NOW}"
PG_SUPERUSER_PASS="${PG_SUPERUSER_PASS:-CHANGE_ME_NOW}"

### =========================
### Helpers
### =========================

log() { echo -e "\n==> $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }
}

pct_exec() {
  local cmd="$1"
  pct exec "$CTID" -- bash -lc "$cmd"
}

### =========================
### Preconditions
### =========================

need_cmd pct
need_cmd curl
need_cmd jq

if [[ "$ADMIN1_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: ADMIN1_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Passwort für ${ADMIN1_USER}:"
  echo "  export ADMIN1_PASS='sicheres-passwort'"
  exit 1
fi

if [[ "$ADMIN2_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: ADMIN2_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Passwort für ${ADMIN2_USER}:"
  echo "  export ADMIN2_PASS='sicheres-passwort'"
  exit 1
fi

if [[ "$GITEA_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: GITEA_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Gitea-Passwort für ${GITEA_USER}:"
  echo "  export GITEA_PASS='gitea-passwort'"
  exit 1
fi

log "Prüfe Semaphore-Erreichbarkeit (${SEMAPHORE_URL})"
if ! curl -sf "${SEMAPHORE_URL}/api/ping" >/dev/null; then
  echo "ERROR: Semaphore nicht erreichbar unter ${SEMAPHORE_URL}"
  exit 1
fi
log "Semaphore erreichbar ✓"

### =========================
### 1) Erstelle zweiten Admin-User
### =========================

log "Erstelle Admin-User: ${ADMIN2_USER}"
pct_exec "set -euo pipefail;

# Prüfe ob User bereits existiert
if /usr/local/bin/semaphore user list --config /etc/semaphore/config.json 2>/dev/null | grep -qi '${ADMIN2_USER}'; then
  echo 'User ${ADMIN2_USER} existiert bereits'
else
  /usr/local/bin/semaphore user add \
    --admin \
    --login '${ADMIN2_USER}' \
    --name '${ADMIN2_NAME}' \
    --email '${ADMIN2_EMAIL}' \
    --password '${ADMIN2_PASS}' \
    --config /etc/semaphore/config.json
  echo 'Admin-User ${ADMIN2_USER} erstellt'
fi
"

### =========================
### 2) Generiere SSH-Keypair für Ansible
### =========================

log "Generiere SSH-Keypair (ed25519)"
pct_exec "set -euo pipefail;

if [[ -f /root/.ssh/id_ed25519 ]]; then
  echo 'SSH-Key existiert bereits: /root/.ssh/id_ed25519'
else
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  ssh-keygen -t ed25519 -C 'semaphore@ops-semaphore' -f /root/.ssh/id_ed25519 -N ''
  echo 'SSH-Key generiert: /root/.ssh/id_ed25519'
fi

echo ''
echo 'Public Key:'
cat /root/.ssh/id_ed25519.pub
"

### =========================
### 3) Wait for Semaphore API to be ready
### =========================

log "Warte auf Semaphore API Bereitschaft..."

MAX_WAIT=60
WAIT_COUNT=0
API_READY=false

while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
  if curl -sf "${SEMAPHORE_URL}/api/ping" >/dev/null 2>&1; then
    API_READY=true
    log "Semaphore API bereit nach ${WAIT_COUNT}s"
    break
  fi
  sleep 1
  WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [[ "$API_READY" != "true" ]]; then
  echo "ERROR: Semaphore API nicht bereit nach ${MAX_WAIT}s"
  exit 1
fi

### =========================
### 4) Login via Semaphore API (Session Cookie)
### =========================

log "Login als ${ADMIN1_USER} via Semaphore API"

# Semaphore benutzt Session Cookies, keinen API Token wie Gitea
# Login: POST /api/auth/login mit auth+password
# Response: Set-Cookie Header mit Session

SESSION_COOKIE=$(curl -sf -c - \
  -X POST "${SEMAPHORE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"auth\": \"${ADMIN1_USER}\", \"password\": \"${ADMIN1_PASS}\"}" \
  | grep 'semaphore' | awk '{print $7}')

if [[ -z "$SESSION_COOKIE" ]]; then
  echo "ERROR: Login fehlgeschlagen - kein Session Cookie erhalten"
  exit 1
fi

log "Login erfolgreich, Session Cookie erhalten"

### =========================
### 4) SSH-Key in Semaphore hinterlegen
### =========================

log "Hole SSH Private Key aus Container"
SSH_PRIVATE_KEY=$(pct_exec "cat /root/.ssh/id_ed25519")

log "Erstelle SSH-Key in Semaphore"

# Prüfe ob Key bereits existiert
KEY_EXISTS=$(curl -sf \
  -X GET "${SEMAPHORE_URL}/api/keys" \
  -H "Cookie: semaphore=${SESSION_COOKIE}" \
  | jq -r '.[] | select(.name=="ansible-ssh") | .id' || echo "")

if [[ -n "$KEY_EXISTS" ]]; then
  log "SSH-Key 'ansible-ssh' existiert bereits (ID: ${KEY_EXISTS})"
  SSH_KEY_ID="$KEY_EXISTS"
else
  SSH_KEY_ID=$(curl -sf \
    -X POST "${SEMAPHORE_URL}/api/keys" \
    -H "Cookie: semaphore=${SESSION_COOKIE}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"ansible-ssh\",
      \"type\": \"ssh\",
      \"login_password\": {
        \"login\": \"root\",
        \"password\": \"\"
      },
      \"ssh\": {
        \"private_key\": $(echo "$SSH_PRIVATE_KEY" | jq -Rs .)
      }
    }" \
    | jq -r '.id')

  log "SSH-Key erstellt (ID: ${SSH_KEY_ID})"
fi

### =========================
### 5) Git Repository in Semaphore hinzufügen
### =========================

log "Erstelle Git-Repository in Semaphore"

# Prüfe ob Repository bereits existiert
REPO_EXISTS=$(curl -sf \
  -X GET "${SEMAPHORE_URL}/api/project/1/repositories" \
  -H "Cookie: semaphore=${SESSION_COOKIE}" \
  2>/dev/null | jq -r ".[] | select(.name==\"${GIT_REPO_NAME}\") | .id" || echo "")

if [[ -n "$REPO_EXISTS" ]]; then
  log "Repository '${GIT_REPO_NAME}' existiert bereits (ID: ${REPO_EXISTS})"
  REPO_ID="$REPO_EXISTS"
else
  # Erstelle Login-Key für Git Repository (HTTP Auth)
  GIT_KEY_ID=$(curl -sf \
    -X POST "${SEMAPHORE_URL}/api/keys" \
    -H "Cookie: semaphore=${SESSION_COOKIE}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"gitea-http\",
      \"type\": \"login_password\",
      \"login_password\": {
        \"login\": \"${GITEA_USER}\",
        \"password\": \"${GITEA_PASS}\"
      }
    }" \
    | jq -r '.id')

  log "Git-Credentials erstellt (Key ID: ${GIT_KEY_ID})"

  # Erstelle Repository
  REPO_ID=$(curl -sf \
    -X POST "${SEMAPHORE_URL}/api/project/1/repositories" \
    -H "Cookie: semaphore=${SESSION_COOKIE}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${GIT_REPO_NAME}\",
      \"git_url\": \"${GIT_REPO_URL}\",
      \"git_branch\": \"${GIT_REPO_BRANCH}\",
      \"ssh_key_id\": ${GIT_KEY_ID}
    }" \
    | jq -r '.id')

  log "Repository erstellt (ID: ${REPO_ID})"
fi

### =========================
### 6) Ansible Inventory hinzufügen
### =========================

log "Erstelle Ansible Inventory in Semaphore"

# Prüfe ob Inventory bereits existiert
INV_EXISTS=$(curl -sf \
  -X GET "${SEMAPHORE_URL}/api/project/1/inventory" \
  -H "Cookie: semaphore=${SESSION_COOKIE}" \
  2>/dev/null | jq -r '.[] | select(.name=="hosts") | .id' || echo "")

if [[ -n "$INV_EXISTS" ]]; then
  log "Inventory 'hosts' existiert bereits (ID: ${INV_EXISTS})"
  INV_ID="$INV_EXISTS"
else
  INV_ID=$(curl -sf \
    -X POST "${SEMAPHORE_URL}/api/project/1/inventory" \
    -H "Cookie: semaphore=${SESSION_COOKIE}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"hosts\",
      \"project_id\": 1,
      \"inventory\": \"all:\\n  hosts:\\n    localhost:\\n      ansible_connection: local\\n\",
      \"ssh_key_id\": ${SSH_KEY_ID},
      \"type\": \"static\"
    }" \
    | jq -r '.id')

  log "Inventory erstellt (ID: ${INV_ID})"
fi

### =========================
### 7) Environment Variables anlegen
### =========================

log "Erstelle Environment Variables in Semaphore"

# Helper-Funktion: Environment Variable erstellen oder updaten
create_or_update_env() {
  local name="$1"
  local value="$2"

  # Prüfe ob Variable bereits existiert
  local exists
  exists=$(curl -sf \
    -X GET "${SEMAPHORE_URL}/api/project/1/environment" \
    -H "Cookie: semaphore=${SESSION_COOKIE}" \
    2>/dev/null | jq -r ".[] | select(.name==\"${name}\") | .id" || echo "")

  if [[ -n "$exists" ]]; then
    echo "  ${name}: bereits vorhanden (ID: ${exists})"
  else
    local id
    id=$(curl -sf \
      -X POST "${SEMAPHORE_URL}/api/project/1/environment" \
      -H "Cookie: semaphore=${SESSION_COOKIE}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${name}\",
        \"project_id\": 1,
        \"secret\": $(echo "$value" | jq -Rs .)
      }" \
      | jq -r '.id')
    echo "  ${name}: erstellt (ID: ${id})"
  fi
}

create_or_update_env "PROXMOX_API_URL" "$PROXMOX_API_URL"
create_or_update_env "PROXMOX_API_TOKEN_ID" "$PROXMOX_API_TOKEN_ID"
create_or_update_env "PROXMOX_API_TOKEN_SECRET" "$PROXMOX_API_TOKEN_SECRET"
create_or_update_env "GITEA_DB_PASS" "$GITEA_DB_PASS"
create_or_update_env "PG_SUPERUSER_PASS" "$PG_SUPERUSER_PASS"

### =========================
### 8) Final Summary
### =========================

log "FERTIG ✅"
echo ""
echo "Semaphore Konfiguration abgeschlossen:"
echo ""
echo "Admin-Users:"
echo "  - ${ADMIN1_USER} (${ADMIN1_EMAIL})"
echo "  - ${ADMIN2_USER} (${ADMIN2_EMAIL})"
echo ""
echo "SSH-Key:"
echo "  - ansible-ssh (ID: ${SSH_KEY_ID})"
echo ""
echo "Git Repository:"
echo "  - ${GIT_REPO_NAME} (ID: ${REPO_ID})"
echo "  - URL: ${GIT_REPO_URL}"
echo ""
echo "Ansible Inventory:"
echo "  - hosts (ID: ${INV_ID})"
echo ""
echo "Environment Variables:"
echo "  - PROXMOX_API_URL"
echo "  - PROXMOX_API_TOKEN_ID"
echo "  - PROXMOX_API_TOKEN_SECRET"
echo "  - GITEA_DB_PASS"
echo "  - PG_SUPERUSER_PASS"
echo ""
echo "Naechste Schritte:"
echo "  1. Semaphore Web-UI aufrufen: ${SEMAPHORE_URL}"
echo "  2. Pipeline anlegen und testen"
echo "  3. SSH Public Key auf Ziel-Hosts verteilen"
echo ""
