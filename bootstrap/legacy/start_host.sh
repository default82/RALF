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
bin_dir="${host_base}/bin"
cache_dir="${host_base}/cache"
state_dir="${host_base}/state"
answers_src="${outputs_dir}/answers.yml"
answers_dst="${artifacts_dir}/answers.yml"
plan_file="${artifacts_dir}/host-plan.md"
readiness_file="${artifacts_dir}/tool-readiness.json"

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
tool_links_changed=0
mkdir -p "$outputs_dir"

for d in "$host_base" "$runtime_dir" "$secrets_dir" "$logs_dir" "$artifacts_dir" "$bin_dir" "$cache_dir" "$state_dir"; do
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

tool_report_json='{}'
tool_manifest="${artifacts_dir}/tool-manifest.txt"
tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT
for tool in bash curl git tar sha256sum minisign lxc pct tofu terragrunt ansible; do
  if command -v "$tool" >/dev/null 2>&1; then
    tool_path="$(command -v "$tool")"
    printf '%s\tavailable\t%s\n' "$tool" "$tool_path" >> "$tmp_manifest"
    link_path="${bin_dir}/${tool}"
    if [[ ! -L "$link_path" || "$(readlink "$link_path" 2>/dev/null || true)" != "$tool_path" ]]; then
      ln -sfn "$tool_path" "$link_path"
      tool_links_changed=1
    fi
  else
    printf '%s\tmissing\t-\n' "$tool" >> "$tmp_manifest"
  fi
done
if [[ ! -f "$tool_manifest" ]] || ! cmp -s "$tmp_manifest" "$tool_manifest"; then
  cp "$tmp_manifest" "$tool_manifest"
  created_any=1
fi
if [[ "$tool_links_changed" -eq 1 ]]; then
  created_any=1
fi

tool_report_json="$(
  awk -F'\t' '
    BEGIN { printf("{"); first=1 }
    {
      if (!first) printf(",");
      first=0;
      gsub(/\\/,"\\\\",$1); gsub(/"/,"\\\"",$1);
      gsub(/\\/,"\\\\",$2); gsub(/"/,"\\\"",$2);
      gsub(/\\/,"\\\\",$3); gsub(/"/,"\\\"",$3);
      printf("\"%s\":{\"status\":\"%s\",\"path\":\"%s\"}", $1, $2, $3);
    }
    END { printf("}") }
  ' "$tool_manifest"
)"

required_tools=(bash curl git tar sha256sum)
optional_tools=(minisign lxc pct tofu terragrunt ansible)

missing_required=()
missing_optional=()
for t in "${required_tools[@]}"; do
  if ! command -v "$t" >/dev/null 2>&1; then
    missing_required+=("$t")
  fi
done
for t in "${optional_tools[@]}"; do
  if ! command -v "$t" >/dev/null 2>&1; then
    missing_optional+=("$t")
  fi
done

readiness_status="ready"
if [[ ${#missing_required[@]} -gt 0 ]]; then
  readiness_status="missing_required"
elif [[ ${#missing_optional[@]} -gt 0 ]]; then
  readiness_status="partial"
fi

join_json_array() {
  local out="[" first=1 item
  for item in "$@"; do
    [[ $first -eq 0 ]] && out+=","
    first=0
    out+="\"$(json_escape "$item")\""
  done
  out+="]"
  printf '%s' "$out"
}

required_json="$(join_json_array "${required_tools[@]}")"
optional_json="$(join_json_array "${optional_tools[@]}")"
missing_required_json="$(join_json_array "${missing_required[@]}")"
missing_optional_json="$(join_json_array "${missing_optional[@]}")"

cat > "$readiness_file" <<EOF
{
  "status": "$(json_escape "$readiness_status")",
  "required": ${required_json},
  "optional": ${optional_json},
  "missing_required": ${missing_required_json},
  "missing_optional": ${missing_optional_json}
}
EOF

cat > "$plan_file" <<EOF
# Host Bootstrap Plan (Conservative)

- Workspace: \`${host_base}\`
- Runtime dir: \`${runtime_dir}\`
- Tool readiness: \`${readiness_status}\`

## Required Tools
$(for t in "${required_tools[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then
    printf -- '- %s: present (%s)\n' "$t" "$(command -v "$t")"
  else
    printf -- '- %s: MISSING\n' "$t"
  fi
done)

## Optional Tools (for future phases)
$(for t in "${optional_tools[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then
    printf -- '- %s: present (%s)\n' "$t" "$(command -v "$t")"
  else
    printf -- '- %s: missing\n' "$t"
  fi
done)

## Next Actions (not executed by host adapter)
- Install missing optional tools as needed for local execution (e.g. tofu, terragrunt, ansible, minisign)
- Populate \`${secrets_dir}\` with environment/secrets files before local runner usage
- Add/choose a host-mode runner workflow
EOF

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
  "bin_dir": "$(json_escape "$bin_dir")",
  "cache_dir": "$(json_escape "$cache_dir")",
  "state_dir": "$(json_escape "$state_dir")",
  "answers_copied": $( [[ -f "$answers_dst" ]] && echo true || echo false ),
  "tool_manifest": "$(json_escape "$tool_manifest")",
  "tool_readiness_file": "$(json_escape "$readiness_file")",
  "host_plan_file": "$(json_escape "$plan_file")",
  "tool_readiness_status": "$(json_escape "$readiness_status")",
  "tools": ${tool_report_json},
  "profile": "$(json_escape "${PROFILE:-}")",
  "network_cidr": "$(json_escape "${NETWORK_CIDR:-}")",
  "base_domain": "$(json_escape "${BASE_DOMAIN:-}")",
  "ct_hostname": "$(json_escape "${CT_HOSTNAME:-}")"
}
EOF

echo "[host-adapter] ${message}: ${host_base}"
