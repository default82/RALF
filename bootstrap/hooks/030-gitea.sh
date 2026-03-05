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

ip_cidr="10.10.40.10/16"

# Load PostgreSQL credentials if available (written by 020-postgresql hook)
CRED_FILE="$runtime_dir/state/postgresql-credentials.env"
if [[ -f "$CRED_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CRED_FILE"
fi

if [[ "$mode" == "plan" ]]; then
  if [[ -n "${POSTGRES_HOST:-}" ]]; then
    hm_log "030-gitea" "PLAN: Gitea würde PostgreSQL-Datenbank verwenden (Host=${POSTGRES_HOST}, DB=${GITEA_DB_NAME:-gitea_db})."
  else
    hm_log "030-gitea" "PLAN: Keine PostgreSQL-Credentials – Gitea würde SQLite verwenden."
  fi
fi

run_standard_lxc_hook \
  "030-gitea" "gitea" \
  "4010" "gitea-svc" "$ip_cidr" "$ip_cidr" \
  "${GITEA_CORES:-2}" "${GITEA_MEM_MB:-2048}" "${GITEA_DISK_GB:-32}" \
  "init_gitea_service" \
  "${RALF_DOMAIN:-otta.zone}" "${POSTGRES_HOST:-}" "${GITEA_DB_USER:-}" "${GITEA_DB_PASS:-}" "${GITEA_DB_NAME:-gitea_db}"
