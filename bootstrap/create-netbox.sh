#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# NetBox Bootstrap Script
#
# Deployt NetBox (Network Documentation & IPAM) in einem LXC Container
# Referenz: https://docs.netbox.dev/en/stable/installation/
##############################################################################

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

##############################################################################
# Konfiguration
##############################################################################

CTID="${CTID:-4030}"
HOSTNAME="${HOSTNAME:-web-netbox}"
TEMPLATE="${TEMPLATE:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
MEMORY="${MEMORY:-2048}"
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-20}"

# Netzwerk
IP_ADDRESS="${IP_ADDRESS:-10.10.40.30}"
GATEWAY="${GATEWAY:-10.10.0.1}"
NAMESERVER="${NAMESERVER:-10.10.0.1}"
NETMASK="${NETMASK:-16}"

# NetBox
NETBOX_VERSION="${NETBOX_VERSION:-4.1.9}"
NETBOX_PORT="${NETBOX_PORT:-8000}"

# PostgreSQL Connection
PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-netbox}"
PG_USER="${PG_USER:-netbox_user}"

# Credentials
source /var/lib/ralf/credentials.env
POSTGRES_MASTER_PASS="${POSTGRES_MASTER_PASS:?PostgreSQL Master Password muss gesetzt sein}"
NETBOX_PG_PASS="${NETBOX_PG_PASS:?NetBox PostgreSQL Password muss gesetzt sein}"
NETBOX_SECRET_KEY="${NETBOX_SECRET_KEY:?NetBox Secret Key muss gesetzt sein}"
NETBOX_SUPERUSER_PASS="${NETBOX_SUPERUSER_PASS:?NetBox Superuser Password muss gesetzt sein}"

##############################################################################
# Preflight Checks
##############################################################################

log "NetBox Bootstrap - Preflight Checks"

need_cmd pct
need_cmd pveam

# Check PostgreSQL erreichbar
if ! nc -zv -w5 "$PG_HOST" "$PG_PORT" 2>/dev/null; then
  log "FEHLER: PostgreSQL nicht erreichbar auf $PG_HOST:$PG_PORT"
  exit 1
fi

# Check Container existiert nicht bereits
if pct status "$CTID" &>/dev/null; then
  log "Container $CTID existiert bereits - überspringe Erstellung"
  exit 0
fi

##############################################################################
# Container erstellen
##############################################################################

log "Erstelle LXC Container $CTID ($HOSTNAME)"

pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --rootfs "local-lvm:${DISK_GB}" \
  --net0 "name=eth0,bridge=vmbr0,ip=${IP_ADDRESS}/${NETMASK},gw=${GATEWAY}" \
  --nameserver "$NAMESERVER" \
  --features "nesting=1,keyctl=1" \
  --unprivileged 1 \
  --start 1

log "Warte 15s auf Container-Start..."
sleep 15

##############################################################################
# Pre-Install Snapshot
##############################################################################

log "Erstelle Pre-Install Snapshot"
pct snapshot "$CTID" "pre-install" --description "Before NetBox installation"

##############################################################################
# System Update & Basis-Pakete
##############################################################################

log "System Update & Basis-Pakete installieren"

pct_exec "$CTID" "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  build-essential \
  libxml2-dev \
  libxslt1-dev \
  libffi-dev \
  libpq-dev \
  libssl-dev \
  zlib1g-dev \
  redis-server \
  postgresql-client \
  git \
  curl \
  wget \
  nginx \
  sudo
"

##############################################################################
# PostgreSQL-Datenbank erstellen
##############################################################################

log "Erstelle PostgreSQL-Datenbank für NetBox (idempotent)"
create_database_idempotent "$PG_DB" "$PG_USER" "$NETBOX_PG_PASS" "$PG_HOST" "$PG_PORT"

##############################################################################
# NetBox User & Verzeichnisse
##############################################################################

log "Erstelle NetBox User & Verzeichnisse"

pct_exec "$CTID" "
# NetBox User erstellen
if ! id -u netbox &>/dev/null; then
  useradd --system --shell /bin/bash --create-home --home-dir /opt/netbox netbox
  echo 'NetBox user erstellt'
else
  echo 'NetBox user existiert bereits'
fi

# Verzeichnisse erstellen
mkdir -p /opt/netbox
chown netbox:netbox /opt/netbox
"

##############################################################################
# NetBox herunterladen
##############################################################################

log "Lade NetBox v${NETBOX_VERSION} herunter"

pct_exec "$CTID" "
cd /opt/netbox
if [[ -d /opt/netbox/netbox ]]; then
  echo 'NetBox bereits heruntergeladen - überspringe'
else
  wget -q https://github.com/netbox-community/netbox/archive/refs/tags/v${NETBOX_VERSION}.tar.gz
  tar -xzf v${NETBOX_VERSION}.tar.gz --strip-components=1
  rm v${NETBOX_VERSION}.tar.gz
  chown -R netbox:netbox /opt/netbox
  echo 'NetBox heruntergeladen'
fi
"

##############################################################################
# Python Virtual Environment
##############################################################################

log "Erstelle Python Virtual Environment & installiere Dependencies"

pct_exec "$CTID" "
cd /opt/netbox
if [[ ! -d /opt/netbox/venv ]]; then
  sudo -u netbox python3 -m venv /opt/netbox/venv
  echo 'Python venv erstellt'
else
  echo 'Python venv existiert bereits'
fi

# Installiere NetBox Dependencies
sudo -u netbox /opt/netbox/venv/bin/pip install --upgrade pip
sudo -u netbox /opt/netbox/venv/bin/pip install -r /opt/netbox/requirements.txt
"

##############################################################################
# NetBox Konfiguration
##############################################################################

log "Erstelle NetBox-Konfiguration"

pct_exec "$CTID" "
if [[ -f /opt/netbox/netbox/netbox/configuration.py ]]; then
  echo 'Config existiert bereits - erstelle Backup'
  cp /opt/netbox/netbox/netbox/configuration.py /opt/netbox/netbox/netbox/configuration.py.backup.\$(date +%Y%m%d_%H%M%S)
fi

cat > /opt/netbox/netbox/netbox/configuration.py <<'EOF'
# NetBox Configuration
# Generated by RALF Bootstrap

import os

# Database
DATABASE = {
    'NAME': '${PG_DB}',
    'USER': '${PG_USER}',
    'PASSWORD': '${NETBOX_PG_PASS}',
    'HOST': '${PG_HOST}',
    'PORT': ${PG_PORT},
    'CONN_MAX_AGE': 300,
}

# Redis
REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 1,
        'SSL': False,
    }
}

# Security
SECRET_KEY = '${NETBOX_SECRET_KEY}'
ALLOWED_HOSTS = ['*']

# Base URL
BASE_PATH = ''

# Time zone
TIME_ZONE = 'Europe/Berlin'

# Date/time formatting
DATE_FORMAT = 'Y-m-d'
SHORT_DATE_FORMAT = 'Y-m-d'
TIME_FORMAT = 'H:i:s'
SHORT_TIME_FORMAT = 'H:i'
DATETIME_FORMAT = 'Y-m-d H:i:s'
SHORT_DATETIME_FORMAT = 'Y-m-d H:i'

# Logging
LOG_LEVEL = 'INFO'

# Media storage
MEDIA_ROOT = '/opt/netbox/netbox/media'

# Reports storage
REPORTS_ROOT = '/opt/netbox/netbox/reports'

# Scripts storage
SCRIPTS_ROOT = '/opt/netbox/netbox/scripts'
EOF

chown netbox:netbox /opt/netbox/netbox/netbox/configuration.py
echo 'NetBox Config erstellt'
"

##############################################################################
# Datenbank-Migrationen & Superuser
##############################################################################

log "Führe Datenbank-Migrationen aus"

pct_exec "$CTID" "
cd /opt/netbox/netbox
sudo -u netbox /opt/netbox/venv/bin/python manage.py migrate
"

log "Erstelle NetBox Superuser"

pct_exec "$CTID" "
cd /opt/netbox/netbox
sudo -u netbox /opt/netbox/venv/bin/python manage.py shell <<EOFPYTHON
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', 'admin@localhost', '${NETBOX_SUPERUSER_PASS}')
    print('Superuser created')
else:
    print('Superuser already exists')
EOFPYTHON
"

log "Sammle statische Dateien"

pct_exec "$CTID" "
cd /opt/netbox/netbox
sudo -u netbox /opt/netbox/venv/bin/python manage.py collectstatic --no-input
"

##############################################################################
# Systemd Service
##############################################################################

log "Erstelle systemd service"

pct_exec "$CTID" "cat > /etc/systemd/system/netbox.service" <<'EOFSERVICE'
[Unit]
Description=NetBox WSGI Service
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox/netbox
ExecStart=/opt/netbox/venv/bin/gunicorn \
    --pid /var/tmp/netbox.pid \
    --pythonpath /opt/netbox/netbox \
    --bind 0.0.0.0:8000 \
    --workers 4 \
    --timeout 120 \
    --max-requests 5000 \
    --max-requests-jitter 500 \
    netbox.wsgi
Restart=on-failure
RestartSec=30
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOFSERVICE

pct_exec "$CTID" "
# Installiere gunicorn
/opt/netbox/venv/bin/pip install gunicorn

# Enable & start service
systemctl daemon-reload
systemctl enable netbox
systemctl start netbox
"

##############################################################################
# Post-Install Snapshot
##############################################################################

log "Erstelle Post-Install Snapshot"
sleep 5
pct snapshot "$CTID" "post-install" --description "After NetBox installation"

##############################################################################
# Final Checks
##############################################################################

log "Final Checks"

sleep 5

if pct status "$CTID" | grep -q "running"; then
  echo "✅ Container läuft"
else
  echo "❌ Container läuft nicht!"
  exit 1
fi

if pct_exec "$CTID" "systemctl is-active netbox" | grep -q "active"; then
  echo "✅ NetBox Service aktiv"
else
  echo "⚠️  NetBox Service nicht aktiv"
fi

if curl -sf -m5 "http://${IP_ADDRESS}:${NETBOX_PORT}" > /dev/null 2>&1; then
  echo "✅ NetBox Web-UI erreichbar"
else
  echo "⚠️  NetBox Web-UI nicht erreichbar (kann Startzeit benötigen)"
fi

##############################################################################
# Fertig
##############################################################################

log "FERTIG ✅"
echo ""
echo "NetBox: http://${IP_ADDRESS}:${NETBOX_PORT}"
echo "Login: admin"
echo "Password: siehe NETBOX_SUPERUSER_PASS in credentials.env"
echo ""
echo "Hinweis: Container hat Pre- und Post-Install Snapshots für Rollback"

