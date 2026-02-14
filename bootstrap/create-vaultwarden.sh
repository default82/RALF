#!/usr/bin/env bash
set -euo pipefail

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-3010}"                            # CT-ID im 30er Bereich (Security)
CT_HOSTNAME="${CT_HOSTNAME:-svc-vaultwarden}"   # -fz implied (Functional Zone)
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 30)
IP_CIDR="${IP_CIDR:-10.10.30.10/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen
MEMORY="${MEMORY:-1024}"     # MB (Vaultwarden ist ressourcensparend)
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-8}"

# Ubuntu Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# Vaultwarden (using Docker for binary extraction)
VAULTWARDEN_VERSION="${VAULTWARDEN_VERSION:-1.32.5}"
VAULTWARDEN_WEB_VERSION="${VAULTWARDEN_WEB_VERSION:-2024.12.2}"
VAULTWARDEN_WEB_URL="${VAULTWARDEN_WEB_URL:-https://github.com/dani-garcia/bw_web_builds/releases/download/v${VAULTWARDEN_WEB_VERSION}/bw_web_v${VAULTWARDEN_WEB_VERSION}.tar.gz}"

# Vaultwarden Config
VAULTWARDEN_PORT="${VAULTWARDEN_PORT:-8080}"
VAULTWARDEN_DOMAIN="${VAULTWARDEN_DOMAIN:-vault.homelab.lan}"
VAULTWARDEN_SIGNUPS_ALLOWED="${VAULTWARDEN_SIGNUPS_ALLOWED:-false}"
VAULTWARDEN_ADMIN_TOKEN="${VAULTWARDEN_ADMIN_TOKEN:-CHANGE_ME_NOW}"

# PostgreSQL Connection (MUSS bereits existieren!)
PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-vaultwarden}"
PG_USER="${PG_USER:-vaultwarden}"
PG_PASS="${PG_PASS:-CHANGE_ME_NOW}"

### =========================
### Preconditions
### =========================

need_cmd pct
need_cmd pveam
need_cmd pvesm
need_cmd curl
need_cmd openssl

if [[ "$PG_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: PG_PASS ist noch CHANGE_ME_NOW."
  echo "Setze PostgreSQL-Passwort fuer Vaultwarden-DB:"
  echo "  export PG_PASS='vaultwarden-db-passwort'"
  exit 1
fi

if [[ "$VAULTWARDEN_ADMIN_TOKEN" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: VAULTWARDEN_ADMIN_TOKEN ist noch CHANGE_ME_NOW."
  echo "Generiere Admin-Token:"
  echo "  export VAULTWARDEN_ADMIN_TOKEN=\$(openssl rand -base64 48)"
  exit 1
fi

log "Pruefe PostgreSQL-Erreichbarkeit (${PG_HOST}:${PG_PORT})"
if ! nc -zv "$PG_HOST" "$PG_PORT" 2>&1 | grep -q succeeded; then
  echo "ERROR: PostgreSQL unter ${PG_HOST}:${PG_PORT} nicht erreichbar!"
  echo "Bitte ZUERST PostgreSQL deployen:"
  echo "  bash bootstrap/create-postgresql.sh"
  exit 1
fi
log "PostgreSQL erreichbar ✓"

### =========================
### 0) Create PostgreSQL Database (idempotent)
### =========================

log "Erstelle PostgreSQL-Datenbank für Vaultwarden (idempotent)"
create_database_idempotent "$PG_DB" "$PG_USER" "$PG_PASS" "$PG_HOST" "$PG_PORT"

### =========================
### 1) Ensure template exists
### =========================

log "Pruefe Ubuntu Template: ${TPL_STORAGE}:vztmpl/${TPL_NAME}"
if ! pveam list "$TPL_STORAGE" | awk '{print $1}' | grep -qx "${TPL_STORAGE}:vztmpl/${TPL_NAME}"; then
  log "Template nicht gefunden -> lade herunter"
  pveam update >/dev/null
  pveam download "$TPL_STORAGE" "$TPL_NAME"
fi

### =========================
### 2) Create container (if not exists)
### =========================

if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits -> ueberspringe create"
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

log "Warte auf Boot..."
sleep 3

### =========================
### 3) Set DNS/search domain
### =========================

log "Setze resolv.conf (DNS=${DNS}, search=${SEARCHDOMAIN})"
pct_exec "printf 'search ${SEARCHDOMAIN}\\nnameserver ${DNS}\\n' > /etc/resolv.conf"

### =========================
### 4) Snapshot pre-install
### =========================

log "Erstelle Snapshot 'pre-install' (falls nicht vorhanden)"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "pre-install"; then
  log "Snapshot pre-install existiert bereits"
else
  pct snapshot "$CTID" "pre-install"
fi

### =========================
### 5) Base packages
### =========================

log "Installiere Basis-Tools im Container"
pct_exec "export DEBIAN_FRONTEND=noninteractive;
apt-get update -y;
apt-get install -y --no-install-recommends \
  ca-certificates curl wget postgresql-client locales openssl;
"

### =========================
### 6) Configure Locale
### =========================

log "Konfiguriere UTF-8 Locale"
pct_exec "
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
echo 'LANG=en_US.UTF-8' > /etc/default/locale
echo 'LC_ALL=en_US.UTF-8' >> /etc/default/locale
"

### =========================
### 7) Create vaultwarden user
### =========================

log "Erstelle vaultwarden-User"
pct_exec "
if ! id -u vaultwarden >/dev/null 2>&1; then
  useradd -m -s /bin/bash vaultwarden
fi
"

### =========================
### 8) Database already created in Step 0
### =========================

# Datenbank wurde bereits in Step 0 erstellt (idempotent)

### =========================
### 9) Install Vaultwarden binary
### =========================

log "Installiere Vaultwarden ${VAULTWARDEN_VERSION} -> /usr/local/bin/vaultwarden"
pct_exec "set -euo pipefail;
if [[ -f /usr/local/bin/vaultwarden ]]; then
  CURRENT_VERSION=\$(/usr/local/bin/vaultwarden --version 2>&1 | grep -oP 'Vaultwarden \K[0-9.]+' || echo 'unknown')
  if [[ \"\$CURRENT_VERSION\" == \"${VAULTWARDEN_VERSION}\" ]]; then
    echo 'Vaultwarden ${VAULTWARDEN_VERSION} bereits installiert'
    exit 0
  fi
fi

echo 'Installiere Docker fuer Binary-Extraktion...'
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y docker.io

echo 'Pulling Vaultwarden Docker Image: vaultwarden/server:${VAULTWARDEN_VERSION}'
docker pull vaultwarden/server:${VAULTWARDEN_VERSION}

echo 'Extrahiere Binary aus Docker Image...'
CONTAINER_ID=\$(docker create vaultwarden/server:${VAULTWARDEN_VERSION})
docker cp \${CONTAINER_ID}:/vaultwarden /usr/local/bin/vaultwarden
docker rm \${CONTAINER_ID}

echo 'Cleanup Docker...'
docker rmi vaultwarden/server:${VAULTWARDEN_VERSION}
apt-get purge -y docker.io
apt-get autoremove -y

chmod +x /usr/local/bin/vaultwarden
/usr/local/bin/vaultwarden --version
"

### =========================
### 10) Install Web Vault
### =========================

log "Installiere Web Vault ${VAULTWARDEN_WEB_VERSION} -> /var/lib/vaultwarden/web-vault"
pct_exec "set -euo pipefail;
mkdir -p /var/lib/vaultwarden

if [[ -d /var/lib/vaultwarden/web-vault ]]; then
  echo 'Web Vault bereits installiert'
else
  echo 'Downloading: ${VAULTWARDEN_WEB_URL}'
  cd /tmp
  curl -fsSL -o web-vault.tar.gz '${VAULTWARDEN_WEB_URL}'
  tar -xzf web-vault.tar.gz -C /var/lib/vaultwarden
  rm web-vault.tar.gz
  echo 'Web Vault installiert'
fi

chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
"

### =========================
### 11) Create Vaultwarden config
### =========================

log "Erstelle Vaultwarden config (/etc/vaultwarden/config.env)"
pct_exec "set -euo pipefail;

mkdir -p /etc/vaultwarden
mkdir -p /var/lib/vaultwarden/data

# Erstelle Backup wenn Config bereits existiert
if [[ -f /etc/vaultwarden/config.env ]]; then
  BACKUP_FILE=\"/etc/vaultwarden/config.env.backup.\$(date +%Y%m%d_%H%M%S)\"
  echo \"Config existiert bereits - erstelle Backup: \$BACKUP_FILE\"
  cp /etc/vaultwarden/config.env \"\$BACKUP_FILE\"
fi

cat >/etc/vaultwarden/config.env <<EOF
## Vaultwarden Configuration

# Database
DATABASE_URL=postgresql://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}

# Web Server
ROCKET_ADDRESS=0.0.0.0
ROCKET_PORT=${VAULTWARDEN_PORT}
WEB_VAULT_FOLDER=/var/lib/vaultwarden/web-vault
WEB_VAULT_ENABLED=true

# Domain
DOMAIN=https://${VAULTWARDEN_DOMAIN}

# Signups
SIGNUPS_ALLOWED=${VAULTWARDEN_SIGNUPS_ALLOWED}
INVITATIONS_ALLOWED=true

# Admin
ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}

# Security
DISABLE_ADMIN_TOKEN=false
DISABLE_ICON_DOWNLOAD=false

# Logging
LOG_LEVEL=info
LOG_FILE=/var/lib/vaultwarden/vaultwarden.log
EXTENDED_LOGGING=true

# Data folder
DATA_FOLDER=/var/lib/vaultwarden/data
EOF

chown root:vaultwarden /etc/vaultwarden/config.env
chmod 640 /etc/vaultwarden/config.env
"

### =========================
### 12) Create systemd service
### =========================

log "Erstelle Vaultwarden systemd service"
pct_exec "
cat >/etc/systemd/system/vaultwarden.service <<'EOF'
[Unit]
Description=Vaultwarden (Bitwarden-compatible server)
After=network.target postgresql.service
Wants=network.target

[Service]
Type=simple
User=vaultwarden
Group=vaultwarden
EnvironmentFile=/etc/vaultwarden/config.env
ExecStart=/usr/local/bin/vaultwarden
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vaultwarden
systemctl start vaultwarden
"

### =========================
### 13) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  log "Snapshot post-install existiert bereits"
else
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 14) Final checks
### =========================

log "Checks: Service status + Port listening"
pct_exec "systemctl is-active vaultwarden; ss -lntp | grep -E ':${VAULTWARDEN_PORT}\\b' || true"

log "FERTIG"
echo "Vaultwarden ${VAULTWARDEN_VERSION} sollte jetzt erreichbar sein:"
echo "  HTTP: http://${IP_CIDR%/*}:${VAULTWARDEN_PORT}"
echo "  Admin Panel: http://${IP_CIDR%/*}:${VAULTWARDEN_PORT}/admin"
echo ""
echo "Naechste Schritte:"
echo "  1. Web-UI aufrufen und Account erstellen"
echo "  2. Admin Panel: mit ADMIN_TOKEN einloggen"
echo "  3. Weitere User einladen (INVITATIONS_ALLOWED=true)"
echo "  4. Reverse Proxy (Caddy) einrichten für HTTPS"
echo "  5. Credentials aus Bootstrap-Skripten migrieren"
echo ""
echo "Admin Token:"
echo "  ${VAULTWARDEN_ADMIN_TOKEN}"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
