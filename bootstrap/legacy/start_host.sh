#!/usr/bin/env bash
set -euo pipefail

# Minimal host provisioner adapter for the new `ralf bootstrap` CLI.
# Current behavior is intentionally conservative: no destructive changes.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
outputs_dir="${repo_root}/outputs"
mkdir -p "$outputs_dir"

cat > "${outputs_dir}/host_apply_report.json" <<EOF
{
  "provisioner": "host",
  "status": "applied_noop",
  "message": "Host adapter executed. No host provisioning actions are implemented yet.",
  "profile": "${PROFILE:-}",
  "network_cidr": "${NETWORK_CIDR:-}",
  "base_domain": "${BASE_DOMAIN:-}",
  "ct_hostname": "${CT_HOSTNAME:-}"
}
EOF

echo "[host-adapter] No-op apply completed (artifacts only)."
