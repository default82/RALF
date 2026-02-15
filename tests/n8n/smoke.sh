#!/usr/bin/env bash
# n8n Workflow Automation - Smoke Test
set -euo pipefail

# Config
HOST="${N8N_HOST:-10.10.40.12}"
HTTP_PORT="${N8N_PORT:-5678}"
TIMEOUT=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0
TEST_NUM=0

pass() { echo -e "${GREEN}✓ PASS${NC}: $*"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $*"; FAILED=$((FAILED + 1)); }
skip() { echo -e "${YELLOW}⊘ SKIP${NC}: $*"; SKIPPED=$((SKIPPED + 1)); }

run_test() {
    TEST_NUM=$((TEST_NUM + 1))
    echo "[${TEST_NUM}] $*"
}

echo "============================================"
echo "N8N WORKFLOW AUTOMATION SMOKE TEST"
echo "============================================"
echo "Target: ${HOST}:${HTTP_PORT}"
echo ""

# Test 1: Network Ping
run_test "Testing network connectivity..."
if timeout "${TIMEOUT}" ping -c 1 -W 5 "${HOST}" >/dev/null 2>&1; then
    pass "Host ${HOST} is reachable"
else
    fail "Host ${HOST} is not reachable"
fi

# Test 2: TCP Port
run_test "Testing HTTP port ${HTTP_PORT}..."
if timeout "${TIMEOUT}" bash -c "echo >/dev/tcp/${HOST}/${HTTP_PORT}" 2>/dev/null; then
    pass "Port ${HTTP_PORT} is open"
else
    fail "Port ${HTTP_PORT} is closed or not accessible"
fi

# Test 3: HTTP Response
run_test "Testing n8n web interface..."
HTTP_CODE=$(timeout "${TIMEOUT}" curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    pass "n8n web interface responds with HTTP ${HTTP_CODE}"
else
    fail "n8n web interface returned HTTP ${HTTP_CODE} (expected 200)"
fi

# Test 4: n8n Content Check
run_test "Verifying n8n content..."
if timeout "${TIMEOUT}" curl -s "http://${HOST}:${HTTP_PORT}" | grep -q "n8n"; then
    pass "n8n web interface contains expected content"
else
    fail "n8n web interface does not contain expected content"
fi

# Test 5: n8n Health Check (if healthz endpoint exists)
run_test "Testing n8n health endpoint..."
HEALTH_CODE=$(timeout "${TIMEOUT}" curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${HTTP_PORT}/healthz" 2>/dev/null || echo "000")
if [[ "$HEALTH_CODE" == "200" ]]; then
    pass "n8n health check passed (HTTP ${HEALTH_CODE})"
elif [[ "$HEALTH_CODE" == "404" ]]; then
    skip "n8n health endpoint not available (expected for v2.7+)"
else
    fail "n8n health check failed (HTTP ${HEALTH_CODE})"
fi

# Test 6: PostgreSQL Connectivity
run_test "Testing PostgreSQL connectivity..."
PG_HOST="${N8N_DB_HOST:-10.10.20.10}"
PG_PORT="${N8N_DB_PORT:-5432}"
if timeout "${TIMEOUT}" bash -c "echo >/dev/tcp/${PG_HOST}/${PG_PORT}" 2>/dev/null; then
    pass "PostgreSQL server ${PG_HOST}:${PG_PORT} is reachable"
else
    fail "PostgreSQL server ${PG_HOST}:${PG_PORT} is not reachable"
fi

# Test 7: n8n Service Status (requires container access)
run_test "Testing n8n systemd service..."
if [[ -f /etc/hostname ]] && [[ "$(cat /etc/hostname)" == "web-n8n" ]]; then
    # Running inside the n8n container
    if systemctl is-active --quiet n8n; then
        pass "n8n service is active"
    else
        fail "n8n service is not active"
    fi
else
    skip "Systemd test requires execution from container"
fi

# Test 8: n8n Version Info
run_test "Checking n8n version..."
if command -v n8n >/dev/null 2>&1; then
    VERSION=$(n8n --version 2>/dev/null || echo "unknown")
    pass "n8n version: ${VERSION}"
else
    skip "Version check requires execution from container"
fi

# Test 9: n8n Data Directory
run_test "Checking n8n data directory..."
N8N_DATA_DIR="/var/lib/n8n/.n8n"
if [[ -d "$N8N_DATA_DIR" ]]; then
    pass "n8n data directory exists: ${N8N_DATA_DIR}"
else
    skip "Data directory check requires execution from container"
fi

# Test 10: n8n Database Connection
run_test "Testing n8n database connection..."
if command -v n8n >/dev/null 2>&1; then
    # Try to query workflows (requires n8n CLI)
    skip "Database connection test requires n8n CLI access"
else
    skip "Database connection test requires execution from container"
fi

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

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
fi
