#!/usr/bin/env bash
set -euo pipefail

sc_log() { printf '[smoke-check] %s\n' "$*"; }
sc_warn() { printf '[smoke-check][warn] %s\n' "$*" >&2; }
sc_err() { printf '[smoke-check][error] %s\n' "$*" >&2; }

# Check that a CT is running
smoke_ct_running() {
  local vmid="$1"
  command -v pct >/dev/null 2>&1 || { sc_err "pct nicht verfügbar"; return 1; }
  if pct status "$vmid" 2>/dev/null | grep -q "status: running"; then
    sc_log "CT $vmid läuft."
    return 0
  fi
  sc_err "CT $vmid läuft nicht."
  return 1
}

# Check that a TCP port is reachable inside a CT
smoke_port_open() {
  local vmid="$1"
  local port="$2"
  local host="${3:-127.0.0.1}"
  command -v pct >/dev/null 2>&1 || { sc_err "pct nicht verfügbar"; return 1; }
  if pct exec "$vmid" -- bash -lc "timeout 3 bash -c '</dev/tcp/${host}/${port}'" >/dev/null 2>&1; then
    sc_log "Port $port in CT $vmid erreichbar."
    return 0
  fi
  sc_warn "Port $port in CT $vmid nicht erreichbar."
  return 1
}

# Check that a systemd service is active inside a CT
smoke_service_active() {
  local vmid="$1"
  local service="$2"
  command -v pct >/dev/null 2>&1 || { sc_err "pct nicht verfügbar"; return 1; }
  if pct exec "$vmid" -- systemctl is-active --quiet "$service" 2>/dev/null; then
    sc_log "Service '$service' in CT $vmid aktiv."
    return 0
  fi
  sc_warn "Service '$service' in CT $vmid nicht aktiv."
  return 1
}

# Check that a state file for a service exists
smoke_state_file() {
  local state_file="$1"
  local label="${2:-State}"
  if [[ -f "$state_file" ]]; then
    sc_log "$label State gefunden: $state_file"
    return 0
  fi
  sc_warn "$label State fehlt: $state_file"
  return 1
}

# Run a named smoke check and record result
run_smoke() {
  local name="$1"
  shift
  if "$@"; then
    sc_log "SMOKE OK: $name"
    return 0
  else
    sc_warn "SMOKE FAIL: $name"
    return 1
  fi
}
