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

ip_cidr="10.10.100.20/16"

# Load PostgreSQL credentials if available (written by 020-postgresql hook)
CRED_FILE="$runtime_dir/state/postgresql-credentials.env"
if [[ -f "$CRED_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CRED_FILE"
fi

if [[ "$mode" == "plan" ]]; then
  if [[ -n "${POSTGRES_HOST:-}" ]]; then
    hm_log "070-n8n" "PLAN: n8n würde PostgreSQL-Datenbank verwenden (Host=${POSTGRES_HOST}, DB=${N8N_DB_NAME:-n8n_db})."
  else
    hm_log "070-n8n" "PLAN: Keine PostgreSQL-Credentials – n8n würde SQLite verwenden."
  fi
fi

run_standard_lxc_hook \
  "070-n8n" "n8n" \
  "10020" "n8n-svc" "$ip_cidr" "$ip_cidr" \
  "${N8N_CORES:-2}" "${N8N_MEM_MB:-2048}" "${N8N_DISK_GB:-16}" \
  "init_n8n_service" \
  "${RALF_DOMAIN:-otta.zone}" "${POSTGRES_HOST:-}" "${N8N_DB_USER:-}" "${N8N_DB_PASS:-}" "${N8N_DB_NAME:-n8n_db}"