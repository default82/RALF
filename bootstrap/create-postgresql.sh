#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-2010}"                        # CT-ID im 20er Bereich (Datenbanken)
CT_HOSTNAME="${CT_HOSTNAME:-svc-postgres}"    # -fz implied (Functional Zone)
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 20)
IP_CIDR="${IP_CIDR:-10.10.20.10/16}"
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

# PostgreSQL
PG_VERSION="${PG_VERSION:-16}"

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
  ca-certificates curl gnupg lsb-release locales;
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
### 7) Install PostgreSQL
### =========================

log "Installiere PostgreSQL ${PG_VERSION}"
pct_exec "set -euo pipefail;
export DEBIAN_FRONTEND=noninteractive;

# PostgreSQL APT repository
install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc

echo \"deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt \$(lsb_release -cs)-pgdg main\" \
  > /etc/apt/sources.list.d/pgdg.list

apt-get update -y;
apt-get install -y --no-install-recommends postgresql-${PG_VERSION};
"

### =========================
### 8) Configure PostgreSQL
### =========================

log "Konfiguriere PostgreSQL (listen auf alle Interfaces, pg_hba)"
pct_exec "set -euo pipefail;

PG_CONF='/etc/postgresql/${PG_VERSION}/main/postgresql.conf'
PG_HBA='/etc/postgresql/${PG_VERSION}/main/pg_hba.conf'

# Listen auf alle Interfaces (intern erreichbar)
sed -i \"s/^#\\?listen_addresses.*/listen_addresses = '*'/\" \"\$PG_CONF\"

# Erlaube Zugriff aus dem Homelab-Netz (md5/scram-sha-256)
if ! grep -q '10.10.0.0/16' \"\$PG_HBA\"; then
  echo '# RALF Homelab' >> \"\$PG_HBA\"
  echo 'host    all    all    10.10.0.0/16    scram-sha-256' >> \"\$PG_HBA\"
fi

systemctl restart postgresql;
systemctl enable postgresql;
"

### =========================
### 9) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  log "Snapshot post-install existiert bereits"
else
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 10) Final checks
### =========================

log "Checks: Service status + Port listening"
pct_exec "systemctl is-active postgresql; ss -lntp | grep ':5432' || true"

log "FERTIG"
echo "PostgreSQL ${PG_VERSION} sollte jetzt erreichbar sein:"
echo "  Host: ${IP_CIDR%/*}"
echo "  Port: 5432"
echo ""
echo "Naechste Schritte:"
echo "  1. DB + User fuer Semaphore anlegen"
echo "  2. DB + User fuer Gitea anlegen"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
