#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Semaphore Smoke Test
# Prueft ob Semaphore erreichbar ist und korrekt konfiguriert.
# ============================================================

SEMAPHORE_HOST="${SEMAPHORE_HOST:-10.10.100.15}"
SEMAPHORE_HTTP_PORT="${SEMAPHORE_HTTP_PORT:-3000}"
SEMAPHORE_CTID="${SEMAPHORE_CTID:-10015}"

echo "SEMAPHORE SMOKE TEST"
echo "  Host: ${SEMAPHORE_HOST}"
echo "  HTTP: ${SEMAPHORE_HTTP_PORT}"
echo "  CT-ID: ${SEMAPHORE_CTID}"
echo "  Timestamp: $(date -Is)"
echo ""

FAILED=0

# 1. Ping
echo -n "  Host erreichbar (ping) ... "
if ping -c 1 -W 2 "$SEMAPHORE_HOST" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 2. HTTP erreichbar
echo -n "  HTTP :${SEMAPHORE_HTTP_PORT} erreichbar ... "
if timeout 5 bash -c "echo > /dev/tcp/${SEMAPHORE_HOST}/${SEMAPHORE_HTTP_PORT}" 2>/dev/null; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 3. API Health (/api/ping)
echo -n "  API /api/ping ... "
if curl -sf --connect-timeout 5 --max-time 10 "http://${SEMAPHORE_HOST}:${SEMAPHORE_HTTP_PORT}/api/ping" >/dev/null 2>/dev/null; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 4. Service Status (systemctl)
echo -n "  Semaphore Service ... "
if pct exec "$SEMAPHORE_CTID" -- systemctl is-active semaphore >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 5. Configuration Marker (optional check)
echo -n "  Auto-Configure Status ... "
if pct exec "$SEMAPHORE_CTID" -- test -f /root/.semaphore-configured 2>/dev/null; then
  echo "OK (configured)"
else
  echo "SKIP (not auto-configured)"
fi

echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "SEMAPHORE SMOKE: FAILED"
  exit 1
else
  echo "SEMAPHORE SMOKE: OK"
  exit 0
fi
