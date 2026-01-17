#!/bin/bash

# Test script for static file serving and performance
# Tests CSS, JS, and HTML serving with timing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing static file serving and performance...${NC}"

# Build paths
# Use CMake build path
CLI_PATH="./build/bin/september"
TEST_PORT=2583
BASE_URL="http://localhost:${TEST_PORT}"

# Function to cleanup background processes
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
}

# Set trap to cleanup on script exit
trap cleanup EXIT

echo "Starting server on port ${TEST_PORT}..."
$CLI_PATH serve --verbose --port $TEST_PORT &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

# Wait for server to start up
echo "Waiting for server to start..."
sleep 3

# Function to test URL with timing
test_url() {
    local url=$1
    local expected_content_type=$2
    local description=$3

    echo -e "${YELLOW}Testing $description: $url${NC}"

    # Time the request
    local start_time=$(date +%s%3N)
    local response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" -H "Accept: */*" "$url" 2>/dev/null)
    local end_time=$(date +%s%3N)

    # Extract response time and status
    local http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local response_time=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    local body=$(echo "$response" | sed 's/HTTPSTATUS.*$//')

    # Check content type
    local content_type=$(curl -s -I "$url" 2>/dev/null | grep -i "content-type" | cut -d: -f2- | tr -d '\r' | sed 's/^[[:space:]]*//')

    echo "  Status: $http_status"
    echo "  Content-Type: '$content_type'"
    echo "  Response time: ${response_time}s"
    echo "  Body length: ${#body} chars"

    # Validate results
    if [ "$http_status" != "200" ]; then
        echo -e "${RED}  ✗ Expected status 200, got $http_status${NC}"
        return 1
    fi

    if [ -n "$expected_content_type" ] && [[ "$content_type" != *"$expected_content_type"* ]]; then
        echo -e "${RED}  ✗ Expected content-type containing '$expected_content_type', got '$content_type'${NC}"
        return 1
    fi

    # Check response time (warn if > 1 second)
    if (( $(echo "$response_time > 1.0" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "${RED}  ⚠ Response time > 1s: ${response_time}s${NC}"
    else
        echo -e "${GREEN}  ✓ Fast response (< 1s)${NC}"
    fi

    echo -e "${GREEN}  ✓ $description OK${NC}"
    return 0
}

# Test HTML page
test_url "$BASE_URL/explore" "text/html" "HTML page" || exit 1

# Test CSS file
test_url "$BASE_URL/explore/css/style.css" "text/css" "CSS file" || exit 1

# Test JS file
test_url "$BASE_URL/explore/js/ui.js" "application/javascript" "JavaScript file" || exit 1

# Test API endpoint
test_url "$BASE_URL/explore/api/accounts" "application/json" "API endpoint" || exit 1

# Test 404
echo -e "${YELLOW}Testing 404 handling...${NC}"
response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$BASE_URL/explore/nonexistent" 2>/dev/null)
http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
if [ "$http_status" = "404" ]; then
    echo -e "${GREEN}✓ 404 handling works${NC}"
else
    echo -e "${RED}✗ Expected 404, got $http_status${NC}"
    exit 1
fi

echo -e "${GREEN}All static file tests passed! 🎉${NC}"