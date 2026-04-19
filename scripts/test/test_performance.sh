#!/bin/bash

# Performance test script for ATProto PDS server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Performance testing ATProto PDS server...${NC}"

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
$CLI_PATH serve --port $TEST_PORT --verbose &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

# Wait for server to start up
echo "Waiting for server to start..."
sleep 3

# Test basic connectivity
echo -e "${YELLOW}Testing basic connectivity...${NC}"
START=$(date +%s%3N)
curl -s "http://localhost:${TEST_PORT}/explore" > /dev/null
END=$(date +%s%3N)
HTML_TIME=$((END - START))
echo "HTML page load time: ${HTML_TIME}ms"

# Test API endpoint
echo -e "${YELLOW}Testing API endpoint...${NC}"
START=$(date +%s%3N)
curl -s "http://localhost:${TEST_PORT}/api/pds/accounts" > /dev/null
END=$(date +%s%3N)
API_TIME=$((END - START))
echo "API response time: ${API_TIME}ms"

# Test static files
echo -e "${YELLOW}Testing static files...${NC}"
START=$(date +%s%3N)
curl -s "http://localhost:${TEST_PORT}/css/explore.css" > /dev/null
END=$(date +%s%3N)
CSS_TIME=$((END - START))
echo "CSS load time: ${CSS_TIME}ms"

START=$(date +%s%3N)
curl -s "http://localhost:${TEST_PORT}/js/ui.js" > /dev/null
END=$(date +%s%3N)
JS_TIME=$((END - START))
echo "JS load time: ${JS_TIME}ms"

# Run multiple requests to check for consistency
echo -e "${YELLOW}Testing request consistency (10 requests)...${NC}"
TIMES=()
for i in {1..10}; do
    START=$(date +%s%3N)
    curl -s "http://localhost:${TEST_PORT}/explore" > /dev/null
    END=$(date +%s%3N)
    TIME=$((END - START))
    TIMES+=($TIME)
    echo -n "."
done
echo ""

# Calculate average
SUM=0
for time in "${TIMES[@]}"; do
    SUM=$((SUM + time))
done
AVG=$((SUM / ${#TIMES[@]}))
echo "Average response time: ${AVG}ms"

# Check for slow requests
SLOW_COUNT=0
for time in "${TIMES[@]}"; do
    if [ $time -gt 100 ]; then
        SLOW_COUNT=$((SLOW_COUNT + 1))
    fi
done

echo -e "${GREEN}Performance Results:${NC}"
echo "  HTML page: ${HTML_TIME}ms"
echo "  API call: ${API_TIME}ms"
echo "  CSS file: ${CSS_TIME}ms"
echo "  JS file: ${JS_TIME}ms"
echo "  Average (10 requests): ${AVG}ms"
echo "  Requests > 100ms: ${SLOW_COUNT}/10"

if [ $AVG -gt 100 ]; then
    echo -e "${RED}⚠️  WARNING: Average response time > 100ms - this is slow for local server${NC}"
elif [ $AVG -gt 50 ]; then
    echo -e "${YELLOW}⚠️  WARNING: Average response time > 50ms - could be improved${NC}"
else
    echo -e "${GREEN}✅ Good performance - average response time < 50ms${NC}"
fi

# Check server logs for any errors
echo -e "${YELLOW}Checking for server errors...${NC}"
ps -p $SERVER_PID > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Server is still running${NC}"
else
    echo -e "${RED}❌ Server crashed during testing${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Performance testing complete!${NC}"
