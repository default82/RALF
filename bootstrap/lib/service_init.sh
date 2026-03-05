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
  pct exec "$vmid" -- env \
    GITEA_DB_USER="${GITEA_DB_USER:-}" \
    GITEA_DB_PASS="${GITEA_DB_PASS:-}" \
    GITEA_DB_NAME="${GITEA_DB_NAME:-gitea_db}" \
    N8N_DB_USER="${N8N_DB_USER:-}" \
    N8N_DB_PASS="${N8N_DB_PASS:-}" \
    N8N_DB_NAME="${N8N_DB_NAME:-n8n_db}" \
    MATRIX_DB_USER="${MATRIX_DB_USER:-}" \
    MATRIX_DB_PASS="${MATRIX_DB_PASS:-}" \
    MATRIX_DB_NAME="${MATRIX_DB_NAME:-synapse_db}" \
    bash -lc '
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

    # Configure PostgreSQL to accept connections from the RALF network
    PG_VERSION="$(pg_lsclusters -h | awk '"'"'{print $1}'"'"' | head -1)"
    PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
    PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

    if ! grep -q "^listen_addresses = '\*'" "$PG_CONF" 2>/dev/null; then
      sed -i "s/^#*listen_addresses = .*/listen_addresses = '*'/" "$PG_CONF"
    fi
    if ! grep -q "10.10.0.0/16" "$PG_HBA" 2>/dev/null; then
      printf "host\tall\tall\t10.10.0.0/16\tscram-sha-256\n" >> "$PG_HBA"
    fi

    systemctl enable postgresql
    systemctl restart postgresql
    systemctl is-active --quiet postgresql

    # Helper: idempotent user + database creation.
    # $1=user $2=password $3=dbname $4=optional extra CREATE DATABASE options
    create_pg_user_db() {
      local u="$1" p="$2" d="$3" extra_opts="${4:-}"
      [ -z "$u" ] && return 0
      su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${u}'\" | grep -q 1 || \
        psql -c \"CREATE USER ${u} WITH PASSWORD '${p}';\""
      if [ -z "$extra_opts" ]; then
        su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${d}'\" | grep -q 1 || \
          psql -c \"CREATE DATABASE ${d} OWNER ${u};\""
      else
        su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${d}'\" | grep -q 1 || \
          psql -c \"CREATE DATABASE ${d} ${extra_opts} OWNER ${u};\""
      fi
    }

    # Default RALF database
    create_pg_user_db "$RALF_USER" "$RALF_PASSWORD" "$RALF_DB"

    # Per-service databases
    create_pg_user_db "$GITEA_DB_USER" "$GITEA_DB_PASS" "$GITEA_DB_NAME"
    create_pg_user_db "$N8N_DB_USER" "$N8N_DB_PASS" "$N8N_DB_NAME"

    # Matrix Synapse requires UTF-8 with C locale (cannot run inside a transaction)
    create_pg_user_db "$MATRIX_DB_USER" "$MATRIX_DB_PASS" "$MATRIX_DB_NAME" \
      "ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0"
  '
}

init_gitea_service() {
  local vmid="$1"
  local domain="$2"
  local pg_host="${3:-}"
  local pg_user="${4:-}"
  local pg_pass="${5:-}"
  local pg_db="${6:-gitea_db}"
  ensure_ct_running "$vmid"
  si_log "Initialisiere Gitea in CT ${vmid}"
  pct exec "$vmid" -- env \
    RALF_DOMAIN="$domain" \
    PG_HOST="$pg_host" \
    PG_USER="$pg_user" \
    PG_PASS="$pg_pass" \
    PG_DB="$pg_db" \
    bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates git >/dev/null

    if ! command -v gitea >/dev/null 2>&1; then
      ARCH="$(dpkg --print-architecture)"
      GITEA_VERSION="$(curl -fsSL https://dl.gitea.com/gitea/version.json | grep -oP "\"latest\":\s*\"\K[^\"]+")"
      if [[ -z "$GITEA_VERSION" ]]; then
        echo "[service-init][error] Gitea-Version konnte nicht ermittelt werden." >&2
        exit 1
      fi
      GITEA_URL="https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}"
      curl -fsSL -o /usr/local/bin/gitea "${GITEA_URL}"
      EXPECTED="$(curl -fsSL "${GITEA_URL}.sha256" | awk '"'"'{print $1}'"'"')"
      ACTUAL="$(sha256sum /usr/local/bin/gitea | awk '"'"'{print $1}'"'"')"
      if [[ "$EXPECTED" != "$ACTUAL" ]]; then
        echo "[service-init][error] SHA256-Prüfung für Gitea-Binary fehlgeschlagen." >&2
        rm -f /usr/local/bin/gitea
        exit 1
      fi
      chmod +x /usr/local/bin/gitea
    fi

    id -u git >/dev/null 2>&1 || useradd --system --home /var/lib/gitea --shell /bin/bash git
    mkdir -p /var/lib/gitea/{custom,data,log} /etc/gitea
    # /etc/ralf ist das systemweite RALF-Konfig-Verzeichnis für alle Dienste
    mkdir -p /etc/ralf
    chown -R git:git /var/lib/gitea /etc/gitea

    if [ ! -f /etc/systemd/system/gitea.service ]; then
      {
        cat <<'"'"'STATIC'"'"'
[Unit]
Description=Gitea
After=network-online.target
Wants=network-online.target

[Service]
User=git
Group=git
WorkingDirectory=/var/lib/gitea
Environment=USER=git HOME=/var/lib/gitea GITEA_WORK_DIR=/var/lib/gitea
STATIC
        if [ -n "${PG_HOST:-}" ]; then
          printf "Environment=GITEA__database__DB_TYPE=postgres\n"
          printf "Environment=GITEA__database__HOST=%s:5432\n" "$PG_HOST"
          printf "Environment=GITEA__database__NAME=%s\n" "$PG_DB"
          printf "Environment=GITEA__database__USER=%s\n" "$PG_USER"
          printf "Environment=GITEA__database__PASSWD=%s\n" "$PG_PASS"
          printf "Environment=GITEA__database__SSL_MODE=disable\n"
        fi
        cat <<'"'"'STATIC'"'"'
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always

[Install]
WantedBy=multi-user.target
STATIC
      } > /etc/systemd/system/gitea.service
    fi

    systemctl daemon-reload
    systemctl enable --now gitea
    systemctl is-active --quiet gitea

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
  local pg_host="${3:-}"
  local pg_user="${4:-}"
  local pg_pass="${5:-}"
  local pg_db="${6:-n8n_db}"
  ensure_ct_running "$vmid"
  si_log "Initialisiere n8n in CT ${vmid}"
  pct exec "$vmid" -- env \
    RALF_DOMAIN="$domain" \
    PG_HOST="$pg_host" \
    PG_USER="$pg_user" \
    PG_PASS="$pg_pass" \
    PG_DB="$pg_db" \
    bash -lc '
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
      {
        cat <<'"'"'STATIC'"'"'
[Unit]
Description=n8n workflow automation
After=network-online.target
Wants=network-online.target

[Service]
User=n8n
Group=n8n
Environment=N8N_USER_FOLDER=/var/lib/n8n
Environment=N8N_PORT=5678
STATIC
        if [ -n "${PG_HOST:-}" ]; then
          printf "Environment=DB_TYPE=postgresdb\n"
          printf "Environment=DB_POSTGRESDB_HOST=%s\n" "$PG_HOST"
          printf "Environment=DB_POSTGRESDB_PORT=5432\n"
          printf "Environment=DB_POSTGRESDB_DATABASE=%s\n" "$PG_DB"
          printf "Environment=DB_POSTGRESDB_USER=%s\n" "$PG_USER"
          printf "Environment=DB_POSTGRESDB_PASSWORD=%s\n" "$PG_PASS"
        fi
        cat <<'"'"'STATIC'"'"'
ExecStart=/usr/bin/n8n start
Restart=always

[Install]
WantedBy=multi-user.target
STATIC
      } > /etc/systemd/system/n8n.service
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

init_matrix_service() {
  local vmid="$1"
  local domain="$2"
  local pg_host="${3:-}"
  local pg_user="${4:-}"
  local pg_pass="${5:-}"
  local pg_db="${6:-synapse_db}"
  ensure_ct_running "$vmid"
  si_log "Initialisiere Matrix Synapse in CT ${vmid}"
  pct exec "$vmid" -- env \
    RALF_DOMAIN="$domain" \
    PG_HOST="$pg_host" \
    PG_USER="$pg_user" \
    PG_PASS="$pg_pass" \
    PG_DB="$pg_db" \
    bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y lsb-release wget apt-transport-https curl ca-certificates openssl >/dev/null

    # Add Matrix.org package repository
    if [ ! -f /usr/share/keyrings/matrix-org-archive-keyring.gpg ]; then
      wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg \
        https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
    fi
    if [ ! -f /etc/apt/sources.list.d/matrix-org.list ]; then
      printf "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ %s main\n" \
        "$(lsb_release -cs)" > /etc/apt/sources.list.d/matrix-org.list
    fi
    apt-get update -y >/dev/null
    # Pre-accept the debconf question for reporting stats
    echo "matrix-synapse matrix-synapse/report-stats boolean false" | debconf-set-selections
    echo "matrix-synapse matrix-synapse/server-name string matrix.${RALF_DOMAIN}" | debconf-set-selections
    apt-get install -y matrix-synapse-py3 >/dev/null

    mkdir -p /etc/ralf /var/lib/matrix-synapse /etc/matrix-synapse/conf.d

    # Write database config fragment (overrides the default SQLite config)
    if [ -n "${PG_HOST:-}" ]; then
      cat > /etc/matrix-synapse/conf.d/database.yaml <<DBCONF
database:
  name: psycopg2
  args:
    user: ${PG_USER}
    password: ${PG_PASS}
    database: ${PG_DB}
    host: ${PG_HOST}
    cp_min: 5
    cp_max: 10
DBCONF
      chmod 640 /etc/matrix-synapse/conf.d/database.yaml
      chown root:matrix-synapse /etc/matrix-synapse/conf.d/database.yaml
    fi

    # Generate signing key and registration secret if not present
    if [ ! -f /etc/matrix-synapse/homeserver.signing.key ]; then
      python3 -m synapse.app.homeserver \
        --server-name "matrix.${RALF_DOMAIN}" \
        --config-path /etc/matrix-synapse/homeserver.yaml \
        --generate-keys 2>/dev/null || true
    fi

    systemctl daemon-reload
    systemctl enable matrix-synapse
    systemctl restart matrix-synapse
    sleep 3
    systemctl is-active --quiet matrix-synapse

    printf "MATRIX_URL=http://matrix.%s\nMATRIX_PORT=8008\n" "$RALF_DOMAIN" > /etc/ralf/matrix.env
  '
  si_log "Matrix Synapse in CT ${vmid} bereitgestellt."
}
