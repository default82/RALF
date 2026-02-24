#!/usr/bin/env bash
set -euo pipefail

# Phase 1 (bootstrap -> handover):
# 1) MinIO (remote state)
# 2) PostgreSQL
# 3) Gitea
# 4) Semaphore (toolchain + wrappers for further runs)

AUTO_APPLY="${AUTO_APPLY:-1}"
START_SCRIPT_MODE="${START_SCRIPT_MODE:-local}" # local|github
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START_SCRIPT_LOCAL="${ROOT_DIR}/bootstrap/start.sh"
SMOKE_LOCAL="${ROOT_DIR}/bootstrap/smoke.sh"

run_start() {
  local stacks="$1"
  echo
  echo "[phase1] run stacks: ${stacks}"
  if [[ "$START_SCRIPT_MODE" == "github" ]]; then
    AUTO_APPLY="${AUTO_APPLY}" START_AT=000 ONLY_STACKS="${stacks}" \
      bash <(curl -fsSL "https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh?nocache=$(date +%s)")
  else
    AUTO_APPLY="${AUTO_APPLY}" START_AT=000 ONLY_STACKS="${stacks}" \
      bash "${START_SCRIPT_LOCAL}"
  fi
}

run_smoke() {
  local target="$1"
  echo
  echo "[phase1] smoke: ${target}"
  bash "${SMOKE_LOCAL}" "${target}"
}

run_start "030-minio-lxc 031-minio-config"
run_smoke minio

run_start "020-postgres-lxc 021-postgres-config"
run_smoke postgres

run_start "034-gitea-lxc 035-gitea-config"
run_smoke gitea

run_start "040-semaphore-lxc 041-semaphore-config"
run_smoke semaphore

echo
echo "[phase1] full smoke"
run_smoke phase1
echo "[phase1] phase1 complete"
