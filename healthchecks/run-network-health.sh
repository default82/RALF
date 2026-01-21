#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Resolve repository root (so the script works from anywhere)
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ------------------------------------------------------------
# Load runtime configuration (single source of truth)
# ------------------------------------------------------------
if [[ -f "$REPO_ROOT/inventory/runtime.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/inventory/runtime.env"
else
  echo "[NET] Missing inventory/runtime.env"
  exit 1
fi

# ------------------------------------------------------------
# Required variables (fail fast if missing)
# ------------------------------------------------------------
: "${GATEWAY_IP:?Missing GATEWAY_IP}"
: "${PROXMOX_IP:?Missing PROXMOX_IP}"
: "${DNS_TEST_HOST:=google.com}"

echo "[NET] Starting network health check..."

FAILED=0

check() {
  local description="$1"
  local command="$2"

  echo -n "[NET] $description ... "
  if eval "$command" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    FAILED=1
  fi
}

# ------------------------------------------------------------
# Actual health checks
# ------------------------------------------------------------

check "Gateway reachable (opnsense)" "ping -c 1 -W 1 $GATEWAY_IP"
check "Proxmox reachable (pve-deploy)" "ping -c 1 -W 1 $PROXMOX_IP"
check "DNS resolution" "getent hosts $DNS_TEST_HOST"
check "Default route exists" "ip route | grep -q default"

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------
echo "[NET] Health check finished."

if [[ $FAILED -ne 0 ]]; then
  echo "[NET] Network health: FAILED"
  exit 1
else
  echo "[NET] Network health: OK"
  exit 0
fi
