#!/usr/bin/env bash
set -euo pipefail

# Conservative LXD adapter for `ralf bootstrap`.
# Behavior:
# - validates `lxc`
# - checks if instance exists
# - creates it if missing (explicitly called only via `ralf bootstrap --apply`)
# - stamps safe metadata (`user.ralf.*`) idempotently for traceability
# - writes outputs/lxd_apply_report.json

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
outputs_dir="${OUTPUTS_DIR:-${repo_root}/outputs}"
mkdir -p "$outputs_dir"
artifacts_dir="${outputs_dir}/lxd"
mkdir -p "$artifacts_dir"

name="${CT_HOSTNAME:-ralf-bootstrap}"
image="${LXD_IMAGE:-images:ubuntu/24.04}"
lxd_profile="${LXD_PROFILE:-default}"
config_changed=0
config_error=""
metadata_preview_file="${artifacts_dir}/lxd-metadata-targets.json"
metadata_applied_file="${artifacts_dir}/lxd-metadata-applied.json"
plan_file="${artifacts_dir}/lxd-plan.md"
instance_state="unknown"

write_artifacts() {
  cat > "$metadata_preview_file" <<EOF
{
  "instance_name": "$(json_escape "$name")",
  "image": "$(json_escape "$image")",
  "profile": "$(json_escape "$lxd_profile")",
  "metadata": {
    "user.ralf.profile": "$(json_escape "${PROFILE:-}")",
    "user.ralf.base_domain": "$(json_escape "${BASE_DOMAIN:-}")",
    "user.ralf.network_cidr": "$(json_escape "${NETWORK_CIDR:-}")",
    "user.ralf.managed": "true"
  }
}
EOF

  cat > "$plan_file" <<EOF
# LXD Bootstrap Plan (Conservative)

- Instance: \`${name}\`
- Image: \`${image}\`
- Profile: \`${lxd_profile}\`
- Outputs dir: \`${outputs_dir}\`
- Metadata preview: \`${metadata_preview_file}\`
- Metadata applied: \`${metadata_applied_file}\`

## Behavior
- Validate \`lxc\` client and LXD reachability
- Create instance only if missing
- Stamp \`user.ralf.*\` metadata idempotently
- No destructive changes
EOF
}

write_applied_metadata() {
  cat > "$metadata_applied_file" <<EOF
{
  "instance_name": "$(json_escape "$name")",
  "instance_state": "$(json_escape "$instance_state")",
  "metadata": {
    "user.ralf.profile": "$(json_escape "$(lxc config get "$name" "user.ralf.profile" 2>/dev/null || true)")",
    "user.ralf.base_domain": "$(json_escape "$(lxc config get "$name" "user.ralf.base_domain" 2>/dev/null || true)")",
    "user.ralf.network_cidr": "$(json_escape "$(lxc config get "$name" "user.ralf.network_cidr" 2>/dev/null || true)")",
    "user.ralf.managed": "$(json_escape "$(lxc config get "$name" "user.ralf.managed" 2>/dev/null || true)")"
  }
}
EOF
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

write_report() {
  local status="$1" message="$2" created="$3" exists="$4" lxc_version="${5:-}"
  cat > "${outputs_dir}/lxd_apply_report.json" <<EOF
{
  "provisioner": "lxd",
  "status": "$(json_escape "$status")",
  "message": "$(json_escape "$message")",
  "created": ${created},
  "exists": ${exists},
  "config_changed": ${config_changed},
  "config_error": "$(json_escape "${config_error}")",
  "instance_state": "$(json_escape "${instance_state}")",
  "instance_name": "$(json_escape "$name")",
  "image": "$(json_escape "$image")",
  "profile": "$(json_escape "$lxd_profile")",
  "artifacts_dir": "$(json_escape "$artifacts_dir")",
  "metadata_preview_file": "$(json_escape "$metadata_preview_file")",
  "metadata_applied_file": "$(json_escape "$metadata_applied_file")",
  "plan_file": "$(json_escape "$plan_file")",
  "lxc_version": "$(json_escape "$lxc_version")",
  "profile_name": "$(json_escape "${PROFILE:-}")",
  "network_cidr": "$(json_escape "${NETWORK_CIDR:-}")",
  "base_domain": "$(json_escape "${BASE_DOMAIN:-}")"
}
EOF
}

ensure_lxd_user_key() {
  local key="$1" value="$2" current
  current="$(lxc config get "$name" "$key" 2>/dev/null || true)"
  if [[ "$current" != "$value" ]]; then
    lxc config set "$name" "$key" "$value"
    config_changed=1
  fi
}

if ! command -v lxc >/dev/null 2>&1; then
  echo "[lxd-adapter] missing command: lxc" >&2
  write_artifacts
  write_report "error" "missing command: lxc" "false" "false" ""
  exit 2
fi

lxc_version="$(lxc version 2>/dev/null | head -n 1 || true)"

if ! lxc info >/dev/null 2>&1; then
  echo "[lxd-adapter] lxc client is present but LXD is not reachable" >&2
  write_artifacts
  write_report "error" "lxc present but LXD is not reachable" "false" "false" "$lxc_version"
  exit 2
fi

write_artifacts

created=false
if lxc list --format csv -c n | grep -Fxq "$name"; then
  echo "[lxd-adapter] instance exists: $name"
  instance_state="exists"
else
  echo "[lxd-adapter] creating instance '$name' from '$image' (profile=$lxd_profile)"
  lxc launch "$image" "$name" -p "$lxd_profile"
  created=true
  instance_state="created"
fi

set +e
ensure_lxd_user_key "user.ralf.profile" "${PROFILE:-}"
rc1=$?
ensure_lxd_user_key "user.ralf.base_domain" "${BASE_DOMAIN:-}"
rc2=$?
ensure_lxd_user_key "user.ralf.network_cidr" "${NETWORK_CIDR:-}"
rc3=$?
ensure_lxd_user_key "user.ralf.managed" "true"
rc4=$?
set -e

if [[ $rc1 -ne 0 || $rc2 -ne 0 || $rc3 -ne 0 || $rc4 -ne 0 ]]; then
  config_error="failed to stamp one or more user.ralf.* metadata keys"
fi

if [[ "$instance_state" == "exists" && "$config_changed" -eq 1 ]]; then
  instance_state="updated"
fi

if [[ -z "$config_error" ]]; then
  write_applied_metadata
fi

if [[ "$created" == "true" ]]; then
  msg="instance created successfully"
  [[ "$config_changed" -eq 1 ]] && msg+=" and metadata stamped"
  write_report "created" "$msg" "true" "true" "$lxc_version"
  echo "[lxd-adapter] instance ready: $name"
else
  if [[ "$config_changed" -eq 1 ]]; then
    write_report "updated" "instance exists; metadata updated" "false" "true" "$lxc_version"
    echo "[lxd-adapter] instance metadata updated: $name"
  else
    write_report "exists" "instance already exists; no changes applied" "false" "true" "$lxc_version"
    echo "[lxd-adapter] instance unchanged: $name"
  fi
fi
