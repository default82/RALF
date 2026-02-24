#!/usr/bin/env bash
set -euo pipefail

# Conservative host provisioner adapter for the new `ralf bootstrap` CLI.
# It performs a minimal local apply:
# - creates a local workspace/layout for future host-mode bootstrap work
# - records invocation metadata
# No destructive host changes are performed.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
outputs_dir="${OUTPUTS_DIR:-${repo_root}/outputs}"
host_base="${RALF_HOST_BASE:-${repo_root}/.ralf-host}"
runtime_dir="${host_base}/runtime"
secrets_dir="${runtime_dir}/secrets"
logs_dir="${host_base}/logs"
artifacts_dir="${host_base}/artifacts"
bin_dir="${host_base}/bin"
cache_dir="${host_base}/cache"
state_dir="${host_base}/state"
config_dir="${host_base}/config"
answers_src="${outputs_dir}/answers.yml"
answers_dst="${artifacts_dir}/answers.yml"
plan_file="${artifacts_dir}/host-plan.md"
readiness_file="${artifacts_dir}/tool-readiness.json"
host_runner_env_file="${config_dir}/host-runner.env"
host_runner_wrapper="${bin_dir}/ralf-host-runner"
host_runner_readme="${artifacts_dir}/host-runner.md"

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

for d in "$host_base" "$runtime_dir" "$secrets_dir" "$logs_dir" "$artifacts_dir" "$bin_dir" "$cache_dir" "$state_dir" "$config_dir"; do
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

cat > "$host_runner_env_file" <<EOF
# Host-mode runner environment (generated by bootstrap/legacy/start_host.sh)
RALF_REPO=${repo_root}
RALF_BASE=${host_base}
RALF_RUNTIME=${runtime_dir}
RALF_OUTPUTS_DIR=${outputs_dir}
RALF_TOOL_READINESS_FILE=${readiness_file}
AUTO_APPLY=0
RUN_STACKS=0
EOF
chmod 0644 "$host_runner_env_file"

cat > "$host_runner_wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ralf-host-runner [--check|--dry-run|--run]

  --check   Validate local prerequisites and print derived paths
  --dry-run Show the command that a future host runner would execute
  --run     Guarded placeholder for future host execution (requires explicit enable)
USAGE
}

mode="check"
case "\${1:-}" in
  ""|--check) mode="check" ;;
  --dry-run) mode="dry_run" ;;
  --run) mode="run" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[host-runner] unknown option: \$1" >&2; usage; exit 2 ;;
esac

HOST_BASE="\${RALF_HOST_BASE:-${host_base}}"
CFG_FILE="\${RALF_HOST_RUNNER_ENV:-${host_runner_env_file}}"

if [[ -f "\$CFG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "\$CFG_FILE"
  set +a
fi

export RALF_BASE="\${RALF_BASE:-\$HOST_BASE}"
export RALF_RUNTIME="\${RALF_RUNTIME:-\$HOST_BASE/runtime}"
export RALF_REPO="\${RALF_REPO:-${repo_root}}"
export RALF_OUTPUTS_DIR="\${RALF_OUTPUTS_DIR:-${outputs_dir}}"
export RALF_TOOL_READINESS_FILE="\${RALF_TOOL_READINESS_FILE:-\$HOST_BASE/artifacts/tool-readiness.json}"

echo "[host-runner] repo=\$RALF_REPO"
echo "[host-runner] runtime=\$RALF_RUNTIME"
echo "[host-runner] outputs=\$RALF_OUTPUTS_DIR"
echo "[host-runner] readiness=\$RALF_TOOL_READINESS_FILE"

if [[ -f "\$RALF_TOOL_READINESS_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "\$RALF_TOOL_READINESS_FILE" <<'PY'
import json, sys
p = sys.argv[1]
try:
    data = json.load(open(p))
except Exception as e:
    print(f"[host-runner] warning: could not parse readiness file: {e}", file=sys.stderr)
    sys.exit(0)
status = data.get("status", "unknown")
missing_required = data.get("missing_required", []) or []
missing_optional = data.get("missing_optional", []) or []
print(f"[host-runner] readiness status: {status}")
if missing_required:
    print("[host-runner] missing required tools: " + ", ".join(missing_required))
if missing_optional:
    print("[host-runner] missing optional tools: " + ", ".join(missing_optional))
PY
fi

missing=0
for req in bash curl git; do
  if ! command -v "\$req" >/dev/null 2>&1; then
    echo "[host-runner] missing required tool: \$req" >&2
    missing=1
  fi
done
[[ -d "\$RALF_RUNTIME/secrets" ]] || { echo "[host-runner] missing runtime secrets dir: \$RALF_RUNTIME/secrets" >&2; missing=1; }
[[ -d "\$RALF_REPO" ]] || { echo "[host-runner] missing repo dir: \$RALF_REPO" >&2; missing=1; }

if [[ "\$mode" == "check" ]]; then
  if [[ "\$missing" -eq 0 ]]; then
    echo "[host-runner] check: OK"
    echo "[host-runner] Placeholder wrapper only. No stack execution implemented yet."
    exit 0
  fi
  echo "[host-runner] check: FAILED" >&2
  exit 2
fi

if [[ "\$mode" == "dry_run" ]]; then
  runner_script="\$RALF_REPO/bootstrap/runner.sh"
  echo "[host-runner] dry-run: placeholder preview"
  echo "[host-runner] would export:"
  echo "  RALF_BASE=\$RALF_BASE"
  echo "  RALF_RUNTIME=\$RALF_RUNTIME"
  echo "  RALF_REPO=\$RALF_REPO"
  echo "  AUTO_APPLY=\${AUTO_APPLY:-0}"
  echo "  RUN_STACKS=\${RUN_STACKS:-0}"
  echo "  START_AT=\${START_AT:-}"
  echo "  ONLY_STACKS=\${ONLY_STACKS:-}"
  echo "[host-runner] would run:"
  echo "  bash \$runner_script"
  if [[ ! -f "\$runner_script" ]]; then
    echo "[host-runner] warning: runner script not found at \$runner_script" >&2
    exit 1
  fi
  exit 0
fi

if [[ "\${HOST_RUNNER_ENABLE_EXEC:-0}" != "1" ]]; then
  echo "[host-runner] --run is disabled by default. Set HOST_RUNNER_ENABLE_EXEC=1 to proceed." >&2
  exit 2
fi

if [[ "\$missing" -ne 0 ]]; then
  echo "[host-runner] prerequisites missing; refusing --run" >&2
  exit 2
fi

runner_script="\$RALF_REPO/bootstrap/runner.sh"
if [[ ! -f "\$runner_script" ]]; then
  echo "[host-runner] missing runner script: \$runner_script" >&2
  exit 2
fi
if ! bash -n "\$runner_script" >/dev/null 2>&1; then
  echo "[host-runner] runner syntax check failed: \$runner_script" >&2
  exit 2
fi

echo "[host-runner] preflight OK (execution mode enabled)." >&2
echo "[host-runner] runner script present and syntax-valid: \$runner_script" >&2
echo "[host-runner] stack execution is still intentionally not implemented in host runner." >&2
echo "[host-runner] Next step: add host-safe runner wiring to bootstrap/runner.sh or a dedicated host runner." >&2
exit 2
EOF
chmod 0755 "$host_runner_wrapper"

cat > "$host_runner_readme" <<EOF
# Host Runner (Placeholder)

Generated by the host bootstrap adapter.

Files:

- \`${host_runner_env_file}\` - environment defaults for a future local runner
- \`${host_runner_wrapper}\` - placeholder wrapper (currently non-executing)

Current behavior:

- `--check`: validates local prerequisites and prints derived paths
- `--run`: guarded placeholder (disabled by default, no stack execution yet)

Next step to make this real:

1. Install optional tools (`tofu`, `terragrunt`, `ansible`)
2. Populate \`${secrets_dir}\`
3. Add a host-safe runner implementation (likely a host-specific variant of \`bootstrap/runner.sh\`)
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
  "config_dir": "$(json_escape "$config_dir")",
  "answers_copied": $( [[ -f "$answers_dst" ]] && echo true || echo false ),
  "tool_manifest": "$(json_escape "$tool_manifest")",
  "tool_readiness_file": "$(json_escape "$readiness_file")",
  "host_plan_file": "$(json_escape "$plan_file")",
  "host_runner_env_file": "$(json_escape "$host_runner_env_file")",
  "host_runner_wrapper": "$(json_escape "$host_runner_wrapper")",
  "host_runner_readme": "$(json_escape "$host_runner_readme")",
  "tool_readiness_status": "$(json_escape "$readiness_status")",
  "tools": ${tool_report_json},
  "profile": "$(json_escape "${PROFILE:-}")",
  "network_cidr": "$(json_escape "${NETWORK_CIDR:-}")",
  "base_domain": "$(json_escape "${BASE_DOMAIN:-}")",
  "ct_hostname": "$(json_escape "${CT_HOSTNAME:-}")"
}
EOF

echo "[host-adapter] ${message}: ${host_base}"
