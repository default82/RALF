#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-2012}"                        # CT-ID im 20er Bereich (Databases/Devtools)
CT_HOSTNAME="${CT_HOSTNAME:-svc-gitea}"     # -fz implied (Functional Zone)
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 20)
IP_CIDR="${IP_CIDR:-10.10.20.12/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen
MEMORY="${MEMORY:-2048}"     # MB
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-32}"

# Ubuntu Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# Gitea
GITEA_VERSION="${GITEA_VERSION:-1.22.6}"
GITEA_BINARY_URL="${GITEA_BINARY_URL:-https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64}"

# Gitea Config
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-2222}"
GITEA_DOMAIN="${GITEA_DOMAIN:-gitea.homelab.lan}"

# Gitea Admin Accounts (werden automatisch angelegt)
GITEA_ADMIN1_USER="${GITEA_ADMIN1_USER:-kolja}"
GITEA_ADMIN1_EMAIL="${GITEA_ADMIN1_EMAIL:-kolja@homelab.lan}"
GITEA_ADMIN1_PASS="${GITEA_ADMIN1_PASS:-CHANGE_ME_NOW}"

GITEA_ADMIN2_USER="${GITEA_ADMIN2_USER:-ralf}"
GITEA_ADMIN2_EMAIL="${GITEA_ADMIN2_EMAIL:-ralf@homelab.lan}"
GITEA_ADMIN2_PASS="${GITEA_ADMIN2_PASS:-CHANGE_ME_NOW}"

# PostgreSQL Connection (MUSS bereits existieren!)
PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-gitea}"
PG_USER="${PG_USER:-gitea}"
PG_PASS="${PG_PASS:-CHANGE_ME_NOW}"

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
need_cmd pvesm
need_cmd curl

if [[ "$PG_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: PG_PASS ist noch CHANGE_ME_NOW."
  echo "Setze PostgreSQL-Passwort fuer Gitea-DB:"
  echo "  export PG_PASS='gitea-db-passwort'"
  exit 1
fi

if [[ "$GITEA_ADMIN1_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: GITEA_ADMIN1_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Admin-Passwort fuer ${GITEA_ADMIN1_USER}:"
  echo "  export GITEA_ADMIN1_PASS='sicheres-passwort'"
  exit 1
fi

if [[ "$GITEA_ADMIN2_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: GITEA_ADMIN2_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Admin-Passwort fuer ${GITEA_ADMIN2_USER}:"
  echo "  export GITEA_ADMIN2_PASS='sicheres-passwort'"
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
pct_exec "printf 'search ${SEARCHDOMAIN}\nnameserver ${DNS}\n' > /etc/resolv.conf"

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
  ca-certificates curl git openssh-server postgresql-client locales;
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
### 7) Create git user
### =========================

log "Erstelle git-User"
pct_exec "
if ! id -u git >/dev/null 2>&1; then
  useradd -m -s /bin/bash git
fi
"

### =========================
### 8) Install Gitea binary
### =========================

log "Installiere Gitea ${GITEA_VERSION} -> /usr/local/bin/gitea"
pct_exec "set -euo pipefail;
if [[ -f /usr/local/bin/gitea ]]; then
  CURRENT_VERSION=\$(/usr/local/bin/gitea --version | awk '{print \$3}' || echo 'unknown')
  if [[ \"\$CURRENT_VERSION\" == \"${GITEA_VERSION}\" ]]; then
    echo 'Gitea ${GITEA_VERSION} bereits installiert'
    exit 0
  fi
fi

echo 'Downloading: ${GITEA_BINARY_URL}'
curl -fsSL -o /tmp/gitea '${GITEA_BINARY_URL}'
chmod +x /tmp/gitea
mv /tmp/gitea /usr/local/bin/gitea

/usr/local/bin/gitea --version
"

### =========================
### 9) Configure Gitea directories
### =========================

log "Erstelle Gitea-Verzeichnisse"
pct_exec "
mkdir -p /var/lib/gitea/{custom,data,log}
mkdir -p /etc/gitea
chown -R git:git /var/lib/gitea
chown root:git /etc/gitea
chmod 770 /etc/gitea
"

### =========================
### 10) Create Gitea config (app.ini)
### =========================

log "Erstelle Gitea config (/etc/gitea/app.ini)"
pct_exec "set -euo pipefail;

cat >/etc/gitea/app.ini <<EOF
APP_NAME = RALF Gitea
RUN_USER = git
RUN_MODE = prod

[server]
DOMAIN           = ${GITEA_DOMAIN}
HTTP_PORT        = ${GITEA_HTTP_PORT}
ROOT_URL         = http://${GITEA_DOMAIN}:${GITEA_HTTP_PORT}/
DISABLE_SSH      = false
SSH_PORT         = ${GITEA_SSH_PORT}
SSH_LISTEN_PORT  = ${GITEA_SSH_PORT}
START_SSH_SERVER = true
LFS_START_SERVER = true

[database]
DB_TYPE  = postgres
HOST     = ${PG_HOST}:${PG_PORT}
NAME     = ${PG_DB}
USER     = ${PG_USER}
PASSWD   = ${PG_PASS}
SSL_MODE = disable
LOG_SQL  = false

[repository]
ROOT = /var/lib/gitea/data/gitea-repositories

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW  = false

[security]
INSTALL_LOCK = true
SECRET_KEY   = \$(openssl rand -base64 32)
INTERNAL_TOKEN = \$(openssl rand -base64 64)

[log]
MODE      = console,file
LEVEL     = Info
ROOT_PATH = /var/lib/gitea/log

[session]
PROVIDER = file
EOF

chown root:git /etc/gitea/app.ini
chmod 640 /etc/gitea/app.ini
"

### =========================
### 11) Create systemd service
### =========================

log "Erstelle Gitea systemd service"
pct_exec "
cat >/etc/systemd/system/gitea.service <<'EOF'
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target postgresql.service
Wants=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=on-failure
RestartSec=3
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gitea
systemctl start gitea
"

### =========================
### 12) Create Admin Users + Organization
### =========================

log "Warte auf Gitea Startup..."
sleep 5

log "Erstelle Admin-User: ${GITEA_ADMIN1_USER}"
pct_exec "set -euo pipefail;
export USER=git
export HOME=/home/git
export GITEA_WORK_DIR=/var/lib/gitea

# Prüfe ob User bereits existiert
if sudo -u git /usr/local/bin/gitea admin user list --config /etc/gitea/app.ini 2>/dev/null | grep -qi '${GITEA_ADMIN1_USER}'; then
  echo 'User ${GITEA_ADMIN1_USER} existiert bereits'
else
  sudo -u git /usr/local/bin/gitea admin user create \
    --admin \
    --username '${GITEA_ADMIN1_USER}' \
    --email '${GITEA_ADMIN1_EMAIL}' \
    --password '${GITEA_ADMIN1_PASS}' \
    --config /etc/gitea/app.ini
  echo 'Admin-User ${GITEA_ADMIN1_USER} erstellt'
fi
"

log "Erstelle Admin-User: ${GITEA_ADMIN2_USER}"
pct_exec "set -euo pipefail;
export USER=git
export HOME=/home/git
export GITEA_WORK_DIR=/var/lib/gitea

# Prüfe ob User bereits existiert
if sudo -u git /usr/local/bin/gitea admin user list --config /etc/gitea/app.ini 2>/dev/null | grep -qi '${GITEA_ADMIN2_USER}'; then
  echo 'User ${GITEA_ADMIN2_USER} existiert bereits'
else
  sudo -u git /usr/local/bin/gitea admin user create \
    --admin \
    --username '${GITEA_ADMIN2_USER}' \
    --email '${GITEA_ADMIN2_EMAIL}' \
    --password '${GITEA_ADMIN2_PASS}' \
    --config /etc/gitea/app.ini
  echo 'Admin-User ${GITEA_ADMIN2_USER} erstellt'
fi
"

log "Erstelle Organisation RALF-Homelab"
pct_exec "set -euo pipefail;
export USER=git
export HOME=/home/git
export GITEA_WORK_DIR=/var/lib/gitea

# Prüfe ob Organisation bereits existiert via API
if curl -s http://localhost:${GITEA_HTTP_PORT}/api/v1/orgs/RALF-Homelab 2>&1 | grep -q '\"username\":\"RALF-Homelab\"'; then
  echo 'Organisation RALF-Homelab existiert bereits'
else
  # Erstelle Organisation via API (als Admin-User)
  curl -X POST http://localhost:${GITEA_HTTP_PORT}/api/v1/orgs \
    -u '${GITEA_ADMIN1_USER}:${GITEA_ADMIN1_PASS}' \
    -H 'Content-Type: application/json' \
    -d '{
      \"username\": \"RALF-Homelab\",
      \"full_name\": \"RALF Homelab Infrastructure\",
      \"description\": \"Self-orchestrating homelab infrastructure platform\",
      \"visibility\": \"private\"
    }' >/dev/null 2>&1
  echo 'Organisation RALF-Homelab erstellt'
fi
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
pct_exec "systemctl is-active gitea; ss -lntp | grep -E ':(${GITEA_HTTP_PORT}|${GITEA_SSH_PORT})\\b' || true"

log "FERTIG"
echo "Gitea ${GITEA_VERSION} sollte jetzt erreichbar sein:"
echo "  HTTP: http://${IP_CIDR%/*}:${GITEA_HTTP_PORT}"
echo "  SSH:  ssh://git@${IP_CIDR%/*}:${GITEA_SSH_PORT}"
echo ""
echo "Naechste Schritte:"
echo "  1. Web-UI aufrufen und Initial Setup durchfuehren"
echo "  2. Admin-Accounts anlegen (kolja, ralf)"
echo "  3. SSH-Keys hinterlegen"
echo "  4. Repository von GitHub migrieren"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
