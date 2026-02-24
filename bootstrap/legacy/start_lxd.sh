#!/usr/bin/env bash
set -euo pipefail

# Conservative LXD adapter for `ralf bootstrap`.
# Behavior:
# - validates `lxc`
# - checks if instance exists
# - creates it if missing (explicitly called only via `ralf bootstrap --apply`)
# - writes outputs/lxd_apply_report.json

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
outputs_dir="${repo_root}/outputs"
mkdir -p "$outputs_dir"

name="${CT_HOSTNAME:-ralf-bootstrap}"
image="${LXD_IMAGE:-images:ubuntu/24.04}"
lxd_profile="${LXD_PROFILE:-default}"

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
  "instance_name": "$(json_escape "$name")",
  "image": "$(json_escape "$image")",
  "profile": "$(json_escape "$lxd_profile")",
  "lxc_version": "$(json_escape "$lxc_version")",
  "profile_name": "$(json_escape "${PROFILE:-}")",
  "network_cidr": "$(json_escape "${NETWORK_CIDR:-}")",
  "base_domain": "$(json_escape "${BASE_DOMAIN:-}")"
}
EOF
}

if ! command -v lxc >/dev/null 2>&1; then
  echo "[lxd-adapter] missing command: lxc" >&2
  write_report "error" "missing command: lxc" "false" "false" ""
  exit 2
fi

lxc_version="$(lxc version 2>/dev/null | head -n 1 || true)"

if ! lxc info >/dev/null 2>&1; then
  echo "[lxd-adapter] lxc client is present but LXD is not reachable" >&2
  write_report "error" "lxc present but LXD is not reachable" "false" "false" "$lxc_version"
  exit 2
fi

if lxc list --format csv -c n | grep -Fxq "$name"; then
  echo "[lxd-adapter] instance exists: $name"
  write_report "exists" "instance already exists; no changes applied" "false" "true" "$lxc_version"
  exit 0
fi

echo "[lxd-adapter] creating instance '$name' from '$image' (profile=$lxd_profile)"
lxc launch "$image" "$name" -p "$lxd_profile"

write_report "created" "instance created successfully" "true" "true" "$lxc_version"
echo "[lxd-adapter] instance created: $name"
