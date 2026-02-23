#!/usr/bin/env bash
set -euo pipefail

RALF_REPO="${RALF_REPO:-/opt/ralf/repo}"
RALF_RUNTIME="${RALF_RUNTIME:-/opt/ralf/runtime}"

RUN_STACKS="${RUN_STACKS:-1}"     # 1=Stacks laufen lassen
AUTO_APPLY="${AUTO_APPLY:-0}"     # 0=plan only, 1=apply
STACKS="${STACKS:-030-minio-lxc}" # später erweitern: "030-minio-lxc 040-postgres-lxc ..."

echo "[runner] RALF_REPO=${RALF_REPO}"
echo "[runner] RALF_RUNTIME=${RALF_RUNTIME}"

PVE_ENV="${PVE_ENV:-${RALF_RUNTIME}/secrets/pve.env}"
if [[ ! -f "$PVE_ENV" ]]; then
  echo "[runner] ERROR: missing PVE env at $PVE_ENV" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$PVE_ENV"
set +a

# Optional: export TF_VAR_… aus pve.env (falls du es so halten willst)
# (Besser ist: tofu vars über *.tfvars oder env mapping im Stack sauber machen.)
export TF_VAR_pve_endpoint="${PVE_ENDPOINT:-}"
export TF_VAR_pve_token_id="${PVE_TOKEN_ID:-}"
export TF_VAR_pve_token_secret="${PVE_TOKEN_SECRET:-}"
export TF_VAR_pve_node="${PVE_NODE:-}"

run_stack() {
  local name="$1"
  local dir="${RALF_REPO}/stacks/${name}"
  [[ -d "$dir" ]] || { echo "[runner] ERROR: stack not found: $dir" >&2; exit 1; }

  echo "[runner] === stack: ${name} ==="
  cd "$dir"

  tofu init -upgrade
  tofu fmt -check >/dev/null 2>&1 || true

  tofu plan

  if [[ "$AUTO_APPLY" == "1" ]]; then
    tofu apply -auto-approve
  else
    echo "[runner] AUTO_APPLY=0 -> skipping apply for ${name}"
  fi
}

if [[ "$RUN_STACKS" == "1" ]]; then
  for s in $STACKS; do
    run_stack "$s"
  done
else
  echo "[runner] RUN_STACKS=0 -> skipping stacks"
fi

echo "[runner] done"
