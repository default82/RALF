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

if [[ ! -f "$PVE_ENV" ]]; then
  echo "ERROR: Missing $PVE_ENV" >&2
  exit 1
fi

set -a
source "$PVE_ENV"
set +a

echo "[runner] OK: PVE creds loaded (endpoint/token/node)"

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

cd "$RALF_REPO"

for s in $STACKS; do
  dir="$RALF_REPO/stacks/$s"
  [[ -d "$dir" ]] || { echo "ERROR: stack dir not found: $dir" >&2; exit 1; }

  echo
  echo "[runner] === Stack: $s ==="
  cd "$dir"

  # Safety: show what will run
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
