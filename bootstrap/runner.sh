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
TFSTATE_ENV="$SECRETS/tfstate.env"

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
if [[ -f /root/.ssh/ralf_ed25519 ]]; then
  export ANSIBLE_PRIVATE_KEY_FILE="/root/.ssh/ralf_ed25519"
fi

TFSTATE_REMOTE_ENABLED=0
if [[ -f "$TFSTATE_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$TFSTATE_ENV"
  set +a
  if [[ "${TFSTATE_ENABLE_REMOTE:-1}" == "1" ]]; then
    TFSTATE_REMOTE_ENABLED=1
  fi
fi

recover_warning_container_create() {
  local dir="$1"
  local res_name vm_id

  res_name="$(grep -hE 'resource[[:space:]]+"proxmox_virtual_environment_container"[[:space:]]+"[^"]+"' "$dir"/*.tf 2>/dev/null \
    | head -n1 \
    | sed -E 's/.*resource[[:space:]]+"proxmox_virtual_environment_container"[[:space:]]+"([^"]+)".*/\1/' || true)"
  vm_id="$(grep -hE '^[[:space:]]*vm_id[[:space:]]*=[[:space:]]*[0-9]+' "$dir"/*.tf 2>/dev/null \
    | head -n1 \
    | sed -E 's/.*vm_id[[:space:]]*=[[:space:]]*([0-9]+).*/\1/' || true)"

  [[ -n "$res_name" && -n "$vm_id" ]] || {
    echo "[runner] Could not detect proxmox container resource/vm_id for warning recovery"
    return 1
  }

  wait_for_ct_existence() {
    local retries="${1:-12}" delay="${2:-5}"
    local api_base
    local i

    if command -v pct >/dev/null 2>&1; then
      for i in $(seq 1 "$retries"); do
        if pct config "$vm_id" >/dev/null 2>&1; then
          return 0
        fi
        sleep "$delay"
      done
      return 1
    fi

    api_base="${PVE_ENDPOINT%/}"
    api_base="${api_base%/api2/json}"
    for i in $(seq 1 "$retries"); do
      if curl -fsS -k \
        -H "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}" \
        "${api_base}/api2/json/nodes/${TF_VAR_node_name}/lxc/${vm_id}/status/current" >/dev/null 2>&1; then
        return 0
      fi
      sleep "$delay"
    done
    return 1
  }

  if ! wait_for_ct_existence 18 5; then
    echo "[runner] Warning recovery skipped: CT $vm_id not found after waiting for async Proxmox create"
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

recover_container_after_apply_failure() {
  local dir="$1" apply_output="$2"
  local _unused="$apply_output"

  # Try import-based recovery unconditionally for Proxmox LXC stacks.
  # If the failure was unrelated, this will simply return non-zero and the
  # original apply failure is preserved.
  recover_warning_container_create "$dir" || return 1
  return 0
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
  for w in $ONLY_STACKS; do
    found=0
    for s in "${stacks[@]}"; do
      if [[ "$s" == "$w" ]]; then
        filtered+=("$s")
        found=1
        break
      fi
    done
    [[ "$found" == "1" ]] || { echo "ERROR: requested stack not found: $w" >&2; exit 1; }
  done
  stacks=("${filtered[@]}")
fi

[[ ${#stacks[@]} -gt 0 ]] || { echo "ERROR: no stacks selected" >&2; exit 1; }

# 4) Skip-Liste (Bootstrap raus)
SKIP_STACKS_REGEX="${SKIP_STACKS_REGEX:-^(100-bootstrap-lxc)$}"
REMOTE_STATE_SKIP_REGEX="${REMOTE_STATE_SKIP_REGEX:-^(030-minio-lxc)$}"

configure_remote_s3_backend() {
  local stack_name="$1"
  local dir="$2"

  cat > "$dir/zz_ralf_backend.auto.tf" <<EOF
terraform {
  backend "s3" {}
}
EOF

  cat > "$dir/.ralf_backend.hcl" <<EOF
bucket = "${TFSTATE_S3_BUCKET}"
key    = "${TFSTATE_S3_PREFIX%/}/${stack_name}/terraform.tfstate"
region = "${TFSTATE_S3_REGION:-us-east-1}"
endpoint = "${TFSTATE_S3_ENDPOINT}"
access_key = "${TFSTATE_S3_ACCESS_KEY}"
secret_key = "${TFSTATE_S3_SECRET_KEY}"
skip_credentials_validation = true
skip_metadata_api_check = true
skip_requesting_account_id = true
skip_region_validation = true
use_path_style = true
encrypt = false
EOF
}

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
    if [[ "$TFSTATE_REMOTE_ENABLED" == "1" && ! "$s" =~ $REMOTE_STATE_SKIP_REGEX ]]; then
      : "${TFSTATE_S3_BUCKET:?missing in tfstate.env}"
      : "${TFSTATE_S3_ENDPOINT:?missing in tfstate.env}"
      : "${TFSTATE_S3_ACCESS_KEY:?missing in tfstate.env}"
      : "${TFSTATE_S3_SECRET_KEY:?missing in tfstate.env}"
      : "${TFSTATE_S3_PREFIX:=ralf}"
      configure_remote_s3_backend "$s" "$dir"
      echo "[runner] Remote S3 backend enabled for $s (${TFSTATE_S3_BUCKET}/${TFSTATE_S3_PREFIX%/}/$s)"
      tofu init -input=false -migrate-state -force-copy -backend-config=.ralf_backend.hcl
    else
      tofu init -input=false
    fi
    if [[ "$AUTO_APPLY" == "1" ]]; then
      apply_output=""
      if ! apply_output="$(tofu apply -auto-approve -input=false 2>&1)"; then
        printf '%s\n' "$apply_output"
        if recover_container_after_apply_failure "$dir" "$apply_output"; then
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
      play_output=""
      played=0
      for attempt in $(seq 1 12); do
        if play_output="$(ansible-playbook -i "$inv" playbook.yml 2>&1)"; then
          printf '%s\n' "$play_output"
          played=1
          break
        fi
        printf '%s\n' "$play_output"
        if grep -q 'UNREACHABLE!' <<<"$play_output" && grep -Eq 'Connection timed out|Connection refused|No route to host' <<<"$play_output"; then
          echo "[runner] Playbook unreachable on attempt ${attempt}; retrying after 5s"
          sleep 5
          continue
        fi
        exit 1
      done
      [[ "$played" == "1" ]] || exit 1
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
