#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/hook_module.sh"

ip_cidr="10.10.100.10/16"

run_standard_lxc_hook \
  "040-semaphore" "semaphore" \
  "10010" "semaphore-svc" "$ip_cidr" "$ip_cidr" \
  "${SEMAPHORE_CORES:-2}" "${SEMAPHORE_MEM_MB:-2048}" "${SEMAPHORE_DISK_GB:-32}" \
  "init_semaphore_service" \
  "${RALF_DOMAIN:-otta.zone}"
