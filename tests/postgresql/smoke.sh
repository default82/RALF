#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PostgreSQL Smoke Test
# Prueft ob PostgreSQL erreichbar ist und Verbindungen akzeptiert.
# ============================================================

PG_HOST="${PG_HOST:-10.10.20.10}"
PG_PORT="${PG_PORT:-5432}"

echo "POSTGRESQL SMOKE TEST"
echo "  Host: ${PG_HOST}"
echo "  Port: ${PG_PORT}"
echo "  Timestamp: $(date -Is)"
echo ""

FAILED=0

# 1. TCP-Verbindung
echo -n "  TCP-Port ${PG_PORT} erreichbar ... "
if timeout 5 bash -c "echo > /dev/tcp/${PG_HOST}/${PG_PORT}" 2>/dev/null; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 2. Ping
echo -n "  Host erreichbar (ping) ... "
if ping -c 1 -W 2 "$PG_HOST" >/dev/null 2>&1; then
  echo "OK"
else
  echo "FAIL"
  FAILED=1
fi

# 3. pg_isready (wenn verfuegbar)
echo -n "  pg_isready ... "
if command -v pg_isready >/dev/null 2>&1; then
  if pg_isready -h "$PG_HOST" -p "$PG_PORT" -t 5 >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    FAILED=1
  fi
else
  echo "SKIP (pg_isready nicht installiert)"
fi

echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "POSTGRESQL SMOKE: FAILED"
  exit 1
else
  echo "POSTGRESQL SMOKE: OK"
  exit 0
fi
