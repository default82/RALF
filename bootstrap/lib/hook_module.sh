#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/proxmox_lxc.sh"

hm_log() {
  local tag="$1"
  shift
  printf '[hook:%s] %s\n' "$tag" "$*"
}

hm_warn() {
  local tag="$1"
  shift
  printf '[hook:%s][warn] %s\n' "$tag" "$*" >&2
}

hm_runtime_dir() {
  printf '%s' "${RALF_RUNTIME_DIR:-/opt/ralf/runtime}"
}

hm_mode() {
  printf '%s' "${RALF_MODE:-plan}"
}

hm_plan_ct() {
  local tag="$1"
  local vmid="$2"
  local ip_cidr="$3"

  hm_log "$tag" "PLAN: würde LXC erstellen/abgleichen (CTID=$vmid, IP=$ip_cidr)."
  command -v pct >/dev/null 2>&1 || {
    hm_warn "$tag" "pct fehlt"
    return 1
  }

  if pct status "$vmid" >/dev/null 2>&1; then
    hm_log "$tag" "PLAN: CT $vmid existiert bereits."
  else
    hm_log "$tag" "PLAN: CT $vmid fehlt und würde erstellt werden."
  fi
}

hm_write_state_file() {
  local runtime_dir="$1"
  local state_name="$2"
  local vmid="$3"
  local state_ip="$4"

  mkdir -p "$runtime_dir/state"
  {
    printf '%s_ctid=%s\n' "$state_name" "$vmid"
    printf '%s_ip=%s\n' "$state_name" "$state_ip"
  } > "$runtime_dir/state/${state_name}.state"
}

# Usage:
# run_standard_lxc_hook <hook_tag> <state_name> <vmid> <hostname> <ip_cidr> <state_ip> <cores> <mem_mb> <disk_gb> <init_function|-> [init_args...]
run_standard_lxc_hook() {
  if [[ "$#" -lt 10 ]]; then
    printf '[hook-module][error] run_standard_lxc_hook requires at least 10 arguments\n' >&2
    return 2
  fi

  local tag="$1"
  local state_name="$2"
  local vmid="$3"
  local hostname="$4"
  local ip_cidr="$5"
  local state_ip="$6"
  local cores="$7"
  local mem_mb="$8"
  local disk_gb="$9"
  local init_fn="${10}"
  shift 10

  local mode runtime_dir
  mode="$(hm_mode)"
  runtime_dir="$(hm_runtime_dir)"

  local gateway bridge storage template_storage template_name ssh_pubkey_file
  gateway="${RALF_GATEWAY:-10.10.0.1}"
  bridge="${RALF_BRIDGE:-vmbr0}"
  storage="${RALF_STORAGE:-local-lvm}"
  template_storage="${RALF_TEMPLATE_STORAGE:-local}"
  template_name="${RALF_TEMPLATE_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
  ssh_pubkey_file="${RALF_SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

  if [[ "$mode" == "plan" ]]; then
    hm_plan_ct "$tag" "$vmid" "$ip_cidr"
  else
    ensure_lxc "$vmid" "$hostname" "$ip_cidr" "$gateway" "$bridge" "$cores" "$mem_mb" "$disk_gb" "$storage" "$template_storage" "$template_name" "$ssh_pubkey_file"

    if [[ "$init_fn" != "-" ]]; then
      if [[ "$(type -t "$init_fn" || true)" != "function" ]]; then
        hm_warn "$tag" "Init-Funktion '$init_fn' ist nicht definiert."
        return 1
      fi
      "$init_fn" "$vmid" "$@"
    fi

    hm_log "$tag" "APPLY: Service-LXC bereitgestellt."
  fi

  hm_write_state_file "$runtime_dir" "$state_name" "$vmid" "$state_ip"
}
