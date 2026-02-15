#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || {
  log() { echo -e "\n==> $*"; }
  need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }; }
  pct_exec() { pct exec "$1" -- bash -lc "${@:2}"; }
}

### CONFIG ###
CTID="${CTID:-3010}"
CT_HOSTNAME="${CT_HOSTNAME:-sec-vaultwarden}"
BRIDGE="${BRIDGE:-vmbr0}"
IP_CIDR="${IP_CIDR:-10.10.30.10/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"
MEMORY="${MEMORY:-512}"      # MB - Rust Binary, sehr effizient (optimiert für 500GB/16GB node)
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-8}"
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
VAULTWARDEN_PORT="${VAULTWARDEN_PORT:-8080}"
VAULTWARDEN_VERSION="${VAULTWARDEN_VERSION:-1.35.3}"

# PostgreSQL
PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-vaultwarden}"
PG_USER="${PG_USER:-vaultwarden}"
PG_PASS="${PG_PASS:-${VAULTWARDEN_PG_PASS:-CHANGE_ME}}"

need_cmd pct

### Template ###
log "Prüfe Ubuntu Template"
if ! pveam list "$TPL_STORAGE" | awk '{print $1}' | grep -qx "${TPL_STORAGE}:vztmpl/${TPL_NAME}"; then
  pveam update >/dev/null
  pveam download "$TPL_STORAGE" "$TPL_NAME"
fi

### Create Container ###
if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits"
else
  log "Erstelle CT ${CTID} (${CT_HOSTNAME})"
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

pct start "$CTID" 2>/dev/null || true
sleep 5

log "Setze resolv.conf"
pct_exec "$CTID" "printf 'search ${SEARCHDOMAIN}\nnameserver ${DNS}\n' > /etc/resolv.conf"

log "Snapshot pre-install"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "pre-install"; then
  log "Snapshot existiert"
else
  pct snapshot "$CTID" "pre-install"
fi

### Install Dependencies ###
log "Installiere Dependencies"
pct_exec "$CTID" "
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl wget postgresql-client build-essential git libssl-dev pkg-config
"

### Create Database ###
log "Erstelle PostgreSQL-Datenbank für Vaultwarden"
if pct exec 2010 -- bash -lc "sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${PG_DB}'\"" 2>/dev/null | grep -q 1; then
  log "Datenbank existiert bereits"
else
  log "Erstelle DB + User"
  pct exec 2010 -- bash -lc "sudo -u postgres psql <<EOF
CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASS}';
CREATE DATABASE ${PG_DB} OWNER ${PG_USER};
GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USER};
EOF"
fi

### Install Rust Toolchain ###
log "Installiere Rust Toolchain (für Build from Source)"
pct_exec "$CTID" "
export DEBIAN_FRONTEND=noninteractive
apt-get install -y build-essential git libssl-dev pkg-config
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source \$HOME/.cargo/env
"

### Build Vaultwarden from Source ###
log "Clone und Build Vaultwarden v${VAULTWARDEN_VERSION} from Source"
pct_exec "$CTID" "
source \$HOME/.cargo/env
cd /tmp
git clone https://github.com/dani-garcia/vaultwarden.git
cd vaultwarden
git checkout ${VAULTWARDEN_VERSION}
cargo build --features sqlite,postgresql --release
mkdir -p /opt/vaultwarden
cp target/release/vaultwarden /opt/vaultwarden/
chmod +x /opt/vaultwarden/vaultwarden
mkdir -p /var/lib/vaultwarden/data
"

### Download Web-Vault ###
log "Download Vaultwarden Web-Vault"
pct_exec "$CTID" "
cd /tmp
VAULT_VERSION=\$(curl -s https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest | grep tag_name | cut -d '\"' -f 4)
wget https://github.com/dani-garcia/bw_web_builds/releases/download/\${VAULT_VERSION}/bw_web_\${VAULT_VERSION}.tar.gz
tar -xzf bw_web_\${VAULT_VERSION}.tar.gz -C /opt/vaultwarden/
"

### Config ###
log "Erstelle Vaultwarden Config"
pct_exec "$CTID" "
cat > /opt/vaultwarden/.env <<EOF
DATABASE_URL=postgresql://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}
ROCKET_ADDRESS=0.0.0.0
ROCKET_PORT=${VAULTWARDEN_PORT}
WEB_VAULT_ENABLED=true
SIGNUPS_ALLOWED=true
ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN:-\$(openssl rand -base64 48)}
DOMAIN=http://${IP_CIDR%/*}:${VAULTWARDEN_PORT}
DATA_FOLDER=/var/lib/vaultwarden/data
EOF
"

### Systemd Service ###
log "Erstelle systemd service"
pct_exec "$CTID" "
cat > /etc/systemd/system/vaultwarden.service <<'EOFSVC'
[Unit]
Description=Vaultwarden Password Manager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vaultwarden
EnvironmentFile=/opt/vaultwarden/.env
ExecStart=/opt/vaultwarden/vaultwarden
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable --now vaultwarden
"

log "Warte auf Startup (20s)"
sleep 20

log "Final Checks"
pct_exec "$CTID" "systemctl is-active vaultwarden && ss -lntp | grep ':${VAULTWARDEN_PORT}' || true"

log "FERTIG ✅"
echo ""
echo "Vaultwarden: http://${IP_CIDR%/*}:${VAULTWARDEN_PORT}"
echo "Admin: http://${IP_CIDR%/*}:${VAULTWARDEN_PORT}/admin"
echo "Admin Token: siehe /opt/vaultwarden/.env"
