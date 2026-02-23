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
# shellcheck disable=SC1090
source "$PVE_ENV"
set +a

echo "[runner] OK: Proxmox credentials loaded"

# --- Controls ---
AUTO_APPLY="${AUTO_APPLY:-0}"          # 0=plan/syntax-check, 1=apply/run
START_AT="${START_AT:-}"               # e.g. "030" (inclusive)
ONLY_STACKS="${ONLY_STACKS:-}"         # e.g. "030-minio-lxc 031-minio-config"
RUN_STACKS="${RUN_STACKS:-1}"

# --- Export TF_VARs ---
: "${PVE_ENDPOINT:?missing in pve.env}"
: "${PVE_TOKEN_ID:?missing in pve.env}"
: "${PVE_TOKEN_SECRET:?missing in pve.env}"
: "${PVE_NODE:?missing in pve.env}"

export TF_VAR_pm_api_url="${PVE_ENDPOINT}"
export TF_VAR_pm_api_token_id="${PVE_TOKEN_ID}"
export TF_VAR_pm_api_token_secret="${PVE_TOKEN_SECRET}"
export TF_VAR_node_name="${PVE_NODE}"
export TF_VAR_ssh_public_key="$(awk 'NR==1{print;exit}' /root/.ssh/authorized_keys 2>/dev/null || true)"

recover_warning_container_create() {
  local dir="$1"
  local res_name vm_id

  res_name="$(awk 'match($0, /resource[[:space:]]+"proxmox_virtual_environment_container"[[:space:]]+"([^"]+)"/, m) { print m[1]; exit }' "$dir"/*.tf 2>/dev/null || true)"
  vm_id="$(awk 'match($0, /vm_id[[:space:]]*=[[:space:]]*([0-9]+)/, m) { print m[1]; exit }' "$dir"/*.tf 2>/dev/null || true)"

  [[ -n "$res_name" && -n "$vm_id" ]] || {
    echo "[runner] Could not detect proxmox container resource/vm_id for warning recovery"
    return 1
  }

  if ! pct config "$vm_id" >/dev/null 2>&1; then
    echo "[runner] Warning recovery skipped: CT $vm_id does not exist on host"
    return 1
  fi

  echo "[runner] CT $vm_id exists despite warning; trying tofu import for proxmox_virtual_environment_container.$res_name"

  local addr="proxmox_virtual_environment_container.$res_name"
  local import_id
  for import_id in "$vm_id" "${TF_VAR_node_name}/${vm_id}" "${TF_VAR_node_name}/lxc/${vm_id}"; do
    if tofu import -input=false "$addr" "$import_id" >/dev/null 2>&1; then
      echo "[runner] Imported $addr using id '$import_id'"
      return 0
    fi
  done

  echo "[runner] Failed to import $addr after warning"
  return 1
}

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
  mapfile -t stacks < <(printf "%s\n" "${stacks[@]}" | awk -v s="$START_AT" '$0 >= s')
fi

# 3) optional: ONLY_STACKS Filter
if [[ -n "$ONLY_STACKS" ]]; then
  filtered=()
  for s in "${stacks[@]}"; do
    for w in $ONLY_STACKS; do
      [[ "$s" == "$w" ]] && filtered+=("$s")
    done
  done
  stacks=("${filtered[@]}")
fi

[[ ${#stacks[@]} -gt 0 ]] || { echo "ERROR: no stacks selected" >&2; exit 1; }

# 4) Skip-Liste (Bootstrap raus)
SKIP_STACKS_REGEX="${SKIP_STACKS_REGEX:-^(100-bootstrap-lxc)$}"

for s in "${stacks[@]}"; do
  if [[ "$s" =~ $SKIP_STACKS_REGEX ]]; then
    echo "[runner] Skipping stack: $s (matches SKIP_STACKS_REGEX)"
    continue
  fi

  dir="$RALF_REPO/stacks/$s"
  [[ -d "$dir" ]] || { echo "ERROR: stack dir not found: $dir" >&2; exit 1; }

  echo
  echo "[runner] === Stack: $s ==="
  cd "$dir"

  if [[ -f "main.tf" || -f "versions.tf" ]]; then
    tofu init -input=false
    if [[ "$AUTO_APPLY" == "1" ]]; then
      apply_output=""
      if ! apply_output="$(tofu apply -auto-approve -input=false 2>&1)"; then
        printf '%s\n' "$apply_output"
        if grep -q "exit code: WARNINGS: 1" <<<"$apply_output" && recover_warning_container_create "$dir"; then
          tofu apply -auto-approve -input=false
        else
          exit 1
        fi
      else
        printf '%s\n' "$apply_output"
      fi
    else
      tofu plan -input=false
    fi

  elif [[ -f "playbook.yml" || -f "playbook.yaml" ]]; then
    inv="$RALF_REPO/inventory/hosts.ini"
    [[ -f "$inv" ]] || { echo "ERROR: missing inventory: $inv" >&2; exit 1; }

    if [[ "$AUTO_APPLY" == "1" ]]; then
      ansible-playbook -i "$inv" playbook.yml
    else
      echo "[runner] AUTO_APPLY=0 → ansible remote run skipped; running syntax-check only"
      ansible-playbook -i "$inv" --syntax-check playbook.yml
    fi

  else
    echo "ERROR: unknown stack type in $dir (no tofu, no playbook)" >&2
    exit 1
  fi

  cd "$RALF_REPO"
done

echo
echo "[runner] Stacks completed."
