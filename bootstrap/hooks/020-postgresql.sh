#!/usr/bin/env bash
set -euo pipefail

log() { printf '[hook:020-postgresql] %s\n' "$*"; }
warn() { printf '[hook:020-postgresql][warn] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/proxmox_lxc.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"

mode="${RALF_MODE:-plan}"
runtime_dir="${RALF_RUNTIME_DIR:-/opt/ralf/runtime}"
mkdir -p "$runtime_dir/state"

vmid="2010"
hostname="postgres-svc"
ip_cidr="10.10.20.10/16"
postgres_host="${ip_cidr%%/*}"

gateway="${RALF_GATEWAY:-10.10.0.1}"
bridge="${RALF_BRIDGE:-vmbr0}"
cores="${POSTGRES_CORES:-2}"
mem_mb="${POSTGRES_MEM_MB:-2048}"
disk_gb="${POSTGRES_DISK_GB:-32}"
storage="${RALF_STORAGE:-local-lvm}"
template_storage="${RALF_TEMPLATE_STORAGE:-local}"
template_name="${RALF_TEMPLATE_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
ssh_pubkey_file="${RALF_SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

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
  log "Datenbank-Credentials generiert: $CRED_FILE"
fi
# shellcheck disable=SC1090
source "$CRED_FILE"

if [[ "$mode" == "plan" ]]; then
  log "PLAN: würde PostgreSQL LXC erstellen/abgleichen (CTID=$vmid, IP=$ip_cidr)."
  log "PLAN: würde Datenbanken erstellen für: ralf_db, ${GITEA_DB_NAME}, ${N8N_DB_NAME}, ${MATRIX_DB_NAME}."
  log "PLAN: PostgreSQL würde Netzwerkzugriff aus 10.10.0.0/16 erlauben."
  command -v pct >/dev/null 2>&1 || { warn "pct fehlt"; exit 1; }
  if pct status "$vmid" >/dev/null 2>&1; then
    log "PLAN: CT $vmid existiert bereits."
  else
    log "PLAN: CT $vmid fehlt und würde erstellt werden."
  fi
else
  ensure_lxc "$vmid" "$hostname" "$ip_cidr" "$gateway" "$bridge" "$cores" "$mem_mb" "$disk_gb" "$storage" "$template_storage" "$template_name" "$ssh_pubkey_file"
  init_postgresql_service "$vmid"
  log "APPLY: PostgreSQL LXC bereitgestellt."
fi

echo "postgres_ctid=$vmid" > "$runtime_dir/state/postgresql.state"
echo "postgres_ip=${postgres_host}" >> "$runtime_dir/state/postgresql.state"
