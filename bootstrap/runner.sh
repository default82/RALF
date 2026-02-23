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

[[ -f "$PVE_ENV" ]] || { echo "ERROR: Missing $PVE_ENV" >&2; exit 1; }

set -a
source "$PVE_ENV"
set +a

echo "[runner] OK: Proxmox credentials loaded"

# --- Controls ---
AUTO_APPLY="${AUTO_APPLY:-0}"          # 0=plan, 1=apply
START_AT="${START_AT:-}"               # e.g. "030" (inclusive)
ONLY_STACKS="${ONLY_STACKS:-}"         # e.g. "030-minio-lxc 031-minio-config"
RUN_STACKS="${RUN_STACKS:-1}"          # keep your gate

# --- Export TF_VARs (after sourcing pve.env!) ---
export TF_VAR_pm_api_url="${PVE_ENDPOINT}"
export TF_VAR_pm_api_token_id="${PVE_TOKEN_ID}"
export TF_VAR_pm_api_token_secret="${PVE_TOKEN_SECRET}"
export TF_VAR_node_name="${PVE_NODE}"
export TF_VAR_ssh_public_key="$(awk 'NR==1{print;exit}' /root/.ssh/authorized_keys 2>/dev/null || true)"

if [[ "${RUN_STACKS}" != "1" ]]; then
  echo "[runner] RUN_STACKS!=1 → exit"
  exit 0
fi

cd "$RALF_REPO"

# 1) stacks automatisch finden + sortieren
mapfile -t stacks < <(
  find "$RALF_REPO/stacks" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
  | LC_ALL=C sort
)

# 2) optional: START_AT Filter
if [[ -n "$START_AT" ]]; then
  stacks=( $(printf "%s\n" "${stacks[@]}" | awk -v s="$START_AT" '$0 >= s') )
fi

# 3) optional: ONLY_STACKS Filter (Whitelist)
if [[ -n "$ONLY_STACKS" ]]; then
  # make set for fast-ish match
  want="$ONLY_STACKS"
  filtered=()
  for s in "${stacks[@]}"; do
    for w in $want; do
      [[ "$s" == "$w" ]] && filtered+=("$s")
    done
  done
  stacks=("${filtered[@]}")
fi

[[ ${#stacks[@]} -gt 0 ]] || { echo "ERROR: no stacks selected" >&2; exit 1; }

for s in "${stacks[@]}"; do
  dir="$RALF_REPO/stacks/$s"
  [[ -d "$dir" ]] || { echo "ERROR: stack dir not found: $dir" >&2; exit 1; }

  echo
  echo "[runner] === Stack: $s ==="
  cd "$dir"

  # Stack-Typ erkennen:
  if [[ -f "main.tf" || -f "versions.tf" ]]; then
    tofu init -input=false
    if [[ "$AUTO_APPLY" == "1" ]]; then
      tofu apply -auto-approve -input=false
    else
      tofu plan -input=false
    fi
  elif [[ -f "playbook.yml" || -f "playbook.yaml" ]]; then
    # Beispiel: ansible im Stack-Verzeichnis
    # (Inventory/Vars nach deinem Schema)
    if [[ "$AUTO_APPLY" == "1" ]]; then
      ansible-playbook -i "$RALF_REPO/inventory/hosts.ini" playbook.yml
    else
      ansible-playbook -i "$RALF_REPO/inventory/hosts.ini" --check --diff playbook.yml
    fi
  else
    echo "ERROR: unknown stack type in $dir (no tofu, no playbook)" >&2
    exit 1
  fi

  cd "$RALF_REPO"
done

echo
echo "[runner] Stacks completed."
