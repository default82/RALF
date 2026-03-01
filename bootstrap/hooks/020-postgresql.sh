#!/usr/bin/env bash
set -euo pipefail

log() { printf '[hook:020-postgresql] %s\n' "$*"; }
warn() { printf '[hook:020-postgresql][warn] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/proxmox_lxc.sh"

mode="${RALF_MODE:-plan}"
runtime_dir="${RALF_RUNTIME_DIR:-/opt/ralf/runtime}"
mkdir -p "$runtime_dir/state"

vmid="2010"
hostname="postgres-ops"
ip_cidr="10.10.20.10/16"

gateway="${RALF_GATEWAY:-10.10.0.1}"
bridge="${RALF_BRIDGE:-vmbr0}"
cores="${POSTGRES_CORES:-2}"
mem_mb="${POSTGRES_MEM_MB:-2048}"
disk_gb="${POSTGRES_DISK_GB:-32}"
storage="${RALF_STORAGE:-local-lvm}"
template_storage="${RALF_TEMPLATE_STORAGE:-local}"
template_name="${RALF_TEMPLATE_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
ssh_pubkey_file="${RALF_SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

if [[ "$mode" == "plan" ]]; then
  log "PLAN: würde PostgreSQL LXC erstellen/abgleichen (CTID=$vmid, IP=$ip_cidr)."
  command -v pct >/dev/null 2>&1 || { warn "pct fehlt"; exit 1; }
  if pct status "$vmid" >/dev/null 2>&1; then
    log "PLAN: CT $vmid existiert bereits."
  else
    log "PLAN: CT $vmid fehlt und würde erstellt werden."
  fi
else
  ensure_lxc "$vmid" "$hostname" "$ip_cidr" "$gateway" "$bridge" "$cores" "$mem_mb" "$disk_gb" "$storage" "$template_storage" "$template_name" "$ssh_pubkey_file"
  log "APPLY: PostgreSQL LXC bereitgestellt."
fi

echo "postgres_ctid=$vmid" > "$runtime_dir/state/postgresql.state"
echo "postgres_ip=$ip_cidr" >> "$runtime_dir/state/postgresql.state"
