#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

RALF_BASE="${RALF_BASE:-/opt/ralf}"
RALF_REPO="${RALF_REPO:-$RALF_BASE/repo}"
RALF_RUNTIME="${RALF_RUNTIME:-$RALF_BASE/runtime}"

SECRETS="$RALF_RUNTIME/secrets"
PVE_ENV="$SECRETS/pve.env"

echo "[runner] RALF_REPO=$RALF_REPO"
echo "[runner] RALF_RUNTIME=$RALF_RUNTIME"

[[ -f "$PVE_ENV" ]] || {
  echo "ERROR: Missing $PVE_ENV" >&2
  exit 1
}

# Load secrets
set -a
source "$PVE_ENV"
set +a

# Map to OpenTofu variables
export TF_VAR_pm_api_url="${PVE_ENDPOINT}"
export TF_VAR_pm_api_token_id="${PVE_TOKEN_ID}"
export TF_VAR_pm_api_token_secret="${PVE_TOKEN_SECRET}"
export TF_VAR_node_name="${PVE_NODE}"
export TF_VAR_ssh_public_key="$(head -n1 /root/.ssh/authorized_keys)"

echo "[runner] OK: Proxmox credentials loaded"

# ---- Stack control ----
RUN_STACKS="${RUN_STACKS:-1}"
AUTO_APPLY="${AUTO_APPLY:-0}"
STACKS="${STACKS:-030-minio-lxc}"

if [[ "$RUN_STACKS" != "1" ]]; then
  echo "[runner] RUN_STACKS disabled."
  exit 0
fi

cd "$RALF_REPO"

for s in $STACKS; do
  dir="$RALF_REPO/stacks/$s"
  [[ -d "$dir" ]] || {
    echo "ERROR: stack dir not found: $dir" >&2
    exit 1
  }

  echo
  echo "[runner] === Stack: $s ==="
  cd "$dir"

  tofu fmt -recursive
  tofu init -input=false

  if [[ "$AUTO_APPLY" == "1" ]]; then
    tofu apply -auto-approve -input=false
  else
    tofu plan -input=false
  fi

  cd "$RALF_REPO"
done

echo
echo "[runner] Stacks completed."
