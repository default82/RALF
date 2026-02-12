#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Gitea Smoke Test
# Prueft ob Gitea erreichbar ist (HTTP + SSH).
# ============================================================

GITEA_HOST="${GITEA_HOST:-10.10.20.12}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-2222}"

echo "GITEA SMOKE TEST"
echo "  Host: ${GITEA_HOST}"
echo "  HTTP: ${GITEA_HTTP_PORT}"
echo "  SSH:  ${GITEA_SSH_PORT}"
echo "  Timestamp: $(date -Is)"
echo ""

FAILED=0

# 1. HTTP erreichbar
echo -n "  HTTP :${GITEA_HTTP_PORT} erreichbar ... "
if curl -sf --connect-timeout 5 --max-time 10 "http://${GITEA_HOST}:${GITEA_HTTP_PORT}" -o /dev/null 2>/dev/null; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 2. SSH-Port erreichbar
echo -n "  SSH :${GITEA_SSH_PORT} erreichbar ... "
if timeout 5 bash -c "echo > /dev/tcp/${GITEA_HOST}/${GITEA_SSH_PORT}" 2>/dev/null; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 3. Ping
echo -n "  Host erreichbar (ping) ... "
if ping -c 1 -W 2 "$GITEA_HOST" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 4. API Health (Gitea hat /api/v1/version)
echo -n "  API /api/v1/version ... "
if curl -sf --connect-timeout 5 --max-time 10 "http://${GITEA_HOST}:${GITEA_HTTP_PORT}/api/v1/version" >/dev/null 2>/dev/null; then
  echo "OK"
else
  echo "FAIL (evtl. noch Ersteinrichtung noetig)"
  FAILED=1
fi

echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "GITEA SMOKE: FAILED"
  exit 1
else
  echo "GITEA SMOKE: OK"
  exit 0
fi
