#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# MariaDB Bootstrap Script
#
# Deployt MariaDB (MySQL-kompatible Datenbank) in einem LXC Container
##############################################################################

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

##############################################################################
# Konfiguration
##############################################################################

CTID="${CTID:-2011}"
HOSTNAME="${HOSTNAME:-svc-mariadb}"
TEMPLATE="${TEMPLATE:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
MEMORY="${MEMORY:-1024}"
CORES="${CORES:-2}"
DISK_GB="${DISK_GB:-16}"

# Netzwerk
IP_ADDRESS="${IP_ADDRESS:-10.10.20.11}"
GATEWAY="${GATEWAY:-10.10.0.1}"
NAMESERVER="${NAMESERVER:-10.10.0.1}"
NETMASK="${NETMASK:-16}"

# MariaDB
MARIADB_VERSION="${MARIADB_VERSION:-11.4}"
MARIADB_PORT="${MARIADB_PORT:-3306}"

# Credentials
source /var/lib/ralf/credentials.env
MARIADB_ROOT_PASS="${MARIADB_ROOT_PASS:?MariaDB Root Password muss gesetzt sein}"

##############################################################################
# Preflight Checks
##############################################################################

log "MariaDB Bootstrap - Preflight Checks"

need_cmd pct
need_cmd pveam

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
pct snapshot "$CTID" "pre-install" --description "Before MariaDB installation"

##############################################################################
# System Update & MariaDB installieren
##############################################################################

log "System Update & MariaDB installieren"

pct_exec "$CTID" "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  mariadb-server \
  mariadb-client \
  curl \
  wget
"

##############################################################################
# MariaDB Konfiguration
##############################################################################

log "Konfiguriere MariaDB für Remote-Zugriff"

pct_exec "$CTID" "
# Erlaube Remote-Verbindungen
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

# Optional: Setze character set auf utf8mb4
cat >> /etc/mysql/mariadb.conf.d/50-server.cnf <<EOF

[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[client]
default-character-set = utf8mb4
EOF

# Restart MariaDB
systemctl restart mariadb
"

##############################################################################
# Secure Installation
##############################################################################

log "Sichere MariaDB Installation"

pct_exec "$CTID" "
mysql <<EOFMYSQL
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASS}';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove remote root login (außer vom lokalen Netzwerk)
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1', '10.10.%');

-- Drop test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Create root user for network access (10.10.0.0/16)
CREATE USER IF NOT EXISTS 'root'@'10.10.%' IDENTIFIED BY '${MARIADB_ROOT_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'10.10.%' WITH GRANT OPTION;

FLUSH PRIVILEGES;
EOFMYSQL

echo 'MariaDB secured'
"

##############################################################################
# Systemd Auto-Start
##############################################################################

log "Aktiviere MariaDB Auto-Start"

pct_exec "$CTID" "
systemctl enable mariadb
"

##############################################################################
# Post-Install Snapshot
##############################################################################

log "Erstelle Post-Install Snapshot"
sleep 5
pct snapshot "$CTID" "post-install" --description "After MariaDB installation"

##############################################################################
# Final Checks
##############################################################################

log "Final Checks"

if pct status "$CTID" | grep -q "running"; then
  echo "✅ Container läuft"
else
  echo "❌ Container läuft nicht!"
  exit 1
fi

if pct_exec "$CTID" "systemctl is-active mariadb" | grep -q "active"; then
  echo "✅ MariaDB Service aktiv"
else
  echo "❌ MariaDB Service nicht aktiv!"
  exit 1
fi

if nc -zv -w5 "$IP_ADDRESS" "$MARIADB_PORT" 2>/dev/null; then
  echo "✅ MariaDB Port ${MARIADB_PORT} erreichbar"
else
  echo "⚠️  MariaDB Port nicht erreichbar"
fi

##############################################################################
# Fertig
##############################################################################

log "FERTIG ✅"
echo ""
echo "MariaDB: ${IP_ADDRESS}:${MARIADB_PORT}"
echo "Root User: root"
echo "Root Password: siehe MARIADB_ROOT_PASS in credentials.env"
echo ""
echo "Verbindungstest:"
echo "  mysql -h ${IP_ADDRESS} -u root -p"
echo ""
echo "Helper-Funktion für App-Datenbanken:"
echo "  create_mysql_database_idempotent DB_NAME DB_USER DB_PASS"
echo ""
echo "Hinweis: Container hat Pre- und Post-Install Snapshots für Rollback"

