#!/usr/bin/env bash
set -euo pipefail

# Conservative host provisioner adapter for the new `ralf bootstrap` CLI.
# It performs a minimal local apply:
# - creates a local workspace/layout for future host-mode bootstrap work
# - records invocation metadata
# No destructive host changes are performed.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
outputs_dir="${repo_root}/outputs"
host_base="${RALF_HOST_BASE:-${repo_root}/.ralf-host}"
runtime_dir="${host_base}/runtime"
secrets_dir="${runtime_dir}/secrets"
logs_dir="${host_base}/logs"
artifacts_dir="${host_base}/artifacts"
answers_src="${outputs_dir}/answers.yml"
answers_dst="${artifacts_dir}/answers.yml"

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

created_any=0
mkdir -p "$outputs_dir"

for d in "$host_base" "$runtime_dir" "$secrets_dir" "$logs_dir" "$artifacts_dir"; do
  if [[ ! -d "$d" ]]; then
    mkdir -p "$d"
    created_any=1
  fi
done

if [[ -f "$answers_src" ]]; then
  if [[ ! -f "$answers_dst" ]] || ! cmp -s "$answers_src" "$answers_dst"; then
    cp "$answers_src" "$answers_dst"
    created_any=1
  fi
fi

status="exists"
message="host workspace already present; no changes applied"
if [[ "$created_any" -eq 1 ]]; then
  status="prepared"
  message="host workspace prepared"
fi

cat > "${outputs_dir}/host_apply_report.json" <<EOF
{
  "provisioner": "host",
  "status": "$(json_escape "$status")",
  "message": "$(json_escape "$message")",
  "workspace": "$(json_escape "$host_base")",
  "runtime_dir": "$(json_escape "$runtime_dir")",
  "secrets_dir": "$(json_escape "$secrets_dir")",
  "logs_dir": "$(json_escape "$logs_dir")",
  "artifacts_dir": "$(json_escape "$artifacts_dir")",
  "answers_copied": $( [[ -f "$answers_dst" ]] && echo true || echo false ),
  "profile": "$(json_escape "${PROFILE:-}")",
  "network_cidr": "$(json_escape "${NETWORK_CIDR:-}")",
  "base_domain": "$(json_escape "${BASE_DOMAIN:-}")",
  "ct_hostname": "$(json_escape "${CT_HOSTNAME:-}")"
}
EOF

echo "[host-adapter] ${message}: ${host_base}"
