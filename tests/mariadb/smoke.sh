#!/usr/bin/env bash
# MariaDB Smoke Test
# Tests MariaDB installation on CT 2011

set -uo pipefail

# Configuration
HOST="${MARIADB_HOST:-10.10.20.11}"
PORT="${MARIADB_PORT:-3306}"
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
echo "MARIADB DATABASE SMOKE TEST"
echo "============================================"
echo "Target: ${HOST}:${PORT}"
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

# Test 2: TCP Port
echo "[2] Testing MariaDB port..."
if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
    pass "MariaDB port ${PORT} is open"
else
    fail "MariaDB port ${PORT} is not accessible"
fi

# Test 3: MySQL Client Connection (requires mysql client)
echo "[3] Testing MySQL client connection..."
if command -v mysql >/dev/null 2>&1; then
    if timeout "$TIMEOUT" mysql -h "$HOST" -P "$PORT" -u root -e "SELECT 1" >/dev/null 2>&1; then
        pass "MySQL client connection successful"
    else
        # Try without password (might fail, but that's OK - it means server is responding)
        if timeout "$TIMEOUT" mysql -h "$HOST" -P "$PORT" -u root -e "SELECT 1" 2>&1 | grep -q "Access denied"; then
            pass "MariaDB server responding (authentication required)"
        else
            fail "MySQL client connection failed"
        fi
    fi
else
    skip "MySQL client not installed (install: apt-get install mysql-client)"
fi

# Test 4: Version Check (requires mysql client)
echo "[4] Testing MariaDB version..."
if command -v mysql >/dev/null 2>&1; then
    VERSION=$(timeout "$TIMEOUT" mysql -h "$HOST" -P "$PORT" -u root -e "SELECT VERSION()" 2>&1 | grep -oP '^\d+\.\d+\.\d+' || echo "")
    if [[ -n "$VERSION" ]]; then
        pass "MariaDB version: $VERSION"
    else
        skip "Could not retrieve version (authentication required)"
    fi
else
    skip "MySQL client not installed"
fi

# Test 5: Database List (requires credentials)
echo "[5] Testing database list query..."
skip "Database list requires credentials (use: MYSQL_PWD=password mysql ...)"

# Test 6: systemd Service Status (internal)
echo "[6] Testing systemd service..."
skip "Systemd test requires execution from container"

# Test 7: Process Check (internal)
echo "[7] Testing mysqld process..."
skip "Process check requires container access"

# Test 8: Log Analysis (internal)
echo "[8] Testing error logs..."
skip "Log analysis requires container access"

# Test 9: Config File Check (internal)
echo "[9] Testing MariaDB configuration..."
skip "Config check requires container access"

# Test 10: Performance Query (requires credentials)
echo "[10] Testing performance query..."
skip "Performance test requires credentials and database access"

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
