#!/usr/bin/env bash
set -euo pipefail

echo "[NET] Starting network health check..."

FAILED=0

check() {
  local desc="$1"
  local cmd="$2"

  echo -n "[NET] $desc ... "
  if eval "$cmd" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    FAILED=1
  fi
}

# Gateway erreichbar?
check "Gateway reachable (opnsense)" "ping -c 1 -W 1 10.10.0.1"

# Proxmox Host erreichbar?
check "Proxmox reachable (pve-deploy)" "ping -c 1 -W 1 10.10.10.10"

# DNS funktioniert?
check "DNS resolution" "getent hosts google.com"

# Default Route vorhanden?
check "Default route exists" "ip route | grep -q default"

echo "[NET] Health check finished."

if [[ $FAILED -ne 0 ]]; then
  echo "[NET] Network health: FAILED"
  exit 1
else
  echo "[NET] Network health: OK"
  exit 0
fi
