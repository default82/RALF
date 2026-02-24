#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_NAME="${1:-}"
PROJECT_ID="${PROJECT_ID:-1}"
SEMAPHORE_BASE_URL="${SEMAPHORE_BASE_URL:-https://10.10.40.10}"
BOOTSTRAP_CT="${BOOTSTRAP_CT:-10010}"
SEMAPHORE_ENV_PATH="${SEMAPHORE_ENV_PATH:-/opt/ralf/runtime/secrets/semaphore.env}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-240}"
POLL_SECONDS="${POLL_SECONDS:-2}"
OUTPUT_TAIL_LINES="${OUTPUT_TAIL_LINES:-120}"

usage() {
  cat >&2 <<'EOF'
usage: bootstrap/sem-run-template.sh "Template Name"

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
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }

[[ -n "$TEMPLATE_NAME" ]] || usage
need curl
need jq
need pct

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

log "Login ${SEMAPHORE_BASE_URL}"
curl -kfsS -c "$cookies" -X POST \
  -H 'Content-Type: application/json' \
  -d "$login_payload" \
  "${SEMAPHORE_BASE_URL}/api/auth/login" >/dev/null

log "Resolve template '${TEMPLATE_NAME}' (project ${PROJECT_ID})"
templates_json="$(api GET "/api/project/${PROJECT_ID}/templates")"
template_id="$(jq -r --arg n "$TEMPLATE_NAME" '.[] | select(.name==$n) | .id' <<<"$templates_json" | head -n1)"
[[ -n "$template_id" ]] || { echo "template not found: ${TEMPLATE_NAME}" >&2; exit 1; }

create_payload="$(jq -nc --argjson tid "$template_id" '{template_id:$tid}')"
task_json="$(api POST "/api/project/${PROJECT_ID}/tasks" "$create_payload")"
task_id="$(jq -r '.id' <<<"$task_json")"
[[ -n "$task_id" && "$task_id" != "null" ]] || { echo "failed to create task" >&2; echo "$task_json" >&2; exit 1; }
log "Task created: ${task_id}"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  task_json="$(api GET "/api/project/${PROJECT_ID}/tasks/${task_id}")"
  status="$(jq -r '.status' <<<"$task_json")"
  case "$status" in
    success)
      log "Task ${task_id} success"
      exit 0
      ;;
    error|failed|fail)
      log "Task ${task_id} ${status}"
      api GET "/api/project/${PROJECT_ID}/tasks/${task_id}/output" | tail -n "$OUTPUT_TAIL_LINES" >&2 || true
      exit 1
      ;;
  esac
  if (( $(date +%s) >= deadline )); then
    log "Task ${task_id} timeout (last status: ${status})"
    api GET "/api/project/${PROJECT_ID}/tasks/${task_id}/output" | tail -n "$OUTPUT_TAIL_LINES" >&2 || true
    exit 1
  fi
  sleep "$POLL_SECONDS"
done
