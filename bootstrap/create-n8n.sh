#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-4011}"
CT_HOSTNAME="${CT_HOSTNAME:-svc-n8n}"
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 40 - Web & Admin)
IP_CIDR="${IP_CIDR:-10.10.40.11/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen
MEMORY="${MEMORY:-2048}"
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-16}"

# Ubuntu Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# n8n
N8N_VERSION="${N8N_VERSION:-latest}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_DOMAIN="${N8N_DOMAIN:-n8n.homelab.lan}"

# PostgreSQL Connection
PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-n8n}"
PG_USER="${PG_USER:-n8n}"
PG_PASS="${PG_PASS:-CHANGE_ME_NOW}"

# n8n Config
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-CHANGE_ME_NOW}"
N8N_ADMIN1_EMAIL="${N8N_ADMIN1_EMAIL:-kolja@homelab.lan}"
N8N_ADMIN1_PASS="${N8N_ADMIN1_PASS:-CHANGE_ME_NOW}"
N8N_ADMIN2_EMAIL="${N8N_ADMIN2_EMAIL:-ralf@homelab.lan}"
N8N_ADMIN2_PASS="${N8N_ADMIN2_PASS:-CHANGE_ME_NOW}"

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
need_cmd pveam

if [[ "$PG_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: PG_PASS ist noch CHANGE_ME_NOW."
  exit 1
fi

if [[ "$N8N_ENCRYPTION_KEY" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: N8N_ENCRYPTION_KEY ist noch CHANGE_ME_NOW."
  exit 1
fi

log "Pruefe PostgreSQL-Erreichbarkeit (${PG_HOST}:${PG_PORT})"
if ! nc -zv "$PG_HOST" "$PG_PORT" 2>&1 | grep -q succeeded; then
  echo "ERROR: PostgreSQL unter ${PG_HOST}:${PG_PORT} nicht erreichbar!"
  exit 1
fi
log "PostgreSQL erreichbar ✓"

### =========================
### 1) Ensure template exists
### =========================

log "Pruefe Ubuntu Template"
if ! pveam list "$TPL_STORAGE" | awk '{print $1}' | grep -qx "${TPL_STORAGE}:vztmpl/${TPL_NAME}"; then
  log "Template nicht gefunden -> lade herunter"
  pveam update >/dev/null
  pveam download "$TPL_STORAGE" "$TPL_NAME"
fi

### =========================
### 2) Create container
### =========================

if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits"
else
  log "Erstelle LXC CT ${CTID} (${CT_HOSTNAME}) mit IP ${IP_CIDR}"
  pct create "$CTID" "${TPL_STORAGE}:vztmpl/${TPL_NAME}" \
    --hostname "$CT_HOSTNAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --rootfs "local-lvm:${DISK_GB}" \
    --onboot 1 \
    --features "keyctl=1,nesting=1" \
    --unprivileged 1
fi

log "Starte CT ${CTID}"
pct start "$CTID" 2>/dev/null || true
sleep 3

### =========================
### 3) Set DNS
### =========================

log "Setze resolv.conf"
pct_exec "printf 'search ${SEARCHDOMAIN}\\nnameserver ${DNS}\\n' > /etc/resolv.conf"

### =========================
### 4) Snapshot pre-install
### =========================

log "Erstelle Snapshot 'pre-install'"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "pre-install"; then
  log "Snapshot pre-install existiert bereits"
else
  pct snapshot "$CTID" "pre-install"
fi

### =========================
### 5) Install Node.js
### =========================

log "Installiere Node.js 20.x"
pct_exec "export DEBIAN_FRONTEND=noninteractive;
apt-get update -y;
apt-get install -y ca-certificates curl gnupg locales postgresql-client;

mkdir -p /etc/apt/keyrings;
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg;

echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main' > /etc/apt/sources.list.d/nodesource.list;

apt-get update -y;
apt-get install -y nodejs;
"

### =========================
### 6) Configure Locale
### =========================

log "Konfiguriere UTF-8 Locale"
pct_exec "
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
echo 'LANG=en_US.UTF-8' > /etc/default/locale
"

### =========================
### 7) Install n8n
### =========================

log "Installiere n8n via npm"
pct_exec "npm install -g n8n@${N8N_VERSION}"

### =========================
### 8) Create n8n user
### =========================

log "Erstelle n8n-User"
pct_exec "
if ! id -u n8n >/dev/null 2>&1; then
  useradd -m -s /bin/bash n8n
fi
mkdir -p /home/n8n/.n8n
chown -R n8n:n8n /home/n8n
"

### =========================
### 9) Create n8n config
### =========================

log "Erstelle n8n Umgebungsvariablen"
pct_exec "
cat > /etc/n8n/config.env <<EOF
# Database
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=${PG_HOST}
DB_POSTGRESDB_PORT=${PG_PORT}
DB_POSTGRESDB_DATABASE=${PG_DB}
DB_POSTGRESDB_USER=${PG_USER}
DB_POSTGRESDB_PASSWORD=${PG_PASS}

# Server
N8N_HOST=0.0.0.0
N8N_PORT=${N8N_PORT}
N8N_PROTOCOL=http
WEBHOOK_URL=http://${N8N_DOMAIN}:${N8N_PORT}/

# Security
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Basic Auth (initial)
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=${N8N_ADMIN1_PASS}

# Paths
N8N_USER_FOLDER=/home/n8n/.n8n
N8N_LOG_LEVEL=info

# Features
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EOF

mkdir -p /etc/n8n
chown root:n8n /etc/n8n/config.env
chmod 640 /etc/n8n/config.env
"

### =========================
### 10) Create systemd service
### =========================

log "Erstelle n8n systemd service"
pct_exec "
cat > /etc/systemd/system/n8n.service <<'EOF'
[Unit]
Description=n8n - Workflow Automation
After=network.target postgresql.service
Wants=network.target

[Service]
Type=simple
User=n8n
Group=n8n
EnvironmentFile=/etc/n8n/config.env
ExecStart=/usr/bin/n8n start
Restart=on-failure
RestartSec=3
WorkingDirectory=/home/n8n

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable n8n
systemctl start n8n
"

### =========================
### 11) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  log "Snapshot post-install existiert bereits"
else
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 12) Final checks
### =========================

log "Checks: Service status + Port listening"
pct_exec "systemctl is-active n8n; ss -lntp | grep ':${N8N_PORT}' || true"

log "FERTIG"
echo "n8n sollte jetzt erreichbar sein:"
echo "  HTTP: http://${IP_CIDR%/*}:${N8N_PORT}"
echo ""
echo "Login (Basic Auth):"
echo "  User: admin"
echo "  Pass: ${N8N_ADMIN1_PASS}"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
