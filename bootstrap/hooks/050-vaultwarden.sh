#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/hook_module.sh"

ip_cidr="10.10.50.10/16"

run_standard_lxc_hook \
  "050-vaultwarden" "vaultwarden" \
  "5010" "vaultwarden-svc" "$ip_cidr" "$ip_cidr" \
  "${VAULTWARDEN_CORES:-1}" "${VAULTWARDEN_MEM_MB:-512}" "${VAULTWARDEN_DISK_GB:-8}" \
  "init_vaultwarden_service" \
  "${RALF_DOMAIN:-otta.zone}"