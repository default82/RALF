#!/usr/bin/env bash
set -euo pipefail

log() { printf '[validate] %s\n' "$*"; }
warn() { printf '[validate][warn] %s\n' "$*" >&2; }
err() { printf '[validate][error] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/smoke_check.sh"

CONFIG_FILE=""
RUNTIME_DIR="/opt/ralf/runtime"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --runtime-dir) RUNTIME_DIR="${2:-}"; shift 2 ;;
    --dry-run|--mock) DRY_RUN=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap/validate.sh [--config FILE] [--runtime-dir DIR] [--dry-run|--mock]

Runs smoke checks for all deployed RALF services.
Requires a Proxmox host with pct available.

Options:
  --dry-run, --mock   Simuliert die Pruefung ohne Proxmox-Abhaengigkeit.
EOF
      exit 0
      ;;
    *)
      err "Unbekannte Option: $1"
      exit 2
      ;;
  esac
done

if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RUNTIME_DIR="${RUNTIME_DIR:-/opt/ralf/runtime}"
STATE_DIR="$RUNTIME_DIR/state"
RESULTS_FILE="$RUNTIME_DIR/smoke-results.jsonl"

mkdir -p "$RUNTIME_DIR"
: > "$RESULTS_FILE"

write_result() {
  local service="$1" status="$2"
  printf '{"ts":"%s","service":"%s","status":"%s"}\n' \
    "$(date -Iseconds)" "$service" "$status" >> "$RESULTS_FILE"
}

check_service() {
  local service="$1"
  local state_file="$STATE_DIR/${service}.state"
  local vmid_key="${service}_ctid"
  local service_name="$2"
  local port="${3:-}"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: pruefe ${service} (service=${service_name}, port=${port:-n/a})"
    write_result "$service" "DRY-RUN"
    return 0
  fi

  if ! smoke_state_file "$state_file" "$service"; then
    write_result "$service" "no-state"
    return 1
  fi

  local vmid
  vmid="$(grep -oP "${vmid_key}=\K.*" "$state_file" 2>/dev/null || true)"
  if [[ -z "$vmid" ]]; then
    warn "$service: CTID nicht im State gefunden."
    write_result "$service" "no-ctid"
    return 1
  fi

  local ok=1
  run_smoke "${service}:ct-running" smoke_ct_running "$vmid" || ok=0
  run_smoke "${service}:service-active" smoke_service_active "$vmid" "$service_name" || ok=0
  if [[ -n "$port" ]]; then
    run_smoke "${service}:port-${port}" smoke_port_open "$vmid" "$port" || ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    write_result "$service" "OK"
    return 0
  else
    write_result "$service" "Warnung"
    return 1
  fi
}

PASS=0
FAIL=0

run_check() {
  local label="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    warn "Check fehlgeschlagen: $label"
  fi
}

log "RALF Smoke-Validierung startet..."

if [[ "$DRY_RUN" == "1" ]]; then
  log "Modus: DRY-RUN (Mock)"
fi

run_check "minio"        check_service "minio"       "minio"          "9000"
run_check "postgresql"   check_service "postgresql"  "postgresql"     "5432"
run_check "gitea"        check_service "gitea"       "gitea"          "3000"
run_check "semaphore"    check_service "semaphore"   "semaphore"      "3000"
run_check "vaultwarden"  check_service "vaultwarden" "vaultwarden"    "8222"
run_check "prometheus"   check_service "prometheus"  "prometheus"     "9090"
run_check "n8n"          check_service "n8n"         "n8n"            "5678"
run_check "ki"           check_service "ki"          "ollama"         "11434"
run_check "matrix"       check_service "matrix"      "matrix-synapse" "8008"

log "Ergebnis: $PASS OK, $FAIL Warnung(en)"
log "Detailergebnisse: $RESULTS_FILE"

if [[ "$FAIL" -gt 0 ]]; then
  warn "Gate: Warnung – $FAIL Service(s) nicht vollständig validiert."
  exit 1
fi

log "Gate: OK – alle Services validiert."
