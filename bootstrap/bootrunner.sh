#!/usr/bin/env bash
set -euo pipefail

log() { printf '[bootrunner] %s\n' "$*"; }
warn() { printf '[bootrunner][warn] %s\n' "$*" >&2; }
err() { printf '[bootrunner][error] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/phase_catalog.sh"

APPLY=0
YES=0
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --yes) YES=1; shift ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap/bootrunner.sh --config FILE [--apply] [--yes]

Runs bootstrap phases and writes checkpoints.
EOF
      exit 0
      ;;
    *)
      err "Unbekannte Option: $1"
      exit 2
      ;;
  esac
done

[[ -n "$CONFIG_FILE" ]] || { err "--config FILE ist erforderlich"; exit 2; }
[[ -f "$CONFIG_FILE" ]] || { err "Config nicht gefunden: $CONFIG_FILE"; exit 2; }

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

RUNTIME_DIR="${RUNTIME_DIR:-/opt/ralf/runtime}"
LOG_DIR="$RUNTIME_DIR/logs"
CHECKPOINTS_FILE="$RUNTIME_DIR/checkpoints.jsonl"
SUMMARY_FILE="$RUNTIME_DIR/summary.md"
HOOK_DIR="${HOOK_DIR:-$REPO_ROOT/bootstrap/hooks}"

mkdir -p "$LOG_DIR"
touch "$CHECKPOINTS_FILE"
chmod 600 "$CHECKPOINTS_FILE" || true

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_LOG="$LOG_DIR/run-$RUN_ID.log"

exec > >(tee -a "$RUN_LOG") 2>&1

MODE="plan"
[[ "$APPLY" == "1" ]] && MODE="apply"

write_checkpoint() {
  local phase="$1" status="$2" summary="$3"
  printf '{"ts":"%s","phase":"%s","status":"%s","summary":"%s"}\n' \
    "$(date -Iseconds)" "$phase" "$status" "${summary//\"/\\\"}" >> "$CHECKPOINTS_FILE"
}

confirm_gate() {
  local phase="$1"
  if [[ "$YES" == "1" || ! -t 0 ]]; then
    return 0
  fi
  local answer
  read -r -p "[bootrunner] Phase '$phase' fortsetzen? (yes/no): " answer || true
  [[ "$answer" == "yes" ]]
}

run_hook_or_stub() {
  local service="$1"
  local hook="$HOOK_DIR/$service.sh"

  if [[ -f "$hook" ]]; then
    log "Hook gefunden: $hook"
    local mode="plan"
    [[ "$APPLY" == "1" ]] && mode="apply"
    RALF_MODE="$mode" RALF_RUNTIME_DIR="$RUNTIME_DIR" bash "$hook"
    return 0
  fi

  warn "Kein Hook für '$service' gefunden ($hook)."
  if [[ "$APPLY" == "1" ]]; then
    warn "APPLY läuft ohne echte Deploy-Logik für '$service' (MVP-Stub)."
  else
    log "PLAN: '$service' ist als Stub markiert."
  fi
  return 0
}

run_service_sequence() {
  local phase_label="$1"
  shift
  local services=("$@")

  log "$phase_label"
  local service
  for service in "${services[@]}"; do
    run_hook_or_stub "$service" || return 1
  done
}

phase_preflight() {
  log "Phase 0: Vorbereitung"
  command -v bash >/dev/null 2>&1 || { err "bash fehlt"; return 1; }
  command -v pct >/dev/null 2>&1 || warn "pct nicht gefunden (für Proxmox-Host erwartet)"
  [[ -n "${PROXMOX_HOST:-}" ]] || { err "PROXMOX_HOST fehlt"; return 1; }
  [[ -n "${PROXMOX_NODE:-}" ]] || { err "PROXMOX_NODE fehlt"; return 1; }
  [[ -n "${RALF_NETWORK_CIDR:-}" ]] || { err "RALF_NETWORK_CIDR fehlt"; return 1; }
  return 0
}

phase_foundation_core() {
  run_service_sequence \
    "Phase 1: Foundation Core (MinIO -> PostgreSQL -> Gitea -> Semaphore)" \
    "${RALF_PHASE_SERVICES_FOUNDATION_CORE[@]}" || return 1
  return 0
}

phase_foundation_services() {
  run_service_sequence \
    "Phase 2: Foundation Services (Vaultwarden -> Prometheus)" \
    "${RALF_PHASE_SERVICES_FOUNDATION_SERVICES[@]}" || return 1
  return 0
}

phase_extension() {
  run_service_sequence \
    "Phase 3: Erweiterung (n8n -> KI -> Matrix)" \
    "${RALF_PHASE_SERVICES_EXTENSION[@]}" || return 1
  return 0
}

phase_operating_mode() {
  run_service_sequence \
    "Phase 4: Betriebsmodus (Semaphore-first)" \
    "${RALF_PHASE_SERVICES_OPERATING_MODE[@]}" || return 1
  return 0
}

run_phase() {
  local name="$1"
  shift
  if "$@"; then
    write_checkpoint "$name" "OK" "Phase erfolgreich"
    log "Gate: OK ($name)"
    return 0
  else
    write_checkpoint "$name" "Blocker" "Phase fehlgeschlagen"
    err "Gate: Blocker ($name)"
    return 1
  fi
}

log "Run-ID: $RUN_ID"
log "Modus: $MODE"
log "Config: $CONFIG_FILE"

run_phase "phase-0-vorbereitung" phase_preflight || exit 2
confirm_gate "phase-0-vorbereitung" || exit 1

run_phase "phase-1-foundation-core" phase_foundation_core || exit 2
confirm_gate "phase-1-foundation-core" || exit 1

run_phase "phase-2-foundation-services" phase_foundation_services || exit 2
confirm_gate "phase-2-foundation-services" || exit 1

run_phase "phase-3-erweiterung" phase_extension || exit 2
confirm_gate "phase-3-erweiterung" || exit 1

run_phase "phase-4-betriebsmodus" phase_operating_mode || exit 2

cat > "$SUMMARY_FILE" <<EOF
# RALF Bootrunner Summary

- Run-ID: $RUN_ID
- Modus: $MODE
- Host: ${PROXMOX_HOST:-unknown}
- Node: ${PROXMOX_NODE:-unknown}
- Netzwerk: ${RALF_NETWORK_CIDR:-unknown}
- Checkpoints: $CHECKPOINTS_FILE
- Log: $RUN_LOG
EOF

log "Bootstrap abgeschlossen."
log "Summary: $SUMMARY_FILE"
