#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_NAME=""
LIST_ONLY=0
JSON_OUTPUT=0
RAW_OUTPUT_ON_FAIL=0
PROJECT_ID="${PROJECT_ID:-1}"
SEMAPHORE_BASE_URL="${SEMAPHORE_BASE_URL:-https://10.10.40.10}"
BOOTSTRAP_CT="${BOOTSTRAP_CT:-10010}"
SEMAPHORE_ENV_PATH="${SEMAPHORE_ENV_PATH:-/opt/ralf/runtime/secrets/semaphore.env}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-240}"
POLL_SECONDS="${POLL_SECONDS:-2}"
OUTPUT_TAIL_LINES="${OUTPUT_TAIL_LINES:-120}"

usage() {
  cat >&2 <<'EOF'
usage:
  bootstrap/sem-run-template.sh [--project-id N] [--json] [--raw-output] "Template Name"
  bootstrap/sem-run-template.sh [--project-id N] [--json] --list

Optional env vars:
  PROJECT_ID=1
  SEMAPHORE_BASE_URL=https://10.10.40.10
  BOOTSTRAP_CT=10010
  TIMEOUT_SECONDS=240
  POLL_SECONDS=2
  OUTPUT_TAIL_LINES=120
EOF
  exit 2
}

log() { printf '[sem-run] %s\n' "$*"; }
json_escape() { jq -Rs . <<<"$1"; }
out() {
  if [[ $JSON_OUTPUT -eq 1 ]]; then
    return 0
  fi
  log "$*"
}
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }

need curl
need jq
need pct

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      LIST_ONLY=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    --raw-output)
      RAW_OUTPUT_ON_FAIL=1
      shift
      ;;
    --project-id)
      [[ $# -ge 2 ]] || usage
      PROJECT_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$TEMPLATE_NAME" ]]; then
        TEMPLATE_NAME="$1"
        shift
      else
        echo "unexpected extra argument: $1" >&2
        usage
      fi
      ;;
  esac
done

if [[ $LIST_ONLY -eq 0 && -z "$TEMPLATE_NAME" ]]; then
  usage
fi

get_admin_from_bootstrap() {
  pct exec "$BOOTSTRAP_CT" -- bash -lc \
    "grep '^SEMAPHORE_ADMIN_NAME=' '$SEMAPHORE_ENV_PATH' | cut -d= -f2-"
}

get_password_from_bootstrap() {
  pct exec "$BOOTSTRAP_CT" -- bash -lc \
    "grep '^SEMAPHORE_ADMIN_PASSWORD=' '$SEMAPHORE_ENV_PATH' | cut -d= -f2-"
}

SEMAPHORE_ADMIN_NAME="${SEMAPHORE_ADMIN_NAME:-$(get_admin_from_bootstrap)}"
SEMAPHORE_ADMIN_PASSWORD="${SEMAPHORE_ADMIN_PASSWORD:-$(get_password_from_bootstrap)}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cookies="$tmpdir/cookies.txt"

api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -kfsS -b "$cookies" -c "$cookies" -X "$method" \
      -H 'Content-Type: application/json' \
      -d "$body" \
      "${SEMAPHORE_BASE_URL}${path}"
  else
    curl -kfsS -b "$cookies" -c "$cookies" -X "$method" \
      "${SEMAPHORE_BASE_URL}${path}"
  fi
}

login_payload="$(jq -nc \
  --arg a "$SEMAPHORE_ADMIN_NAME" \
  --arg p "$SEMAPHORE_ADMIN_PASSWORD" \
  '{auth:$a,password:$p}')"

out "Login ${SEMAPHORE_BASE_URL}"
curl -kfsS -c "$cookies" -X POST \
  -H 'Content-Type: application/json' \
  -d "$login_payload" \
  "${SEMAPHORE_BASE_URL}/api/auth/login" >/dev/null

templates_json="$(api GET "/api/project/${PROJECT_ID}/templates")"
if [[ $LIST_ONLY -eq 1 ]]; then
  if [[ $JSON_OUTPUT -eq 1 ]]; then
    jq -c --argjson pid "$PROJECT_ID" '{project_id:$pid, templates: [ .[] | {id, name} ]}' <<<"$templates_json"
  else
    log "Templates in project ${PROJECT_ID}"
    jq -r '.[] | [.id, .name] | @tsv' <<<"$templates_json" | sort -n | awk -F'\t' '{printf "%s\t%s\n",$1,$2}'
  fi
  exit 0
fi

out "Resolve template '${TEMPLATE_NAME}' (project ${PROJECT_ID})"
template_id="$(jq -r --arg n "$TEMPLATE_NAME" '.[] | select(.name==$n) | .id' <<<"$templates_json" | head -n1)"
[[ -n "$template_id" ]] || { echo "template not found: ${TEMPLATE_NAME}" >&2; exit 1; }

create_payload="$(jq -nc --argjson tid "$template_id" '{template_id:$tid}')"
task_json="$(api POST "/api/project/${PROJECT_ID}/tasks" "$create_payload")"
task_id="$(jq -r '.id' <<<"$task_json")"
[[ -n "$task_id" && "$task_id" != "null" ]] || { echo "failed to create task" >&2; echo "$task_json" >&2; exit 1; }
out "Task created: ${task_id}"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  task_json="$(api GET "/api/project/${PROJECT_ID}/tasks/${task_id}")"
  status="$(jq -r '.status' <<<"$task_json")"
  case "$status" in
    success)
      if [[ $JSON_OUTPUT -eq 1 ]]; then
        jq -nc \
          --argjson project_id "$PROJECT_ID" \
          --argjson template_id "$template_id" \
          --argjson task_id "$task_id" \
          --arg template_name "$TEMPLATE_NAME" \
          --arg status "$status" \
          '{ok:true,project_id:$project_id,template_id:$template_id,template_name:$template_name,task_id:$task_id,status:$status}'
      else
        log "Task ${task_id} success"
      fi
      exit 0
      ;;
    error|failed|fail)
      if [[ $RAW_OUTPUT_ON_FAIL -eq 1 ]]; then
        api GET "/api/project/${PROJECT_ID}/tasks/${task_id}/raw_output" | tail -n "$OUTPUT_TAIL_LINES" >&2 || true
      else
        api GET "/api/project/${PROJECT_ID}/tasks/${task_id}/output" | tail -n "$OUTPUT_TAIL_LINES" >&2 || true
      fi
      if [[ $JSON_OUTPUT -eq 1 ]]; then
        jq -nc \
          --argjson project_id "$PROJECT_ID" \
          --argjson template_id "$template_id" \
          --argjson task_id "$task_id" \
          --arg template_name "$TEMPLATE_NAME" \
          --arg status "$status" \
          '{ok:false,project_id:$project_id,template_id:$template_id,template_name:$template_name,task_id:$task_id,status:$status}'
      else
        log "Task ${task_id} ${status}"
      fi
      exit 1
      ;;
  esac
  if (( $(date +%s) >= deadline )); then
    if [[ $RAW_OUTPUT_ON_FAIL -eq 1 ]]; then
      api GET "/api/project/${PROJECT_ID}/tasks/${task_id}/raw_output" | tail -n "$OUTPUT_TAIL_LINES" >&2 || true
    else
      api GET "/api/project/${PROJECT_ID}/tasks/${task_id}/output" | tail -n "$OUTPUT_TAIL_LINES" >&2 || true
    fi
    if [[ $JSON_OUTPUT -eq 1 ]]; then
      jq -nc \
        --argjson project_id "$PROJECT_ID" \
        --argjson template_id "$template_id" \
        --argjson task_id "$task_id" \
        --arg template_name "$TEMPLATE_NAME" \
        --arg status "$status" \
        '{ok:false,timeout:true,project_id:$project_id,template_id:$template_id,template_name:$template_name,task_id:$task_id,status:$status}'
    else
      log "Task ${task_id} timeout (last status: ${status})"
    fi
    exit 1
  fi
  sleep "$POLL_SECONDS"
done
