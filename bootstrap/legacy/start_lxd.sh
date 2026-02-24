#!/usr/bin/env bash
set -euo pipefail

# Minimal LXD/LXC provisioner adapter for the new `ralf bootstrap` CLI.
# Conservative implementation: validates command presence and records invocation.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
outputs_dir="${repo_root}/outputs"
mkdir -p "$outputs_dir"

if ! command -v lxc >/dev/null 2>&1; then
  echo "[lxd-adapter] missing command: lxc" >&2
  cat > "${outputs_dir}/lxd_apply_report.json" <<EOF
{
  "provisioner": "lxd",
  "status": "error",
  "error": "missing command: lxc"
}
EOF
  exit 2
fi

lxc_version="$(lxc version 2>/dev/null | head -n 1 || true)"
cat > "${outputs_dir}/lxd_apply_report.json" <<EOF
{
  "provisioner": "lxd",
  "status": "applied_noop",
  "message": "LXD adapter executed. Provisioning actions are not implemented yet.",
  "lxc_version": "${lxc_version}",
  "profile": "${PROFILE:-}",
  "network_cidr": "${NETWORK_CIDR:-}",
  "base_domain": "${BASE_DOMAIN:-}",
  "ct_hostname": "${CT_HOSTNAME:-}"
}
EOF

echo "[lxd-adapter] No-op apply completed (artifacts only)."
