#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG
### =========================

# Proxmox
CTID="${CTID:-4013}"
CT_HOSTNAME="${CT_HOSTNAME:-svc-exo}"
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk
IP_CIDR="${IP_CIDR:-10.10.40.13/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen (AI braucht mehr!)
MEMORY="${MEMORY:-8192}"  # 8GB für AI Inferenz
CORES="${CORES:-4}"
DISK_GB="${DISK_GB:-64}"

# Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# Exo
EXO_PORT="${EXO_PORT:-52415}"
EXO_REPO="${EXO_REPO:-https://github.com/exo-explore/exo}"

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
apt-get install -y ca-certificates curl wget git build-essential \
  python3 python3-pip python3-venv python3-dev \
  libssl-dev libffi-dev rustc cargo nodejs npm;
"

### =========================
### 5) Install uv (Python package manager)
### =========================

log "Installiere uv"
pct_exec "
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH=\"\$HOME/.cargo/bin:\$PATH\"
"

### =========================
### 6) Clone exo Repository
### =========================

log "Clone exo Repository"
pct_exec "
cd /opt
git clone ${EXO_REPO}
cd exo
"

### =========================
### 7) Build Dashboard
### =========================

log "Build exo Dashboard"
pct_exec "
cd /opt/exo/dashboard
npm install
npm run build
"

### =========================
### 8) Create exo Service
### =========================

log "Erstelle exo systemd service"
pct_exec "
cat > /etc/systemd/system/exo.service <<'EOFSVC'
[Unit]
Description=Exo Distributed AI Inference
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/exo
Environment=\"PATH=/root/.cargo/bin:/usr/local/bin:/usr/bin:/bin\"
ExecStart=/root/.cargo/bin/uv run exo
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable exo
systemctl start exo
"

### =========================
### 9) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if ! pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 10) Final Checks
### =========================

log "Final Checks"
sleep 10
pct_exec "systemctl is-active exo"

log "FERTIG"
echo "Exo sollte jetzt erreichbar sein:"
echo "  Dashboard: http://${IP_CIDR%/*}:${EXO_PORT}"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
