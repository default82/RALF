#!/usr/bin/env bash
# NetBox IPAM/DCIM Smoke Test
# Tests NetBox installation on CT 4030

set -uo pipefail

# Configuration
HOST="${NETBOX_HOST:-10.10.40.30}"
GUNICORN_PORT="${NETBOX_GUNICORN_PORT:-8000}"
NGINX_PORT="${NETBOX_NGINX_PORT:-80}"
REDIS_PORT="6379"
POSTGRES_HOST="10.10.20.10"
POSTGRES_PORT="5432"
TIMEOUT=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

echo "============================================"
echo "NETBOX IPAM/DCIM SMOKE TEST"
echo "============================================"
echo "Target: ${HOST}"
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    ((SKIPPED++))
}

# Test 1: Ping
echo "[1] Testing network connectivity..."
if ping -c 1 -W "$TIMEOUT" "$HOST" >/dev/null 2>&1; then
    pass "Host $HOST is reachable"
else
    fail "Host $HOST is not reachable"
fi

# Test 2: nginx HTTP
echo "[2] Testing nginx HTTP endpoint..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${HOST}/${NGINX_PORT}" 2>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${NGINX_PORT}" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
        pass "nginx responds with HTTP $HTTP_CODE on port ${NGINX_PORT}"
    else
        fail "nginx responded with HTTP $HTTP_CODE (expected 200 or 302)"
    fi
else
    fail "nginx port ${NGINX_PORT} not accessible"
fi

# Test 3: Gunicorn HTTP
echo "[3] Testing gunicorn HTTP endpoint..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${HOST}/${GUNICORN_PORT}" 2>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${GUNICORN_PORT}" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
        pass "Gunicorn responds with HTTP $HTTP_CODE on port ${GUNICORN_PORT}"
    else
        fail "Gunicorn responded with HTTP $HTTP_CODE (expected 200 or 302)"
    fi
else
    fail "Gunicorn port ${GUNICORN_PORT} not accessible"
fi

# Test 4: NetBox API
echo "[4] Testing NetBox API..."
API_RESPONSE=$(curl -s "http://${HOST}/api/" 2>/dev/null || echo "{}")
if echo "$API_RESPONSE" | grep -q "circuits"; then
    pass "NetBox API is accessible"
else
    fail "NetBox API not responding correctly"
fi

# Test 5: PostgreSQL connectivity
echo "[5] Testing PostgreSQL connectivity..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${POSTGRES_HOST}/${POSTGRES_PORT}" 2>/dev/null; then
    pass "PostgreSQL server ${POSTGRES_HOST}:${POSTGRES_PORT} is reachable"
else
    fail "PostgreSQL server not reachable"
fi

# Test 6: Redis connectivity (localhost, must run from container)
echo "[6] Testing Redis connectivity..."
skip "Redis test requires execution from container (localhost:${REDIS_PORT})"

# Test 7: NetBox systemd service
echo "[7] Testing NetBox systemd service..."
skip "Systemd test requires execution from container"

# Test 8: nginx systemd service
echo "[8] Testing nginx systemd service..."
skip "Systemd test requires execution from container"

# Test 9: Redis systemd service
echo "[9] Testing Redis systemd service..."
skip "Systemd test requires execution from container"

# Test 10: NetBox version
echo "[10] Testing NetBox version..."
skip "Version test requires execution from container"

# Summary
echo ""
echo "============================================"
echo "SUMMARY"
echo "============================================"
echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${RED}Failed:${NC}  $FAILED"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
echo "Total:   $((PASSED + FAILED + SKIPPED))"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit 1
fi
