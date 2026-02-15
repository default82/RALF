#!/usr/bin/env bash
# RALF Regression Test Suite
# Runs all smoke tests sequentially and provides summary

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
SERVICES_PASSED=0
SERVICES_FAILED=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

echo ""
echo "========================================"
echo "RALF REGRESSION TEST SUITE"
echo "========================================"
echo ""

# Find all smoke test scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_TESTS=$(find "$SCRIPT_DIR" -name "smoke.sh" -type f | sort)

if [ -z "$SMOKE_TESTS" ]; then
    echo -e "${RED}ERROR: No smoke tests found${NC}"
    exit 1
fi

TOTAL_SERVICES=$(echo "$SMOKE_TESTS" | wc -l)
CURRENT=0

# Run each test
while IFS= read -r test_script; do
    CURRENT=$((CURRENT + 1))
    SERVICE=$(basename "$(dirname "$test_script")")

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}[$CURRENT/$TOTAL_SERVICES] $SERVICE${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Run test
    if bash "$test_script" > /tmp/smoke-$SERVICE.log 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        SERVICES_PASSED=$((SERVICES_PASSED + 1))

        # Parse counts if available
        P=$(grep -oP 'Passed:\s*\K\d+' /tmp/smoke-$SERVICE.log 2>/dev/null | head -1 || echo "1")
        F=$(grep -oP 'Failed:\s*\K\d+' /tmp/smoke-$SERVICE.log 2>/dev/null | head -1 || echo "0")
        S=$(grep -oP 'Skipped:\s*\K\d+' /tmp/smoke-$SERVICE.log 2>/dev/null | head -1 || echo "0")
    else
        echo -e "${RED}✗ FAIL${NC}"
        SERVICES_FAILED=$((SERVICES_FAILED + 1))
        tail -5 /tmp/smoke-$SERVICE.log
        P=0
        F=1
        S=0
    fi

    TOTAL_PASSED=$((TOTAL_PASSED + P))
    TOTAL_FAILED=$((TOTAL_FAILED + F))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + S))
    echo ""
done <<< "$SMOKE_TESTS"

# Summary
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo -e "${GREEN}Services Passed:${NC} $SERVICES_PASSED/$TOTAL_SERVICES"
echo -e "${RED}Services Failed:${NC} $SERVICES_FAILED/$TOTAL_SERVICES"
echo "Total Tests: Passed=$TOTAL_PASSED Failed=$TOTAL_FAILED Skipped=$TOTAL_SKIPPED"
echo ""

if [ $SERVICES_FAILED -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ All services passed!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ Some services failed!${NC}"
    exit 1
fi
