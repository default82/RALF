#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-10015}"                       # CT-ID im 100er Bereich (Automation)
HOSTNAME="${HOSTNAME:-semaphore-pg}"         # -pg = Playground
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (dein Schema 10.10.0.0/16, Bereich 100)
IP_CIDR="${IP_CIDR:-10.10.100.15/16}"
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

# Semaphore (Binary Install)
SEMAPHORE_VERSION="${SEMAPHORE_VERSION:-2.16.51}"  # bei Bedarf ändern
# Die meisten Releases folgen diesem Muster; wenn dein Release anders heißt:
# SEMAPHORE_TARBALL_URL überschreiben.
SEMAPHORE_TARBALL_URL="${SEMAPHORE_TARBALL_URL:-https://github.com/semaphoreui/semaphore/releases/download/v${SEMAPHORE_VERSION}/semaphore_${SEMAPHORE_VERSION}_linux_amd64.tar.gz}"

# Semaphore initial (SQLite)
SEMAPHORE_USER="${SEMAPHORE_USER:-admin}"
SEMAPHORE_EMAIL="${SEMAPHORE_EMAIL:-admin@otta.zone}"
SEMAPHORE_NAME="${SEMAPHORE_NAME:-RALF Admin}"
# Passwort NICHT hart im Repo lassen. Für einmaligen Bootstrap: env var setzen.
SEMAPHORE_PASS="${SEMAPHORE_PASS:-CHANGE_ME_NOW}"

SEMAPHORE_BIND_ADDR="${SEMAPHORE_BIND_ADDR:-0.0.0.0}"
SEMAPHORE_PORT="${SEMAPHORE_PORT:-3000}"

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

if [[ "$SEMAPHORE_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: SEMAPHORE_PASS ist noch CHANGE_ME_NOW."
  echo "Setze es einmalig vor dem Start, z.B.:"
  echo "  export SEMAPHORE_PASS='ein-lang-es-passwort'"
  exit 1
fi

### =========================
### 1) Ensure template exists
### =========================

log "Prüfe Ubuntu Template: ${TPL_STORAGE}:vztmpl/${TPL_NAME}"
if ! pveam list "$TPL_STORAGE" | awk '{print $1}' | grep -qx "${TPL_STORAGE}:vztmpl/${TPL_NAME}"; then
  log "Template nicht gefunden -> lade herunter (pveam download)"
  pveam update >/dev/null
  # Falls TPL_NAME anders heißt, passe oben an.
  pveam download "$TPL_STORAGE" "$TPL_NAME"
fi

### =========================
### 2) Create container (if not exists)
### =========================

if pct status "$CTID" >/dev/null 2>&1; then
  log "CT ${CTID} existiert bereits -> überspringe create"
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

log "Warte kurz auf Boot..."
sleep 3

### =========================
### 3) Set DNS/search domain in container
### =========================

log "Setze resolv.conf (DNS=${DNS}, search=${SEARCHDOMAIN})"
pct_exec "printf '# --- RALF ---\nsearch ${SEARCHDOMAIN}\nnameserver ${DNS}\n# --- RALF ---\n' > /etc/resolv.conf"

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
### 5) Base packages + toolchain
### =========================

log "Installiere Basis-Tools im Container"
pct_exec "export DEBIAN_FRONTEND=noninteractive;
apt-get update -y;
apt-get install -y --no-install-recommends ca-certificates curl jq git unzip gnupg lsb-release sqlite3 openssh-client;
"

### =========================
### 6) Install Semaphore binary
### =========================

log "Installiere Semaphore v${SEMAPHORE_VERSION} (Binary) -> /usr/local/bin/semaphore"
pct_exec "set -euo pipefail;
mkdir -p /opt/semaphore /etc/semaphore /var/lib/semaphore;
cd /tmp;

echo 'Downloading: ${SEMAPHORE_TARBALL_URL}';
curl -fsSL -o semaphore.tar.gz '${SEMAPHORE_TARBALL_URL}';
tar -xzf semaphore.tar.gz;

# Manche Releases packen 'semaphore' direkt, andere in Unterordnern.
if [[ -f ./semaphore ]]; then
  install -m 0755 ./semaphore /usr/local/bin/semaphore
else
  # Suche nach binary
  SEM_BIN=\$(find . -maxdepth 3 -type f -name semaphore | head -n 1 || true)
  if [[ -z \"\$SEM_BIN\" ]]; then
    echo 'ERROR: semaphore binary not found in tarball.' >&2
    exit 1
  fi
  install -m 0755 \"\$SEM_BIN\" /usr/local/bin/semaphore
fi

/usr/local/bin/semaphore version || true
"

### =========================
### 7) Configure Semaphore (SQLite)
### =========================

log "Erzeuge Semaphore config (SQLite) + systemd service"
pct_exec "set -euo pipefail;

cat >/etc/semaphore/config.json <<'EOF'
{
  \"dialect\": \"sqlite\",
  \"database\": \"/var/lib/semaphore/semaphore.sqlite\",
  \"host\": \"\",
  \"port\": \"\",
  \"user\": \"\",
  \"pass\": \"\",
  \"name\": \"\",
  \"sslmode\": \"disable\",
  \"web_host\": \"${SEMAPHORE_BIND_ADDR}\",
  \"web_port\": \"${SEMAPHORE_PORT}\",
  \"email_alert\": false,
  \"telegram_alert\": false,
  \"slack_alert\": false
}
EOF

cat >/etc/systemd/system/semaphore.service <<'EOF'
[Unit]
Description=Semaphore UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/semaphore
Environment=SEMAPHORE_CONFIG=/etc/semaphore/config.json
ExecStart=/usr/local/bin/semaphore server
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now semaphore
"

### =========================
### 8) Create admin user (first-run)
### =========================

log "Lege Admin-User an (wenn noch nicht vorhanden)"
pct_exec "set -euo pipefail;

# Prüfe ob schon User existiert
if /usr/local/bin/semaphore user list --config /etc/semaphore/config.json 2>/dev/null | grep -qi '${SEMAPHORE_USER}'; then
  echo 'Admin user exists -> skip'
else
  /usr/local/bin/semaphore user add \
    --admin \
    --login '${SEMAPHORE_USER}' \
    --name '${SEMAPHORE_NAME}' \
    --email '${SEMAPHORE_EMAIL}' \
    --password '${SEMAPHORE_PASS}' \
    --config /etc/semaphore/config.json
fi
"

### =========================
### 9) Final checks
### =========================

log "Checks: Service status + Port listening"
pct_exec "systemctl is-active semaphore; ss -lntp | grep -E ':(3000|${SEMAPHORE_PORT})\\b' || true"

log "FERTIG ✅"
echo "Semaphore sollte jetzt erreichbar sein:"
echo "  http://${IP_CIDR%/*}:${SEMAPHORE_PORT}"
echo ""
echo "Login:"
echo "  User: ${SEMAPHORE_USER}"
echo "  Pass: (wie in SEMAPHORE_PASS gesetzt)"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
