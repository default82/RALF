#!/usr/bin/env bash
set -euo pipefail

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

### =========================
### CONFIG
### =========================

# Proxmox
CTID="${CTID:-2013}"
CT_HOSTNAME="${CT_HOSTNAME:-svc-minio}"
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 20 - Databases/Storage)
IP_CIDR="${IP_CIDR:-10.10.20.13/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen (optimiert für 500GB/16GB node)
MEMORY="${MEMORY:-512}"      # MB - MinIO ist sehr effizient
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-8}"      # Initial storage, kann erweitert werden

# Ubuntu Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# MinIO
MINIO_VERSION="${MINIO_VERSION:-RELEASE.2024-02-17T01-15-57Z}"
MINIO_BINARY_URL="${MINIO_BINARY_URL:-https://dl.min.io/server/minio/release/linux-amd64/minio}"
MINIO_CLIENT_URL="${MINIO_CLIENT_URL:-https://dl.min.io/client/mc/release/linux-amd64/mc}"

# MinIO Config
MINIO_HTTP_PORT="${MINIO_HTTP_PORT:-9000}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/var/lib/minio/data}"

# MinIO Credentials (aus credentials.env)
MINIO_ROOT_USER="${MINIO_ROOT_USER:-${MINIO_ROOT_USER:-CHANGE_ME_NOW}}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-${MINIO_ROOT_PASSWORD:-CHANGE_ME_NOW}}"

### =========================
### Preconditions
### =========================

need_cmd pct
need_cmd pveam
need_cmd curl

if [[ "$MINIO_ROOT_PASSWORD" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: MINIO_ROOT_PASSWORD ist noch CHANGE_ME_NOW."
  echo "Setze MinIO Root-Passwort:"
  echo "  export MINIO_ROOT_PASSWORD='sicheres-passwort'"
  exit 1
fi

### =========================
### 1) Ensure template exists
### =========================

log "Prüfe Ubuntu Template: ${TPL_STORAGE}:vztmpl/${TPL_NAME}"
if ! pveam list "$TPL_STORAGE" | awk '{print $1}' | grep -qx "${TPL_STORAGE}:vztmpl/${TPL_NAME}"; then
  log "Template nicht gefunden -> lade herunter"
  pveam update >/dev/null
  pveam download "$TPL_STORAGE" "$TPL_NAME"
fi

### =========================
### 2) Create container
### =========================

if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits -> überspringe create"
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
sleep 5

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
### 5) Base packages
### =========================

log "Installiere Basis-Tools"
pct_exec "export DEBIAN_FRONTEND=noninteractive;
apt-get update -y;
apt-get install -y --no-install-recommends ca-certificates curl wget;"

### =========================
### 6) Install MinIO Server
### =========================

log "Installiere MinIO Server -> /usr/local/bin/minio"
pct_exec "
curl -fsSL -o /usr/local/bin/minio '${MINIO_BINARY_URL}'
chmod +x /usr/local/bin/minio
/usr/local/bin/minio --version
"

### =========================
### 7) Install MinIO Client (mc)
### =========================

log "Installiere MinIO Client (mc) -> /usr/local/bin/mc"
pct_exec "
curl -fsSL -o /usr/local/bin/mc '${MINIO_CLIENT_URL}'
chmod +x /usr/local/bin/mc
/usr/local/bin/mc --version
"

### =========================
### 8) Configure MinIO directories
### =========================

log "Erstelle MinIO-Verzeichnisse"
pct_exec "
mkdir -p ${MINIO_DATA_DIR}
mkdir -p /etc/minio
chown -R root:root ${MINIO_DATA_DIR}
"

### =========================
### 9) Create MinIO systemd service
### =========================

log "Erstelle MinIO systemd service"
pct_exec "
cat >/etc/systemd/system/minio.service <<'EOF'
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs/minio/linux/index.html
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/usr/local
ExecStart=/usr/local/bin/minio server ${MINIO_DATA_DIR} --console-address :${MINIO_CONSOLE_PORT}
Restart=on-failure
RestartSec=5
Environment=\"MINIO_ROOT_USER=${MINIO_ROOT_USER}\"
Environment=\"MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}\"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minio
systemctl start minio
"

### =========================
### 10) Wait for MinIO API
### =========================

log "Warte auf MinIO API..."
sleep 5

for i in {1..30}; do
  if pct_exec "curl -sf http://localhost:${MINIO_HTTP_PORT}/minio/health/live" >/dev/null 2>&1; then
    log "MinIO API bereit"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: MinIO API nicht bereit nach 30 Sekunden"
    exit 1
  fi
  sleep 1
done

### =========================
### 11) Create default buckets
### =========================

log "Konfiguriere MinIO Client und erstelle Buckets"
pct_exec "
# Configure mc alias
/usr/local/bin/mc alias set local http://localhost:${MINIO_HTTP_PORT} ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}

# Create buckets for state backends
/usr/local/bin/mc mb local/terraform-state --ignore-existing
/usr/local/bin/mc mb local/terragrunt-state --ignore-existing
/usr/local/bin/mc mb local/opentofu-state --ignore-existing
/usr/local/bin/mc mb local/ansible-facts --ignore-existing

# List buckets
/usr/local/bin/mc ls local/
"

### =========================
### 12) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  log "Snapshot post-install existiert bereits"
else
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 13) Final checks
### =========================

log "Checks: Service status + Port listening"
pct_exec "systemctl is-active minio; ss -lntp | grep -E ':(${MINIO_HTTP_PORT}|${MINIO_CONSOLE_PORT})' || true"

log "FERTIG"
echo "MinIO sollte jetzt erreichbar sein:"
echo "  API: http://${IP_CIDR%/*}:${MINIO_HTTP_PORT}"
echo "  Console: http://${IP_CIDR%/*}:${MINIO_CONSOLE_PORT}"
echo "  User: ${MINIO_ROOT_USER}"
echo ""
echo "Buckets erstellt:"
echo "  - terraform-state"
echo "  - terragrunt-state"
echo "  - opentofu-state"
echo "  - ansible-facts"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
