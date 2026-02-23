#!/usr/bin/env bash
set -euo pipefail

RALF_REPO="${RALF_REPO:-/opt/ralf/repo}"
RALF_RUNTIME="${RALF_RUNTIME:-/opt/ralf/runtime}"

RUN_STACKS="${RUN_STACKS:-1}"
AUTO_APPLY="${AUTO_APPLY:-0}"
STACKS="${STACKS:-030-minio-lxc}"

echo "[runner] RALF_REPO=${RALF_REPO}"
echo "[runner] RALF_RUNTIME=${RALF_RUNTIME}"

PVE_ENV="${RALF_RUNTIME}/secrets/pve.env"
if [[ ! -f "$PVE_ENV" ]]; then
  echo "[runner] ERROR: missing PVE env at $PVE_ENV" >&2
  exit 1
fi

set -a
source "$PVE_ENV"
set +a

export TF_VAR_pve_endpoint="${PVE_ENDPOINT}"
export TF_VAR_pve_token_id="${PVE_TOKEN_ID}"
export TF_VAR_pve_token_secret="${PVE_TOKEN_SECRET}"
export TF_VAR_pve_node="${PVE_NODE}"

run_stack() {
  local stack="$1"
  local dir="${RALF_REPO}/stacks/${stack}"

  if [[ ! -d "$dir" ]]; then
    echo "[runner] ERROR: stack not found: $dir" >&2
    exit 1
  fi

  echo
  echo "[runner] === stack: ${stack} ==="
  cd "$dir"

  tofu init -upgrade
  tofu plan

  if [[ "$AUTO_APPLY" == "1" ]]; then
    tofu apply -auto-approve
  else
    echo "[runner] AUTO_APPLY=0 -> skipping apply"
  fi
}

if [[ "$RUN_STACKS" == "1" ]]; then
  for s in $STACKS; do
    run_stack "$s"
  done
else
  echo "[runner] RUN_STACKS=0 -> skipping stacks"
fi

echo
echo "[runner] done"
