#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-2012}"                        # CT-ID im 20er Bereich (Datenbanken/DevTools)
HOSTNAME="${HOSTNAME:-svc-gitea}"            # Functional Zone
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 20)
IP_CIDR="${IP_CIDR:-10.10.20.12/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen
MEMORY="${MEMORY:-2048}"     # MB
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-16}"

# Ubuntu Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# Gitea
GITEA_VERSION="${GITEA_VERSION:-1.22.6}"
GITEA_BINARY_URL="${GITEA_BINARY_URL:-https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-2222}"

# PostgreSQL Verbindung (Secrets via env vars setzen!)
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

if [[ "$PG_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: PG_PASS ist noch CHANGE_ME_NOW."
  echo "Setze es vor dem Start, z.B.:"
  echo "  export PG_PASS='sicheres-passwort'"
  exit 1
fi

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
  log "Erstelle LXC CT ${CTID} (${HOSTNAME}) mit IP ${IP_CIDR}"
  pct create "$CTID" "${TPL_STORAGE}:vztmpl/${TPL_NAME}" \
    --hostname "$HOSTNAME" \
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
if pct listsnapshot "$CTID" 2>/dev/null | awk '{print $1}' | grep -qx "pre-install"; then
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
  ca-certificates curl git openssh-server;
"

### =========================
### 6) Create gitea system user
### =========================

log "Erstelle Gitea System-User"
pct_exec "set -euo pipefail;
if id gitea &>/dev/null; then
  echo 'User gitea existiert bereits'
else
  adduser --system --shell /bin/bash --gecos 'Gitea' \
    --group --disabled-password --home /home/gitea gitea
fi
"

### =========================
### 7) Install Gitea binary
### =========================

log "Installiere Gitea v${GITEA_VERSION}"
pct_exec "set -euo pipefail;
mkdir -p /var/lib/gitea/{custom,data,log} /etc/gitea;

curl -fsSL -o /usr/local/bin/gitea '${GITEA_BINARY_URL}';
chmod +x /usr/local/bin/gitea;

chown -R gitea:gitea /var/lib/gitea /etc/gitea;
chmod 750 /etc/gitea;

/usr/local/bin/gitea --version || true;
"

### =========================
### 8) Configure Gitea (app.ini)
### =========================

log "Erzeuge Gitea app.ini + systemd service"
pct_exec "set -euo pipefail;

cat > /etc/gitea/app.ini << 'APPINI'
APP_NAME = RALF Gitea
RUN_USER = gitea
RUN_MODE = prod
WORK_PATH = /var/lib/gitea

[server]
SSH_DOMAIN       = ${HOSTNAME}.${SEARCHDOMAIN}
DOMAIN           = ${HOSTNAME}.${SEARCHDOMAIN}
HTTP_PORT        = ${GITEA_HTTP_PORT}
ROOT_URL         = http://${HOSTNAME}.${SEARCHDOMAIN}:${GITEA_HTTP_PORT}/
SSH_PORT         = ${GITEA_SSH_PORT}
START_SSH_SERVER = true
LFS_START_SERVER = true

[database]
DB_TYPE  = postgres
HOST     = ${PG_HOST}:${PG_PORT}
NAME     = ${PG_DB}
USER     = ${PG_USER}
PASSWD   = ${PG_PASS}
SSL_MODE = disable

[repository]
ROOT = /var/lib/gitea/data/gitea-repositories

[log]
MODE      = console
LEVEL     = info
ROOT_PATH = /var/lib/gitea/log
APPINI

chown gitea:gitea /etc/gitea/app.ini;
chmod 640 /etc/gitea/app.ini;

cat > /etc/systemd/system/gitea.service << 'SVC'
[Unit]
Description=Gitea (Git with a cup of tea)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=gitea
Group=gitea
WorkingDirectory=/var/lib/gitea
Environment=GITEA_WORK_DIR=/var/lib/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload;
systemctl enable --now gitea;
"

### =========================
### 9) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if pct listsnapshot "$CTID" 2>/dev/null | awk '{print $1}' | grep -qx "post-install"; then
  log "Snapshot post-install existiert bereits"
else
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 10) Final checks
### =========================

log "Checks: Service status + Port listening"
pct_exec "systemctl is-active gitea; ss -lntp | grep -E ':(${GITEA_HTTP_PORT}|${GITEA_SSH_PORT})\\b' || true"

log "FERTIG"
echo "Gitea v${GITEA_VERSION} sollte jetzt erreichbar sein:"
echo "  HTTP: http://${IP_CIDR%/*}:${GITEA_HTTP_PORT}"
echo "  SSH:  ssh://git@${IP_CIDR%/*}:${GITEA_SSH_PORT}"
echo ""
echo "Ersteinrichtung ueber Web-UI (erster User = Admin)."
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
