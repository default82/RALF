#!/usr/bin/env bash
set -euo pipefail

# Full cleanroom flow:
# 1) Phase 1 bootstrap (MinIO -> PostgreSQL -> Gitea -> Semaphore)
# 2) Run full platform apply via Semaphore
# 3) Run full platform smoke via Semaphore
#
# Uses GitHub-fetched bootstrap/start.sh in phase1 (same behavior as cleanroom-phase1.sh).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_APPLY="${AUTO_APPLY:-1}"
PROJECT_ID="${PROJECT_ID:-1}"
APPLY_TEMPLATE="${APPLY_TEMPLATE:-RALF Full Platform Apply}"
SMOKE_TEMPLATE="${SMOKE_TEMPLATE:-RALF Full Platform Smoke}"

run_step() {
  printf '\n[cleanroom-full] %s\n' "$1"
}

run_step "phase1 bootstrap + smokes"
AUTO_APPLY="${AUTO_APPLY}" bash "${ROOT_DIR}/bootstrap/cleanroom-phase1.sh"

run_step "semaphore apply: ${APPLY_TEMPLATE}"
"${ROOT_DIR}/bootstrap/sem-run-template.sh" --project-id "${PROJECT_ID}" "${APPLY_TEMPLATE}"

run_step "semaphore smoke: ${SMOKE_TEMPLATE}"
"${ROOT_DIR}/bootstrap/sem-run-template.sh" --project-id "${PROJECT_ID}" "${SMOKE_TEMPLATE}"

run_step "done"
echo "[cleanroom-full] PASS"
