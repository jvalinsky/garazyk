#!/bin/bash

# Full page load simulation - tests how a browser would load the explore page

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌐 Simulating full browser page load...${NC}"

# CLI path
# Use CMake build path
CLI_PATH="./build/bin/kaszlak"
TEST_PORT=2583

# Function to cleanup background processes
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
}

# Set trap to cleanup on script exit
trap cleanup EXIT

echo "Starting server on port ${TEST_PORT}..."
$CLI_PATH serve --port $TEST_PORT &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

# Wait for server to start up
echo "Waiting for server to start..."
sleep 3

echo -e "${YELLOW}Simulating browser page load sequence...${NC}"

# 1. Load main HTML page
echo -e "${BLUE}1. Loading HTML page...${NC}"
START=$(date +%s%3N)
HTML=$(curl -s "http://localhost:${TEST_PORT}/explore")
END=$(date +%s%3N)
HTML_TIME=$((END - START))
echo "   HTML loaded in: ${HTML_TIME}ms"

# 2. Extract and load CSS (simulating browser parsing HTML and finding <link> tags)
echo -e "${BLUE}2. Loading CSS...${NC}"
START=$(date +%s%3N)
CSS=$(curl -s "http://localhost:${TEST_PORT}/explore/css/style.css")
END=$(date +%s%3N)
CSS_TIME=$((END - START))
echo "   CSS loaded in: ${CSS_TIME}ms"

# 3. Extract and load JS (simulating browser parsing HTML and finding <script> tags)
echo -e "${BLUE}3. Loading JavaScript...${NC}"
START=$(date +%s%3N)
JS=$(curl -s "http://localhost:${TEST_PORT}/explore/js/ui.js")
END=$(date +%s%3N)
JS_TIME=$((END - START))
echo "   JS loaded in: ${JS_TIME}ms"

# 4. Simulate user clicking "Accounts" - load accounts data
echo -e "${BLUE}4. Loading accounts data (user interaction)...${NC}"
START=$(date +%s%3N)
ACCOUNTS=$(curl -s "http://localhost:${TEST_PORT}/explore/api/accounts")
END=$(date +%s%3N)
ACCOUNTS_TIME=$((END - START))
echo "   Accounts API loaded in: ${ACCOUNTS_TIME}ms"

# Calculate total page load time
TOTAL_TIME=$((HTML_TIME + CSS_TIME + JS_TIME))
echo ""
echo -e "${GREEN}📊 Page Load Breakdown:${NC}"
echo "   HTML:     ${HTML_TIME}ms"
echo "   CSS:      ${CSS_TIME}ms"  
echo "   JS:       ${JS_TIME}ms"
echo "   Accounts: ${ACCOUNTS_TIME}ms"
echo "   ──────────────────"
echo "   Total:    ${TOTAL_TIME}ms"

# Check resource sizes
HTML_SIZE=${#HTML}
CSS_SIZE=${#CSS}
JS_SIZE=${#JS}
ACCOUNTS_SIZE=${#ACCOUNTS}

echo ""
echo -e "${GREEN}📏 Resource Sizes:${NC}"
echo "   HTML:     ${HTML_SIZE} bytes"
echo "   CSS:      ${CSS_SIZE} bytes"
echo "   JS:       ${JS_SIZE} bytes"  
echo "   Accounts: ${ACCOUNTS_SIZE} bytes"

# Check for potential issues
ISSUES=0

if [ $TOTAL_TIME -gt 500 ]; then
    echo -e "${RED}❌ CRITICAL: Total page load > 500ms (${TOTAL_TIME}ms)${NC}"
    ISSUES=$((ISSUES + 1))
elif [ $TOTAL_TIME -gt 200 ]; then
    echo -e "${YELLOW}⚠️  WARNING: Total page load > 200ms (${TOTAL_TIME}ms)${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✅ Good: Total page load < 200ms${NC}"
fi

if [ $ACCOUNTS_TIME -gt 100 ]; then
    echo -e "${RED}❌ CRITICAL: Accounts API > 100ms (${ACCOUNTS_TIME}ms)${NC}"
    ISSUES=$((ISSUES + 1))
elif [ $ACCOUNTS_TIME -gt 50 ]; then
    echo -e "${YELLOW}⚠️  WARNING: Accounts API > 50ms (${ACCOUNTS_TIME}ms)${NC}"
    ISSUES=$((ISSUES + 1))
fi

# Check if resources loaded successfully
if [ $HTML_SIZE -lt 100 ]; then
    echo -e "${RED}❌ ERROR: HTML too small (${HTML_SIZE} bytes)${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ $CSS_SIZE -lt 50 ]; then
    echo -e "${RED}❌ ERROR: CSS too small (${CSS_SIZE} bytes)${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ $JS_SIZE -lt 100 ]; then
    echo -e "${RED}❌ ERROR: JS too small (${JS_SIZE} bytes)${NC}"
    ISSUES=$((ISSUES + 1))
fi

echo ""
if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}🎉 All page load tests passed!${NC}"
else
    echo -e "${RED}❌ Found ${ISSUES} issues with page loading${NC}"
fi