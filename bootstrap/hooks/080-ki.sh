#!/usr/bin/env bash
set -euo pipefail

log() { printf '[hook:080-ki] %s\n' "$*"; }
warn() { printf '[hook:080-ki][warn] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/proxmox_lxc.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"

mode="${RALF_MODE:-plan}"
runtime_dir="${RALF_RUNTIME_DIR:-/opt/ralf/runtime}"
mkdir -p "$runtime_dir/state"

vmid="9010"
hostname="ki-svc"
ip_cidr="10.10.90.10/16"

gateway="${RALF_GATEWAY:-10.10.0.1}"
bridge="${RALF_BRIDGE:-vmbr0}"
cores="${KI_CORES:-4}"
mem_mb="${KI_MEM_MB:-8192}"
disk_gb="${KI_DISK_GB:-64}"
storage="${RALF_STORAGE:-local-lvm}"
template_storage="${RALF_TEMPLATE_STORAGE:-local}"
template_name="${RALF_TEMPLATE_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
ssh_pubkey_file="${RALF_SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

if [[ "$mode" == "plan" ]]; then
  log "PLAN: würde KI-Instanz LXC erstellen/abgleichen (CTID=$vmid, IP=$ip_cidr)."
  command -v pct >/dev/null 2>&1 || { warn "pct fehlt"; exit 1; }
  if pct status "$vmid" >/dev/null 2>&1; then
    log "PLAN: CT $vmid existiert bereits."
  else
    log "PLAN: CT $vmid fehlt und würde erstellt werden."
  fi
else
  ensure_lxc "$vmid" "$hostname" "$ip_cidr" "$gateway" "$bridge" "$cores" "$mem_mb" "$disk_gb" "$storage" "$template_storage" "$template_name" "$ssh_pubkey_file"
  init_ki_service "$vmid"
  log "APPLY: KI-Instanz LXC bereitgestellt."
fi

echo "ki_ctid=$vmid" > "$runtime_dir/state/ki.state"
echo "ki_ip=$ip_cidr" >> "$runtime_dir/state/ki.state"