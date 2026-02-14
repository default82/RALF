#!/usr/bin/env bash
set -euo pipefail

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

### =========================
### CONFIG
### =========================

# Proxmox
CTID="${CTID:-4012}"
CT_HOSTNAME="${CT_HOSTNAME:-svc-matrix}"
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk
IP_CIDR="${IP_CIDR:-10.10.40.12/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen
MEMORY="${MEMORY:-4096}"  # Matrix braucht mehr RAM
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-32}"

# Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# Matrix/Synapse
MATRIX_VERSION="${MATRIX_VERSION:-latest}"
MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-homelab.lan}"
MATRIX_DOMAIN="${MATRIX_DOMAIN:-matrix.homelab.lan}"
SYNAPSE_PORT="${SYNAPSE_PORT:-8008}"

# Element Web
ELEMENT_VERSION="${ELEMENT_VERSION:-v1.11.91}"

# PostgreSQL
PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-synapse}"
PG_USER="${PG_USER:-synapse}"
PG_PASS="${PG_PASS:-CHANGE_ME_NOW}"

# Matrix Config
MATRIX_REGISTRATION_SECRET="${MATRIX_REGISTRATION_SECRET:-CHANGE_ME_NOW}"
MATRIX_ADMIN1_USER="${MATRIX_ADMIN1_USER:-kolja}"
MATRIX_ADMIN1_PASS="${MATRIX_ADMIN1_PASS:-CHANGE_ME_NOW}"
MATRIX_ADMIN2_USER="${MATRIX_ADMIN2_USER:-ralf}"
MATRIX_ADMIN2_PASS="${MATRIX_ADMIN2_PASS:-CHANGE_ME_NOW}"

### =========================
### Preconditions
### =========================

need_cmd pct
need_cmd pveam

if [[ "$PG_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: PG_PASS nicht gesetzt"
  exit 1
fi

log "Pruefe PostgreSQL-Erreichbarkeit"
if ! nc -zv "$PG_HOST" "$PG_PORT" 2>&1 | grep -q succeeded; then
  echo "ERROR: PostgreSQL nicht erreichbar"
  exit 1
fi
log "PostgreSQL erreichbar ✓"

### =========================
### 0) Create PostgreSQL Database (idempotent)
### =========================

log "Erstelle PostgreSQL-Datenbank für Matrix/Synapse (idempotent)"
create_database_idempotent "$PG_DB" "$PG_USER" "$PG_PASS" "$PG_HOST" "$PG_PORT"

### =========================
### 1) Template
### =========================

log "Pruefe Ubuntu Template"
if ! pveam list "$TPL_STORAGE" | awk '{print $1}' | grep -qx "${TPL_STORAGE}:vztmpl/${TPL_NAME}"; then
  pveam update >/dev/null
  pveam download "$TPL_STORAGE" "$TPL_NAME"
fi

### =========================
### 2) Create Container
### =========================

if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits"
else
  log "Erstelle LXC CT ${CTID}"
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

pct_exec "printf 'search ${SEARCHDOMAIN}\\nnameserver ${DNS}\\n' > /etc/resolv.conf"

### =========================
### 3) Snapshot pre-install
### =========================

log "Erstelle Snapshot 'pre-install'"
if ! pct listsnapshot "$CTID" 2>/dev/null | grep -q "pre-install"; then
  pct snapshot "$CTID" "pre-install"
fi

### =========================
### 4) Base Packages
### =========================

log "Installiere Basis-Pakete"
pct_exec "export DEBIAN_FRONTEND=noninteractive;
apt-get update -y;
apt-get install -y ca-certificates curl wget gnupg lsb-release locales \
  postgresql-client python3 python3-pip python3-venv nginx;
"

### =========================
### 5) Locale
### =========================

log "Konfiguriere Locale"
pct_exec "
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
"

### =========================
### 6) Install Synapse
### =========================

log "Installiere Matrix Synapse"
pct_exec "
# Matrix APT Repository
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ \$(lsb_release -cs) main' > /etc/apt/sources.list.d/matrix-org.list

apt-get update -y
apt-get install -y matrix-synapse-py3
"

### =========================
### 7) Configure Synapse
### =========================

log "Konfiguriere Synapse"
pct_exec "
# Erstelle Backup wenn Config bereits modifiziert wurde
if [[ -f /etc/matrix-synapse/homeserver.yaml ]] && [[ ! -f /etc/matrix-synapse/homeserver.yaml.orig ]]; then
  BACKUP_FILE=\"/etc/matrix-synapse/homeserver.yaml.backup.\$(date +%Y%m%d_%H%M%S)\"
  echo \"Config existiert bereits - erstelle Backup: \$BACKUP_FILE\"
  cp /etc/matrix-synapse/homeserver.yaml \"\$BACKUP_FILE\"
fi

# Backup original config wenn noch nicht vorhanden
if [[ -f /etc/matrix-synapse/homeserver.yaml ]] && [[ ! -f /etc/matrix-synapse/homeserver.yaml.orig ]]; then
  cp /etc/matrix-synapse/homeserver.yaml /etc/matrix-synapse/homeserver.yaml.orig
fi

# Create new config
cat > /etc/matrix-synapse/homeserver.yaml <<'EOFSYNAPSE'
server_name: \"${MATRIX_SERVER_NAME}\"
pid_file: /var/run/matrix-synapse.pid
public_baseurl: https://${MATRIX_DOMAIN}

listeners:
  - port: ${SYNAPSE_PORT}
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: ${PG_USER}
    password: ${PG_PASS}
    database: ${PG_DB}
    host: ${PG_HOST}
    port: ${PG_PORT}
    cp_min: 5
    cp_max: 10

log_config: \"/etc/matrix-synapse/log.yaml\"

media_store_path: /var/lib/matrix-synapse/media
uploads_path: /var/lib/matrix-synapse/uploads

max_upload_size: 50M
max_image_pixels: 32M

enable_registration: false
registration_shared_secret: \"${MATRIX_REGISTRATION_SECRET}\"

enable_metrics: false
report_stats: false

suppress_key_server_warning: true

trusted_key_servers:
  - server_name: \"matrix.org\"
EOFSYNAPSE

chown matrix-synapse:matrix-synapse /etc/matrix-synapse/homeserver.yaml
chmod 640 /etc/matrix-synapse/homeserver.yaml
"

### =========================
### 8) Start Synapse
### =========================

log "Starte Synapse"
pct_exec "systemctl restart matrix-synapse"
sleep 5

### =========================
### 9) Install Element Web
### =========================

log "Installiere Element Web"
pct_exec "
mkdir -p /var/www/element
cd /tmp
wget https://github.com/element-hq/element-web/releases/download/${ELEMENT_VERSION}/element-${ELEMENT_VERSION}.tar.gz
tar -xzf element-${ELEMENT_VERSION}.tar.gz
cp -r element-${ELEMENT_VERSION}/* /var/www/element/
rm -rf element-${ELEMENT_VERSION}*

# Element Config
cat > /var/www/element/config.json <<'EOFELEMENT'
{
  \"default_server_config\": {
    \"m.homeserver\": {
      \"base_url\": \"http://${IP_CIDR%/*}:${SYNAPSE_PORT}\",
      \"server_name\": \"${MATRIX_SERVER_NAME}\"
    }
  },
  \"brand\": \"RALF Matrix\",
  \"disable_guests\": true,
  \"disable_3pid_login\": true,
  \"default_theme\": \"dark\"
}
EOFELEMENT
"

### =========================
### 10) Configure Nginx
### =========================

log "Konfiguriere Nginx für Element"
pct_exec "
cat > /etc/nginx/sites-available/element <<'EOFNGINX'
server {
    listen 80;
    server_name ${MATRIX_DOMAIN};

    root /var/www/element;
    index index.html;

    location / {
        try_files \\\$uri \\\$uri/ =404;
    }

    location /_matrix {
        proxy_pass http://127.0.0.1:${SYNAPSE_PORT};
        proxy_set_header X-Forwarded-For \\\$remote_addr;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_set_header Host \\\$host;
    }

    location /_synapse/client {
        proxy_pass http://127.0.0.1:${SYNAPSE_PORT};
        proxy_set_header X-Forwarded-For \\\$remote_addr;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_set_header Host \\\$host;
    }
}
EOFNGINX

ln -sf /etc/nginx/sites-available/element /etc/nginx/sites-enabled/element
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
"

### =========================
### 11) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if ! pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 12) Final Checks
### =========================

log "Final Checks"
pct_exec "systemctl is-active matrix-synapse; systemctl is-active nginx"

log "FERTIG"
echo "Matrix/Synapse sollte jetzt erreichbar sein:"
echo "  Synapse API: http://${IP_CIDR%/*}:${SYNAPSE_PORT}"
echo "  Element Web: http://${IP_CIDR%/*}"
echo ""
echo "User erstellen:"
echo "  pct exec ${CTID} -- register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml http://localhost:${SYNAPSE_PORT}"
