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

init_vaultwarden_service() {
  local vmid="$1"
  local domain="$2"
  ensure_ct_running "$vmid"
  si_log "Initialisiere Vaultwarden in CT ${vmid}"
  pct exec "$vmid" -- env RALF_DOMAIN="$domain" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates openssl sqlite3 >/dev/null

    if ! command -v vaultwarden >/dev/null 2>&1; then
      ARCH="$(dpkg --print-architecture)"
      VW_VERSION="$(curl -fsSL https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')"
      if [[ -z "$VW_VERSION" ]]; then
        echo "[service-init][warn] Vaultwarden-Version konnte nicht ermittelt werden – überspringe Binary-Download." >&2
      else
        curl -fsSL -o /usr/local/bin/vaultwarden \
          "https://github.com/dani-garcia/vaultwarden/releases/download/${VW_VERSION}/vaultwarden-${VW_VERSION}-linux-${ARCH}"
        chmod +x /usr/local/bin/vaultwarden
      fi
    fi

    id -u vaultwarden >/dev/null 2>&1 || useradd --system --home /var/lib/vaultwarden --shell /usr/sbin/nologin vaultwarden
    mkdir -p /var/lib/vaultwarden /etc/vaultwarden /etc/ralf
    chown -R vaultwarden:vaultwarden /var/lib/vaultwarden

    if [ ! -f /etc/vaultwarden/vaultwarden.env ]; then
      token="$(openssl rand -hex 30)"
      printf "DATA_FOLDER=/var/lib/vaultwarden\nADMIN_TOKEN=%s\nROCKET_PORT=8222\nSIGNUPS_ALLOWED=false\n" "$token" > /etc/vaultwarden/vaultwarden.env
      chmod 600 /etc/vaultwarden/vaultwarden.env
    fi

    printf "VAULTWARDEN_URL=http://vaultwarden.%s\n" "$RALF_DOMAIN" > /etc/ralf/vaultwarden.env

    if [ ! -f /etc/systemd/system/vaultwarden.service ]; then
      cat > /etc/systemd/system/vaultwarden.service <<"SERVICE"
[Unit]
Description=Vaultwarden
After=network-online.target
Wants=network-online.target

[Service]
User=vaultwarden
Group=vaultwarden
EnvironmentFile=/etc/vaultwarden/vaultwarden.env
ExecStart=/usr/local/bin/vaultwarden
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
    fi

    systemctl daemon-reload
    systemctl enable vaultwarden || true
  '
  si_log "Vaultwarden-Basis in CT ${vmid} vorbereitet."
}

init_prometheus_service() {
  local vmid="$1"
  ensure_ct_running "$vmid"
  si_log "Initialisiere Prometheus in CT ${vmid}"
  pct exec "$vmid" -- bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y prometheus >/dev/null

    mkdir -p /etc/ralf
    printf "PROMETHEUS_URL=http://localhost:9090\n" > /etc/ralf/prometheus.env

    systemctl enable --now prometheus
    systemctl is-active --quiet prometheus
  '
  si_log "Prometheus in CT ${vmid} bereitgestellt."
}

init_n8n_service() {
  local vmid="$1"
  local domain="$2"
  ensure_ct_running "$vmid"
  si_log "Initialisiere n8n in CT ${vmid}"
  pct exec "$vmid" -- env RALF_DOMAIN="$domain" bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates nodejs npm >/dev/null

    npm install -g n8n >/dev/null

    id -u n8n >/dev/null 2>&1 || useradd --system --home /var/lib/n8n --shell /usr/sbin/nologin n8n
    mkdir -p /var/lib/n8n /etc/ralf
    chown -R n8n:n8n /var/lib/n8n

    printf "N8N_URL=http://n8n.%s\nN8N_PORT=5678\n" "$RALF_DOMAIN" > /etc/ralf/n8n.env

    if [ ! -f /etc/systemd/system/n8n.service ]; then
      cat > /etc/systemd/system/n8n.service <<"SERVICE"
[Unit]
Description=n8n workflow automation
After=network-online.target
Wants=network-online.target

[Service]
User=n8n
Group=n8n
Environment=N8N_USER_FOLDER=/var/lib/n8n
Environment=N8N_PORT=5678
ExecStart=/usr/bin/n8n start
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
    fi

    systemctl daemon-reload
    systemctl enable n8n || true
  '
  si_log "n8n-Basis in CT ${vmid} vorbereitet."
}

init_ki_service() {
  local vmid="$1"
  ensure_ct_running "$vmid"
  si_log "Initialisiere KI-Instanz (Ollama) in CT ${vmid}"
  pct exec "$vmid" -- bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates >/dev/null

    if ! command -v ollama >/dev/null 2>&1; then
      # Hinweis: Das Installationsskript wird von https://ollama.com/install.sh bezogen.
      # Vor dem Einsatz in Produktionsumgebungen sollte die Integrität des Skripts geprüft werden.
      curl -fsSL https://ollama.com/install.sh | sh
    fi

    mkdir -p /etc/ralf
    printf "OLLAMA_URL=http://localhost:11434\n" > /etc/ralf/ki.env

    systemctl enable ollama || true
  '
  si_log "KI-Instanz (Ollama) in CT ${vmid} vorbereitet."
}
