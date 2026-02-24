#!/usr/bin/env bash
set -euo pipefail

# "Cleanroom" in this context = fresh bootstrap script fetched from GitHub
# plus a full Phase-1 smoke test afterwards.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AUTO_APPLY="${AUTO_APPLY:-1}" \
START_SCRIPT_MODE=github \
  bash "${ROOT_DIR}/bootstrap/phase1-core.sh"

bash "${ROOT_DIR}/bootstrap/smoke.sh" phase1
