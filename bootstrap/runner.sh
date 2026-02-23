#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

# --- Defaults (runner must be self-contained) ---
RALF_BASE="${RALF_BASE:-/opt/ralf}"
RALF_REPO="${RALF_REPO:-$RALF_BASE/repo}"
RALF_RUNTIME="${RALF_RUNTIME:-$RALF_BASE/runtime}"

SECRETS="${SECRETS:-$RALF_RUNTIME/secrets}"
PVE_ENV="${PVE_ENV:-$SECRETS/pve.env}"

echo "[runner] RALF_REPO=$RALF_REPO"
echo "[runner] RALF_RUNTIME=$RALF_RUNTIME"

# --- Load secrets early (before referencing PVE_*) ---
if [[ ! -f "$PVE_ENV" ]]; then
  echo "ERROR: Missing $PVE_ENV" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$PVE_ENV"
set +a

# --- Validate required vars (nice errors) ---
: "${PVE_ENDPOINT:?missing in $PVE_ENV}"
: "${PVE_TOKEN_ID:?missing in $PVE_ENV}"
: "${PVE_TOKEN_SECRET:?missing in $PVE_ENV}"
: "${PVE_NODE:?missing in $PVE_ENV}"

echo "[runner] OK: PVE creds loaded (endpoint/token/node)"

# --- Export TF_VAR_* after secrets are loaded ---
export TF_VAR_pm_api_url="$PVE_ENDPOINT"
export TF_VAR_pm_api_token_id="$PVE_TOKEN_ID"
export TF_VAR_pm_api_token_secret="$PVE_TOKEN_SECRET"
export TF_VAR_node_name="$PVE_NODE"

# SSH key: take first key line if available
if [[ -f /root/.ssh/authorized_keys ]]; then
  TF_VAR_ssh_public_key="$(grep -m1 -E '^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp)' /root/.ssh/authorized_keys || true)"
  export TF_VAR_ssh_public_key="${TF_VAR_ssh_public_key:-}"
fi

# --- Control flags ---
RUN_STACKS="${RUN_STACKS:-0}"
AUTO_APPLY="${AUTO_APPLY:-0}"
STACKS="${STACKS:-}"

if [[ "$RUN_STACKS" != "1" ]]; then
  echo
  echo "[runner] Next: we will run tofu to provision minio/postgres/gitea/semaphore"
  echo "         and use MinIO as remote state as soon as MinIO is up."
  exit 0
fi

[[ -n "$STACKS" ]] || { echo "ERROR: RUN_STACKS=1 but STACKS is empty" >&2; exit 1; }
[[ -d "$RALF_REPO" ]] || { echo "ERROR: RALF_REPO not found: $RALF_REPO" >&2; exit 1; }

cd "$RALF_REPO"

for s in $STACKS; do
  dir="$RALF_REPO/stacks/$s"
  [[ -d "$dir" ]] || { echo "ERROR: stack dir not found: $dir" >&2; exit 1; }

  echo
  echo "[runner] === Stack: $s ==="
  cd "$dir"

  echo "[runner] pwd=$(pwd)"
  echo "[runner] AUTO_APPLY=$AUTO_APPLY"

  tofu init -input=false

  if [[ "$AUTO_APPLY" == "1" ]]; then
    tofu apply -auto-approve -input=false
  else
    tofu plan -input=false
  fi

  cd "$RALF_REPO"
done

echo
echo "[runner] Done stacks."
