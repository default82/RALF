#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/bootstrap/lib/hook_module.sh"

mode="$(hm_mode)"
runtime_dir="$(hm_runtime_dir)"
mkdir -p "$runtime_dir/state"

semaphore_state="$runtime_dir/state/semaphore.state"

if [[ "$mode" == "plan" ]]; then
  hm_log "090-semaphore-first" "PLAN: würde Semaphore-first Betriebsmodus aktivieren."
  if [[ -f "$semaphore_state" ]]; then
    hm_log "090-semaphore-first" "PLAN: Semaphore-State gefunden: $semaphore_state"
  else
    hm_warn "090-semaphore-first" "PLAN: Semaphore-State fehlt ($semaphore_state) – Phase 1 muss zuerst abgeschlossen sein."
  fi
else
  if [[ ! -f "$semaphore_state" ]]; then
    hm_warn "090-semaphore-first" "Semaphore-State fehlt; Semaphore-first Modus kann nicht aktiviert werden."
    exit 1
  fi

  semaphore_ctid="$(grep -oP 'semaphore_ctid=\K.*' "$semaphore_state" || true)"
  if [[ -z "$semaphore_ctid" ]]; then
    hm_warn "090-semaphore-first" "semaphore_ctid nicht im State gefunden."
    exit 1
  fi

  command -v pct >/dev/null 2>&1 || { hm_warn "090-semaphore-first" "pct fehlt"; exit 1; }
  if ! pct status "$semaphore_ctid" >/dev/null 2>&1; then
    hm_warn "090-semaphore-first" "Semaphore CT $semaphore_ctid nicht erreichbar."
    exit 1
  fi

  hm_log "090-semaphore-first" "APPLY: Semaphore CT $semaphore_ctid ist aktiv – Semaphore-first Betriebsmodus bestätigt."
fi

printf 'semaphore_first_mode=%s\n' "$mode" > "$runtime_dir/state/semaphore-first.state"
printf 'semaphore_first_ts=%s\n' "$(date -Iseconds)" >> "$runtime_dir/state/semaphore-first.state"