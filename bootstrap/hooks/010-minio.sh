#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/service_init.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/hook_module.sh"

ip_cidr="10.10.30.10/16"

run_standard_lxc_hook \
  "010-minio" "minio" \
  "3010" "minio-svc" "$ip_cidr" "$ip_cidr" \
  "${MINIO_CORES:-2}" "${MINIO_MEM_MB:-2048}" "${MINIO_DISK_GB:-32}" \
  "init_minio_service"
