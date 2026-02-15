#!/usr/bin/env bash
# Dashy Dashboard Smoke Test
# Tests Dashy installation on CT 4001

set -uo pipefail

# Configuration
HOST="${DASHY_HOST:-10.10.40.11}"
DASHY_PORT="${DASHY_PORT:-4000}"
CORS_PORT="${DASHY_CORS_PORT:-8080}"
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
echo "DASHY DASHBOARD SMOKE TEST"
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

# Test 2: Dashy HTTP (npm dev server)
echo "[2] Testing Dashy HTTP endpoint..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${HOST}/${DASHY_PORT}" 2>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${DASHY_PORT}" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        pass "Dashy responds with HTTP $HTTP_CODE on port ${DASHY_PORT}"
    else
        fail "Dashy responded with HTTP $HTTP_CODE (expected 200)"
    fi
else
    fail "Dashy port ${DASHY_PORT} not accessible"
fi

# Test 3: CORS Proxy HTTP
echo "[3] Testing CORS Proxy endpoint..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${HOST}/${CORS_PORT}" 2>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${CORS_PORT}/postgres/" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        pass "CORS Proxy responds with HTTP $HTTP_CODE on port ${CORS_PORT}"
    else
        fail "CORS Proxy responded with HTTP $HTTP_CODE (expected 200)"
    fi
else
    fail "CORS Proxy port ${CORS_PORT} not accessible"
fi

# Test 4: CORS Proxy - Gitea endpoint
echo "[4] Testing CORS Proxy - Gitea endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${CORS_PORT}/gitea/api/v1/version" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "CORS Proxy /gitea/ endpoint accessible"
else
    fail "CORS Proxy /gitea/ endpoint failed (HTTP $HTTP_CODE)"
fi

# Test 5: CORS Proxy - Semaphore endpoint
echo "[5] Testing CORS Proxy - Semaphore endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${CORS_PORT}/semaphore/api/ping" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|401)$ ]]; then
    pass "CORS Proxy /semaphore/ endpoint accessible (HTTP $HTTP_CODE)"
else
    fail "CORS Proxy /semaphore/ endpoint failed (HTTP $HTTP_CODE)"
fi

# Test 6: CORS Proxy - Vaultwarden endpoint
echo "[6] Testing CORS Proxy - Vaultwarden endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${CORS_PORT}/vault/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
    pass "CORS Proxy /vault/ endpoint accessible (HTTP $HTTP_CODE)"
else
    fail "CORS Proxy /vault/ endpoint failed (HTTP $HTTP_CODE)"
fi

# Test 7: CORS Proxy - NetBox endpoint
echo "[7] Testing CORS Proxy - NetBox endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${CORS_PORT}/netbox/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
    pass "CORS Proxy /netbox/ endpoint accessible (HTTP $HTTP_CODE)"
else
    fail "CORS Proxy /netbox/ endpoint failed (HTTP $HTTP_CODE)"
fi

# Test 8: CORS Proxy - Snipe-IT endpoint
echo "[8] Testing CORS Proxy - Snipe-IT endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${CORS_PORT}/snipeit/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|302)$ ]]; then
    pass "CORS Proxy /snipeit/ endpoint accessible (HTTP $HTTP_CODE)"
else
    skip "CORS Proxy /snipeit/ endpoint unavailable (HTTP $HTTP_CODE) - service may be down"
fi

# Test 9: Dashy systemd service
echo "[9] Testing Dashy systemd service..."
skip "Systemd test requires execution from container"

# Test 10: nginx systemd service
echo "[10] Testing nginx systemd service..."
skip "Systemd test requires execution from container"

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
