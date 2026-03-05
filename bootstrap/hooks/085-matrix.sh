#!/usr/bin/env bash
set -euo pipefail

log() { printf '[hook:085-matrix] %s\n' "$*"; }
warn() { printf '[hook:085-matrix][warn] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/proxmox_lxc.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"

mode="${RALF_MODE:-plan}"
runtime_dir="${RALF_RUNTIME_DIR:-/opt/ralf/runtime}"
mkdir -p "$runtime_dir/state"

vmid="11010"
hostname="matrix-svc"
ip_cidr="10.10.110.10/16"

gateway="${RALF_GATEWAY:-10.10.0.1}"
bridge="${RALF_BRIDGE:-vmbr0}"
cores="${MATRIX_CORES:-2}"
mem_mb="${MATRIX_MEM_MB:-2048}"
disk_gb="${MATRIX_DISK_GB:-32}"
storage="${RALF_STORAGE:-local-lvm}"
template_storage="${RALF_TEMPLATE_STORAGE:-local}"
template_name="${RALF_TEMPLATE_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
ssh_pubkey_file="${RALF_SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

# Load PostgreSQL credentials (written by 020-postgresql hook)
CRED_FILE="$runtime_dir/state/postgresql-credentials.env"
if [[ -f "$CRED_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CRED_FILE"
else
  warn "PostgreSQL-Credentials fehlen ($CRED_FILE). Matrix Synapse benötigt PostgreSQL."
  if [[ "$mode" == "apply" ]]; then
    exit 1
  fi
fi

if [[ "$mode" == "plan" ]]; then
  log "PLAN: würde Matrix Synapse LXC erstellen/abgleichen (CTID=$vmid, IP=$ip_cidr)."
  if [[ -n "${POSTGRES_HOST:-}" ]]; then
    log "PLAN: Matrix Synapse würde PostgreSQL verwenden (Host=${POSTGRES_HOST}, DB=${MATRIX_DB_NAME:-synapse_db})."
  else
    warn "PLAN: Keine PostgreSQL-Credentials – Matrix Synapse kann nicht konfiguriert werden."
  fi
  log "PLAN: Matrix Synapse Client-API Port: 8008."
  command -v pct >/dev/null 2>&1 || { warn "pct fehlt"; exit 1; }
  if pct status "$vmid" >/dev/null 2>&1; then
    log "PLAN: CT $vmid existiert bereits."
  else
    log "PLAN: CT $vmid fehlt und würde erstellt werden."
  fi
else
  ensure_lxc "$vmid" "$hostname" "$ip_cidr" "$gateway" "$bridge" "$cores" "$mem_mb" "$disk_gb" "$storage" "$template_storage" "$template_name" "$ssh_pubkey_file"
  init_matrix_service "$vmid" "${RALF_DOMAIN:-otta.zone}" \
    "${POSTGRES_HOST:-}" "${MATRIX_DB_USER:-}" "${MATRIX_DB_PASS:-}" "${MATRIX_DB_NAME:-synapse_db}"
  log "APPLY: Matrix Synapse LXC bereitgestellt."
fi

echo "matrix_ctid=$vmid" > "$runtime_dir/state/matrix.state"
echo "matrix_ip=${ip_cidr%%/*}" >> "$runtime_dir/state/matrix.state"
