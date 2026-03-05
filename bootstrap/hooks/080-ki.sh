#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/hook_module.sh"

ip_cidr="10.10.90.10/16"

run_standard_lxc_hook \
  "080-ki" "ki" \
  "9010" "ki-svc" "$ip_cidr" "$ip_cidr" \
  "${KI_CORES:-4}" "${KI_MEM_MB:-8192}" "${KI_DISK_GB:-64}" \
  "init_ki_service"