#!/usr/bin/env bash
set -euo pipefail

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

### =========================
### CONFIG (anpassen)
### =========================

# Proxmox
CTID="${CTID:-4010}"                        # CT-ID im 40er Bereich (Web & Admin)
CT_HOSTNAME="${CT_HOSTNAME:-svc-mail}"      # -fz implied (Functional Zone)
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk (Schema 10.10.0.0/16, Bereich 40)
IP_CIDR="${IP_CIDR:-10.10.40.10/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"
SEARCHDOMAIN="${SEARCHDOMAIN:-homelab.lan}"

# Ressourcen (optimiert für 500GB/16GB node)
MEMORY="${MEMORY:-512}"      # MB - Maddy Go Binary, sehr effizient
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-8}"

# Ubuntu Template
TPL_STORAGE="${TPL_STORAGE:-local}"
TPL_NAME="${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

# Maddy
MADDY_VERSION="${MADDY_VERSION:-0.8.2}"
MADDY_BINARY_URL="${MADDY_BINARY_URL:-https://github.com/foxcpp/maddy/releases/download/v${MADDY_VERSION}/maddy-${MADDY_VERSION}-x86_64-linux-musl.tar.zst}"

# Maddy Config
MADDY_DOMAIN="${MADDY_DOMAIN:-homelab.lan}"
MADDY_HOSTNAME="${MADDY_HOSTNAME:-svc-mail.homelab.lan}"

# Mail-Accounts (werden erstellt)
MAIL_ACCOUNT1_USER="${MAIL_ACCOUNT1_USER:-kolja}"
MAIL_ACCOUNT1_EMAIL="${MAIL_ACCOUNT1_EMAIL:-kolja@homelab.lan}"
MAIL_ACCOUNT1_PASS="${MAIL_ACCOUNT1_PASS:-CHANGE_ME_NOW}"

MAIL_ACCOUNT2_USER="${MAIL_ACCOUNT2_USER:-ralf}"
MAIL_ACCOUNT2_EMAIL="${MAIL_ACCOUNT2_EMAIL:-ralf@homelab.lan}"
MAIL_ACCOUNT2_PASS="${MAIL_ACCOUNT2_PASS:-CHANGE_ME_NOW}"

### =========================
### Preconditions
### =========================

need_cmd pct
need_cmd pveam
need_cmd pvesm
need_cmd curl

if [[ "$MAIL_ACCOUNT1_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: MAIL_ACCOUNT1_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Mail-Passwort fuer ${MAIL_ACCOUNT1_EMAIL}:"
  echo "  export MAIL_ACCOUNT1_PASS='sicheres-passwort'"
  exit 1
fi

if [[ "$MAIL_ACCOUNT2_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: MAIL_ACCOUNT2_PASS ist noch CHANGE_ME_NOW."
  echo "Setze Mail-Passwort fuer ${MAIL_ACCOUNT2_EMAIL}:"
  echo "  export MAIL_ACCOUNT2_PASS='sicheres-passwort'"
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
  ca-certificates curl wget locales openssl zstd;
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
### 7) Create maddy user
### =========================

log "Erstelle maddy-User"
pct_exec "
if ! id -u maddy >/dev/null 2>&1; then
  useradd -m -r -s /bin/false -d /var/lib/maddy maddy
fi
"

### =========================
### 8) Install Maddy binary
### =========================

log "Installiere Maddy ${MADDY_VERSION} -> /usr/local/bin/maddy"
pct_exec "set -euo pipefail;
if [[ -f /usr/local/bin/maddy ]]; then
  CURRENT_VERSION=\$(/usr/local/bin/maddy --version 2>&1 | grep -oP 'maddy \K[0-9.]+' || echo 'unknown')
  if [[ \"\$CURRENT_VERSION\" == \"${MADDY_VERSION}\" ]]; then
    echo 'Maddy ${MADDY_VERSION} bereits installiert'
    exit 0
  fi
fi

echo 'Downloading: ${MADDY_BINARY_URL}'
cd /tmp
curl -fsSL -o maddy.tar.zst '${MADDY_BINARY_URL}'

echo 'Entpacke Maddy Binary...'
tar --use-compress-program=unzstd -xf maddy.tar.zst
chmod +x maddy-${MADDY_VERSION}-x86_64-linux-musl/maddy
mv maddy-${MADDY_VERSION}-x86_64-linux-musl/maddy /usr/local/bin/maddy
rm -rf maddy.tar.zst maddy-${MADDY_VERSION}-x86_64-linux-musl

/usr/local/bin/maddy --version
"

### =========================
### 9) Create Maddy directories
### =========================

log "Erstelle Maddy-Verzeichnisse"
pct_exec "
mkdir -p /etc/maddy
mkdir -p /var/lib/maddy
chown -R maddy:maddy /var/lib/maddy
chmod 700 /var/lib/maddy
"

### =========================
### 10) Generate self-signed TLS certificate
### =========================

log "Generiere self-signed TLS-Zertifikat"
pct_exec "set -euo pipefail;
if [[ -f /etc/maddy/tls_cert.pem ]]; then
  echo 'TLS-Zertifikat existiert bereits'
else
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
    -nodes -keyout /etc/maddy/tls_key.pem -out /etc/maddy/tls_cert.pem \
    -subj \"/CN=${MADDY_HOSTNAME}\" \
    -addext \"subjectAltName=DNS:${MADDY_HOSTNAME},DNS:${MADDY_DOMAIN}\"

  chmod 600 /etc/maddy/tls_key.pem
  chmod 644 /etc/maddy/tls_cert.pem
  chown maddy:maddy /etc/maddy/tls_*.pem
  echo 'TLS-Zertifikat generiert'
fi
"

### =========================
### 11) Create Maddy config
### =========================

log "Erstelle Maddy config (/etc/maddy/maddy.conf)"
pct_exec "set -euo pipefail;

cat >/etc/maddy/maddy.conf <<'EOFMADDY'
## Maddy Mail Server - Minimal Working Configuration
## Compatible with Maddy 0.8.x

\$(hostname) = ${MADDY_HOSTNAME}
\$(primary_domain) = ${MADDY_DOMAIN}

# TLS Configuration
tls file /etc/maddy/tls_cert.pem /etc/maddy/tls_key.pem

# State directory
state_dir /var/lib/maddy

# --- Authentication Database (SQLite) ---
auth.pass_table local_authdb {
    table sql_table {
        driver sqlite3
        dsn credentials.db
        table_name passwords
    }
}

# --- Local Mailboxes (SQLite) ---
storage.imapsql local_mailboxes {
    driver sqlite3
    dsn mail.db
}

# --- SMTP (Port 25) - Receive incoming mail ---
smtp tcp://0.0.0.0:25 {
    hostname \$(hostname)

    deliver_to &local_mailboxes
}

# --- Submission (Port 587) - Authenticated sending ---
submission tcp://0.0.0.0:587 {
    hostname \$(hostname)

    auth &local_authdb

    deliver_to &local_mailboxes
}

# --- IMAP (Port 993) - Mail retrieval ---
imap tls://0.0.0.0:993 {
    auth &local_authdb
    storage &local_mailboxes
}
EOFMADDY

chown maddy:maddy /etc/maddy/maddy.conf
chmod 644 /etc/maddy/maddy.conf
"

### =========================
### 12) Create systemd service
### =========================

log "Erstelle Maddy systemd service"
pct_exec "
cat >/etc/systemd/system/maddy.service <<'EOF'
[Unit]
Description=Maddy Mail Server
After=network.target
Wants=network.target

[Service]
Type=notify
User=maddy
Group=maddy
WorkingDirectory=/var/lib/maddy
ExecStart=/usr/local/bin/maddy run
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=on-failure
RestartSec=3

# Runtime directory
RuntimeDirectory=maddy
RuntimeDirectoryMode=0750

# Security (reduced restrictions for LXC compatibility)
NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=/var/lib/maddy /run/maddy

# Capabilities (needed for binding to ports < 1024)
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable maddy
"

### =========================
### 13) Initialize Maddy
### =========================

log "Initialisiere Maddy (erstelle Datenbanken)"
pct_exec "set -euo pipefail;
cd /var/lib/maddy

# Maddy initialisiert die DBs beim ersten Start
# Aber wir machen einen dry-run um Errors zu catchen
sudo -u maddy /usr/local/bin/maddy run --dry-run || echo 'Dry-run ausgefuehrt'
"

### =========================
### 14) Start Maddy
### =========================

log "Starte Maddy Service"
pct_exec "systemctl start maddy"

log "Warte auf Maddy Startup..."
sleep 3

### =========================
### 15) Create mail accounts
### =========================

log "Erstelle Mail-Account: ${MAIL_ACCOUNT1_EMAIL}"
pct_exec "set -euo pipefail;
cd /var/lib/maddy
echo '${MAIL_ACCOUNT1_PASS}' | sudo -u maddy /usr/local/bin/maddy creds create '${MAIL_ACCOUNT1_EMAIL}' || echo 'Account existiert bereits'
"

log "Erstelle Mail-Account: ${MAIL_ACCOUNT2_EMAIL}"
pct_exec "set -euo pipefail;
cd /var/lib/maddy
echo '${MAIL_ACCOUNT2_PASS}' | sudo -u maddy /usr/local/bin/maddy creds create '${MAIL_ACCOUNT2_EMAIL}' || echo 'Account existiert bereits'
"

### =========================
### 16) Snapshot post-install
### =========================

log "Erstelle Snapshot 'post-install'"
if pct listsnapshot "$CTID" 2>/dev/null | grep -q "post-install"; then
  log "Snapshot post-install existiert bereits"
else
  pct snapshot "$CTID" "post-install"
fi

### =========================
### 17) Final checks
### =========================

log "Checks: Service status + Ports listening"
pct_exec "systemctl is-active maddy; ss -lntp | grep -E ':(25|587|993)\\b' || true"

log "FERTIG"
echo "Maddy Mail Server ${MADDY_VERSION} sollte jetzt erreichbar sein:"
echo "  SMTP:       ${IP_CIDR%/*}:25"
echo "  Submission: ${IP_CIDR%/*}:587"
echo "  IMAPS:      ${IP_CIDR%/*}:993"
echo ""
echo "Mail-Accounts erstellt:"
echo "  ${MAIL_ACCOUNT1_EMAIL}"
echo "  ${MAIL_ACCOUNT2_EMAIL}"
echo ""
echo "Naechste Schritte:"
echo "  1. Mail-Client konfigurieren (Thunderbird/Evolution)"
echo "     IMAP: ${IP_CIDR%/*}:993 (SSL/TLS)"
echo "     SMTP: ${IP_CIDR%/*}:587 (STARTTLS)"
echo "  2. Test-Mail senden zwischen Accounts"
echo "  3. Vaultwarden SMTP konfigurieren"
echo "  4. Reverse Proxy (optional, für Webmail)"
echo ""
echo "Rollback:"
echo "  pct stop ${CTID} && pct rollback ${CTID} pre-install && pct start ${CTID}"
