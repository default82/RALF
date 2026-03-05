#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/hook_module.sh"

mode="$(hm_mode)"
runtime_dir="$(hm_runtime_dir)"
mkdir -p "$runtime_dir/state"

ip_cidr="10.10.20.10/16"
postgres_host="${ip_cidr%%/*}"

# Generate or load per-service DB credentials (idempotent)
CRED_FILE="$runtime_dir/state/postgresql-credentials.env"
if [[ ! -f "$CRED_FILE" ]]; then
  gen_pass() {
    local p
    p="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')"
    printf '%s' "${p:0:32}"
  }
  _gitea_pass="$(gen_pass)"
  _n8n_pass="$(gen_pass)"
  _matrix_pass="$(gen_pass)"
  cat > "$CRED_FILE" <<CREDS
POSTGRES_HOST="${postgres_host}"
POSTGRES_PORT="5432"
GITEA_DB_USER="gitea"
GITEA_DB_PASS="${_gitea_pass}"
GITEA_DB_NAME="gitea_db"
N8N_DB_USER="n8n"
N8N_DB_PASS="${_n8n_pass}"
N8N_DB_NAME="n8n_db"
MATRIX_DB_USER="synapse"
MATRIX_DB_PASS="${_matrix_pass}"
MATRIX_DB_NAME="synapse_db"
CREDS
  chmod 600 "$CRED_FILE"
  hm_log "020-postgresql" "Datenbank-Credentials generiert: $CRED_FILE"
fi
# shellcheck disable=SC1090
source "$CRED_FILE"

if [[ "$mode" == "plan" ]]; then
  hm_log "020-postgresql" "PLAN: würde Datenbanken erstellen für: ralf_db, ${GITEA_DB_NAME}, ${N8N_DB_NAME}, ${MATRIX_DB_NAME}."
  hm_log "020-postgresql" "PLAN: PostgreSQL würde Netzwerkzugriff aus 10.10.0.0/16 erlauben."
fi

run_standard_lxc_hook \
  "020-postgresql" "postgresql" \
  "2010" "postgres-svc" "$ip_cidr" "$postgres_host" \
  "${POSTGRES_CORES:-2}" "${POSTGRES_MEM_MB:-2048}" "${POSTGRES_DISK_GB:-32}" \
  "init_postgresql_service"
