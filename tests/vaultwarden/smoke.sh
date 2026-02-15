#!/usr/bin/env bash
# Vaultwarden Password Manager Smoke Test
# Tests Vaultwarden installation on CT 3010

set -uo pipefail

# Configuration
HOST="${VAULTWARDEN_HOST:-10.10.30.10}"
HTTP_PORT="${VAULTWARDEN_PORT:-8080}"
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
echo "VAULTWARDEN PASSWORD MANAGER SMOKE TEST"
echo "============================================"
echo "Target: ${HOST}:${HTTP_PORT}"
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

# Test 2: HTTP Port
echo "[2] Testing HTTP port..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${HOST}/${HTTP_PORT}" 2>/dev/null; then
    pass "HTTP port ${HTTP_PORT} is open"
else
    fail "HTTP port ${HTTP_PORT} is not accessible"
fi

# Test 3: Web Vault
echo "[3] Testing Web Vault endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "Web Vault responds with HTTP $HTTP_CODE"
else
    fail "Web Vault responded with HTTP $HTTP_CODE (expected 200)"
fi

# Test 4: API Config Endpoint
echo "[4] Testing API config endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}/api/config" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "API config endpoint responds with HTTP $HTTP_CODE"
else
    fail "API config endpoint responded with HTTP $HTTP_CODE (expected 200)"
fi

# Test 5: API Version
echo "[5] Testing API version..."
VERSION=$(curl -s "http://${HOST}:${HTTP_PORT}/api/config" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "")
if [[ -n "$VERSION" && "$VERSION" != "null" ]]; then
    pass "API version: $VERSION"
else
    fail "Could not retrieve API version"
fi

# Test 6: Admin Panel (expects redirect/auth)
echo "[6] Testing Admin Panel endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}/admin" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|401|302)$ ]]; then
    pass "Admin Panel endpoint accessible (HTTP $HTTP_CODE)"
else
    fail "Admin Panel endpoint failed (HTTP $HTTP_CODE)"
fi

# Test 7: Alive/Health Check
echo "[7] Testing health check endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}/alive" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "Health check endpoint responds (HTTP $HTTP_CODE)"
else
    # Some versions might not have /alive, try /api
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}/api" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        pass "API endpoint responds (HTTP $HTTP_CODE)"
    else
        fail "Health check failed (HTTP $HTTP_CODE)"
    fi
fi

# Test 8: Docker Container (internal check - requires container access)
echo "[8] Testing Docker container status..."
skip "Docker container check requires container access"

# Test 9: systemd Service (internal check)
echo "[9] Testing systemd service..."
skip "Systemd test requires execution from container"

# Test 10: PostgreSQL Connectivity (internal check)
echo "[10] Testing PostgreSQL connectivity..."
skip "PostgreSQL test requires container access and credentials"

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
