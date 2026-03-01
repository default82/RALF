#!/usr/bin/env bash
set -euo pipefail

si_log() { printf '[service-init] %s\n' "$*"; }
si_warn() { printf '[service-init][warn] %s\n' "$*" >&2; }

ensure_ct_running() {
  local vmid="$1"
  pct start "$vmid" >/dev/null 2>&1 || true
}

init_minio_service() {
  local vmid="$1"
  ensure_ct_running "$vmid"
  si_log "Initialisiere MinIO in CT ${vmid}"
  pct exec "$vmid" -- bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates openssl >/dev/null

    if ! command -v minio >/dev/null 2>&1; then
      curl -fsSL -o /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-amd64/minio
      chmod +x /usr/local/bin/minio
    fi

    id -u minio >/dev/null 2>&1 || useradd --system --home /var/lib/minio --shell /usr/sbin/nologin minio
    mkdir -p /var/lib/minio /etc/minio /etc/ralf
    chown -R minio:minio /var/lib/minio

    if [ ! -f /etc/minio/minio.env ]; then
      user="minioadmin"
      pass="$(openssl rand -base64 36 | tr -d "\n" | head -c 40)"
      printf "MINIO_ROOT_USER=%s\nMINIO_ROOT_PASSWORD=%s\nMINIO_VOLUMES=/var/lib/minio\nMINIO_OPTS=--console-address :9001\n" "$user" "$pass" > /etc/minio/minio.env
      chmod 600 /etc/minio/minio.env
    fi

    if [ ! -f /etc/systemd/system/minio.service ]; then
      cat > /etc/systemd/system/minio.service <<"SERVICE"
[Unit]
Description=MinIO
After=network-online.target
Wants=network-online.target

[Service]
User=minio
Group=minio
EnvironmentFile=/etc/minio/minio.env
ExecStart=/usr/local/bin/minio server ${MINIO_VOLUMES} ${MINIO_OPTS}
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE
    fi

    systemctl daemon-reload
    systemctl enable --now minio
    systemctl is-active --quiet minio
  '
}

init_postgresql_service() {
  local vmid="$1"
  ensure_ct_running "$vmid"
  si_log "Initialisiere PostgreSQL in CT ${vmid}"
  pct exec "$vmid" -- bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y postgresql postgresql-contrib openssl >/dev/null

    mkdir -p /etc/ralf
    if [ ! -f /etc/ralf/postgres.env ]; then
      db="ralf_db"
      user="ralf_user"
      pass="$(openssl rand -base64 36 | tr -d "\n" | head -c 40)"
      printf "RALF_DB=%s\nRALF_USER=%s\nRALF_PASSWORD=%s\n" "$db" "$user" "$pass" > /etc/ralf/postgres.env
      chmod 600 /etc/ralf/postgres.env
    fi

    . /etc/ralf/postgres.env

    systemctl enable --now postgresql
    systemctl is-active --quiet postgresql

    su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='\"'\"'$RALF_USER'\"'\"'\" | grep -q 1 || psql -c \"CREATE USER $RALF_USER WITH PASSWORD '\"'\"'$RALF_PASSWORD'\"'\"';\""
    su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='\"'\"'$RALF_DB'\"'\"'\" | grep -q 1 || psql -c \"CREATE DATABASE $RALF_DB OWNER $RALF_USER;\""
  '
}

init_gitea_service() {
  local vmid="$1"
  local domain="$2"
  ensure_ct_running "$vmid"
  si_log "Initialisiere Gitea in CT ${vmid}"
  pct exec "$vmid" -- env RALF_DOMAIN="$domain" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y gitea >/dev/null

    systemctl enable --now gitea
    systemctl is-active --quiet gitea

    mkdir -p /etc/ralf
    printf "GITEA_ROOT_URL=http://gitea.%s\n" "$RALF_DOMAIN" > /etc/ralf/gitea.env
  '
}

init_semaphore_service() {
  local vmid="$1"
  local domain="$2"
  ensure_ct_running "$vmid"
  si_log "Initialisiere Semaphore-Basis in CT ${vmid}"
  pct exec "$vmid" -- env RALF_DOMAIN="$domain" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates jq sqlite3 >/dev/null

    mkdir -p /etc/ralf
    printf "SEMAPHORE_URL=http://semaphore.%s\n" "$RALF_DOMAIN" > /etc/ralf/semaphore.env

    if apt-cache show semaphore >/dev/null 2>&1; then
      apt-get install -y semaphore >/dev/null
      systemctl enable --now semaphore || true
    fi
  '
  si_warn "Semaphore-Applikation ist als Basis-Init vorbereitet; vollständige App-Config folgt im nächsten Schritt."
}
