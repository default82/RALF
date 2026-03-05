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

ip_cidr="10.10.110.10/16"

# Load PostgreSQL credentials (written by 020-postgresql hook)
CRED_FILE="$runtime_dir/state/postgresql-credentials.env"
if [[ -f "$CRED_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CRED_FILE"
else
  hm_warn "085-matrix" "PostgreSQL-Credentials fehlen ($CRED_FILE). Matrix Synapse benötigt PostgreSQL."
  if [[ "$mode" == "apply" ]]; then
    exit 1
  fi
fi

if [[ "$mode" == "plan" ]]; then
  if [[ -n "${POSTGRES_HOST:-}" ]]; then
    hm_log "085-matrix" "PLAN: Matrix Synapse würde PostgreSQL verwenden (Host=${POSTGRES_HOST}, DB=${MATRIX_DB_NAME:-synapse_db})."
  else
    hm_warn "085-matrix" "PLAN: Keine PostgreSQL-Credentials – Matrix Synapse kann nicht konfiguriert werden."
  fi
  hm_log "085-matrix" "PLAN: Matrix Synapse Client-API Port: 8008."
fi

run_standard_lxc_hook \
  "085-matrix" "matrix" \
  "11010" "matrix-svc" "$ip_cidr" "${ip_cidr%%/*}" \
  "${MATRIX_CORES:-2}" "${MATRIX_MEM_MB:-2048}" "${MATRIX_DISK_GB:-32}" \
  "init_matrix_service" \
  "${RALF_DOMAIN:-otta.zone}" "${POSTGRES_HOST:-}" "${MATRIX_DB_USER:-}" "${MATRIX_DB_PASS:-}" "${MATRIX_DB_NAME:-synapse_db}"
