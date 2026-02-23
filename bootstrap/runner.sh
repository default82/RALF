#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

RALF_BASE="${RALF_BASE:-/opt/ralf}"
RALF_REPO="${RALF_REPO:-$RALF_BASE/repo}"
RALF_RUNTIME="${RALF_RUNTIME:-$RALF_BASE/runtime}"

echo "[runner] RALF_REPO=$RALF_REPO"
echo "[runner] RALF_RUNTIME=$RALF_RUNTIME"

SECRETS="$RALF_RUNTIME/secrets"
PVE_ENV="$SECRETS/pve.env"

if [[ ! -f "$PVE_ENV" ]]; then
  cat >&2 <<'EOF'
ERROR: Missing /opt/ralf/runtime/secrets/pve.env

Create it like:
  cat >/opt/ralf/runtime/secrets/pve.env <<ENV
  PVE_ENDPOINT=https://10.10.10.10:8006
  PVE_TOKEN_ID="root@pam!ralf"
  PVE_TOKEN_SECRET="xxxx"
  PVE_NODE="pve-deploy"
  ENV
  chmod 600 /opt/ralf/runtime/secrets/pve.env

Then rerun runner.sh
EOF
  exit 1
fi

set -a
source "$PVE_ENV"
set +a

echo "[runner] OK: PVE creds loaded (endpoint/token/node)"

echo
echo "[runner] Next: we will run tofu to provision minio/postgres/gitea/semaphore"
echo "         and use MinIO as remote state as soon as MinIO is up."
