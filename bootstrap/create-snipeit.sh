#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Snipe-IT Bootstrap Script
#
# Deployt Snipe-IT (Asset Management) in einem LXC Container
# Benötigt: MariaDB Container (CT 2011)
# Referenz: https://snipe-it.readme.io/docs
##############################################################################

# Lade gemeinsame Helper-Funktionen
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/lib/common.sh"

##############################################################################
# Konfiguration
##############################################################################

CTID="${CTID:-4040}"
HOSTNAME="${HOSTNAME:-web-snipeit}"
TEMPLATE="${TEMPLATE:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
MEMORY="${MEMORY:-1024}"     # MB - PHP App, moderat (optimiert für 500GB/16GB node)
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-8}"

# Netzwerk
IP_ADDRESS="${IP_ADDRESS:-10.10.40.40}"
GATEWAY="${GATEWAY:-10.10.0.1}"
NAMESERVER="${NAMESERVER:-10.10.0.1}"
NETMASK="${NETMASK:-16}"

# Snipe-IT
SNIPEIT_VERSION="${SNIPEIT_VERSION:-v8.3.7}"
SNIPEIT_PORT="${SNIPEIT_PORT:-8080}"
SNIPEIT_APP_URL="${SNIPEIT_APP_URL:-http://${IP_ADDRESS}:${SNIPEIT_PORT}}"

# MariaDB Connection (External Container)
MYSQL_HOST="${MYSQL_HOST:-10.10.20.11}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DB="${MYSQL_DB:-snipeit}"
MYSQL_USER="${MYSQL_USER:-snipeit_user}"

# Credentials
source /var/lib/ralf/credentials.env
MARIADB_ROOT_PASS="${MARIADB_ROOT_PASS:?MariaDB Root Password muss gesetzt sein}"
SNIPEIT_MYSQL_PASS="${SNIPEIT_MYSQL_PASS:?Snipe-IT MySQL Password muss gesetzt sein}"
SNIPEIT_APP_KEY="${SNIPEIT_APP_KEY:?Snipe-IT App Key muss gesetzt sein}"

##############################################################################
# Preflight Checks
##############################################################################

log "Snipe-IT Bootstrap - Preflight Checks"

need_cmd pct
need_cmd pveam

# Check MariaDB erreichbar
if ! nc -zv -w5 "$MYSQL_HOST" "$MYSQL_PORT" 2>/dev/null; then
  log "FEHLER: MariaDB nicht erreichbar auf $MYSQL_HOST:$MYSQL_PORT"
  log "Bitte zuerst MariaDB-Container deployen: bash bootstrap/create-mariadb.sh"
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
pct snapshot "$CTID" "pre-install" --description "Before Snipe-IT installation"

##############################################################################
# System Update & Basis-Pakete
##############################################################################

log "System Update & Basis-Pakete installieren"

pct_exec "$CTID" "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  nginx \
  php8.3 \
  php8.3-fpm \
  php8.3-mysql \
  php8.3-curl \
  php8.3-gd \
  php8.3-ldap \
  php8.3-zip \
  php8.3-mbstring \
  php8.3-xml \
  php8.3-bcmath \
  php8.3-redis \
  mariadb-client \
  git \
  curl \
  wget \
  unzip \
  sudo
"

##############################################################################
# MySQL-Datenbank erstellen
##############################################################################

log "Erstelle MySQL-Datenbank für Snipe-IT (idempotent)"
create_mysql_database_idempotent "$MYSQL_DB" "$MYSQL_USER" "$SNIPEIT_MYSQL_PASS" "$MYSQL_HOST" "$MYSQL_PORT"

##############################################################################
# Snipe-IT herunterladen
##############################################################################

log "Lade Snipe-IT ${SNIPEIT_VERSION} herunter"

pct_exec "$CTID" "
cd /var/www
if [[ -d /var/www/snipe-it ]]; then
  echo 'Snipe-IT bereits vorhanden - überspringe Download'
else
  git clone --depth=1 --branch ${SNIPEIT_VERSION} https://github.com/snipe/snipe-it.git
  chown -R www-data:www-data /var/www/snipe-it
  echo 'Snipe-IT heruntergeladen'
fi
"

##############################################################################
# Composer installieren
##############################################################################

log "Installiere Composer"

pct_exec "$CTID" "
if ! command -v composer &>/dev/null; then
  curl -sS https://getcomposer.org/installer | php
  mv composer.phar /usr/local/bin/composer
  chmod +x /usr/local/bin/composer
  echo 'Composer installiert'
else
  echo 'Composer bereits installiert'
fi
"

##############################################################################
# Snipe-IT Dependencies
##############################################################################

log "Installiere Snipe-IT Dependencies (kann einige Minuten dauern)"

pct_exec "$CTID" "
cd /var/www/snipe-it
sudo -u www-data composer install --no-dev --prefer-source --no-interaction
"

##############################################################################
# Snipe-IT Konfiguration
##############################################################################

log "Erstelle Snipe-IT .env Konfiguration"

pct_exec "$CTID" "
cd /var/www/snipe-it

if [[ -f /var/www/snipe-it/.env ]]; then
  echo '.env existiert bereits - erstelle Backup'
  cp /var/www/snipe-it/.env /var/www/snipe-it/.env.backup.\$(date +%Y%m%d_%H%M%S)
fi

cat > /var/www/snipe-it/.env <<'EOF'
# Snipe-IT Configuration
# Generated by RALF Bootstrap

# Application
APP_ENV=production
APP_DEBUG=false
APP_KEY=${SNIPEIT_APP_KEY}
APP_URL=${SNIPEIT_APP_URL}
APP_TIMEZONE='Europe/Berlin'
APP_LOCALE=de_DE

# Database (External MariaDB Container)
DB_CONNECTION=mysql
DB_HOST=${MYSQL_HOST}
DB_PORT=${MYSQL_PORT}
DB_DATABASE=${MYSQL_DB}
DB_USERNAME=${MYSQL_USER}
DB_PASSWORD=${SNIPEIT_MYSQL_PASS}

# Mail (optional - kann später konfiguriert werden)
MAIL_DRIVER=smtp
MAIL_HOST=localhost
MAIL_PORT=25
MAIL_ENCRYPTION=null
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_FROM_ADDR=noreply@localhost
MAIL_FROM_NAME='Snipe-IT'

# Cache & Session
CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_DRIVER=sync

# Security
APP_ALLOW_INSECURE_HOSTS=false
ENABLE_BACKUP=false
EOF

chown www-data:www-data /var/www/snipe-it/.env
chmod 640 /var/www/snipe-it/.env
echo 'Snipe-IT .env erstellt'
"

##############################################################################
# Storage & Permissions
##############################################################################

log "Setze Berechtigungen & erstelle Storage-Links"

pct_exec "$CTID" "
cd /var/www/snipe-it
chown -R www-data:www-data storage public/uploads
chmod -R 755 storage
chmod -R 755 public/uploads

# Storage link
if [[ ! -L /var/www/snipe-it/public/storage ]]; then
  sudo -u www-data php artisan storage:link
fi
"

##############################################################################
# Datenbank-Migrationen
##############################################################################

log "Führe Datenbank-Migrationen aus"

pct_exec "$CTID" "
cd /var/www/snipe-it
sudo -u www-data php artisan migrate --force
"

##############################################################################
# Nginx Konfiguration
##############################################################################

log "Erstelle Nginx Konfiguration"

pct_exec "$CTID" "cat > /etc/nginx/sites-available/snipeit" <<'EOFNGINX'
server {
    listen 8080;
    listen [::]:8080;
    server_name _;

    root /var/www/snipe-it/public;
    index index.php;

    client_max_body_size 100M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOFNGINX

pct_exec "$CTID" "
# Aktiviere Snipe-IT Site
ln -sf /etc/nginx/sites-available/snipeit /etc/nginx/sites-enabled/snipeit
rm -f /etc/nginx/sites-enabled/default

# Test & Reload Nginx
nginx -t
systemctl restart nginx
systemctl restart php8.3-fpm
"

##############################################################################
# Post-Install Snapshot
##############################################################################

log "Erstelle Post-Install Snapshot"
sleep 5
pct snapshot "$CTID" "post-install" --description "After Snipe-IT installation"

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

if pct_exec "$CTID" "systemctl is-active nginx" | grep -q "active"; then
  echo "✅ Nginx Service aktiv"
else
  echo "⚠️  Nginx Service nicht aktiv"
fi

if curl -sf -m5 "http://${IP_ADDRESS}:${SNIPEIT_PORT}" > /dev/null 2>&1; then
  echo "✅ Snipe-IT Web-UI erreichbar"
else
  echo "⚠️  Snipe-IT Web-UI nicht erreichbar (kann Startzeit benötigen)"
fi

##############################################################################
# Fertig
##############################################################################

log "FERTIG ✅"
echo ""
echo "Snipe-IT: http://${IP_ADDRESS}:${SNIPEIT_PORT}"
echo "MariaDB: ${MYSQL_HOST}:${MYSQL_PORT}"
echo ""
echo "Setup-Wizard wird beim ersten Besuch angezeigt"
echo "Erstelle dort den ersten Admin-Account"
echo ""
echo "Hinweis: Container hat Pre- und Post-Install Snapshots für Rollback"
