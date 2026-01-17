#!/bin/bash

# Test script for ATProto PDS HTTP server
# Tests server startup and HTTP header formatting

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting ATProto PDS server test...${NC}"

# Build paths
# Use CMake build path
CLI_PATH="./build/bin/september"
TEST_PORT=2583
TEST_URL="http://localhost:${TEST_PORT}/explore"

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

# Test 1: Check if server is responding
echo -e "${YELLOW}Test 1: Basic connectivity${NC}"
if curl -s --max-time 5 "$TEST_URL" > /dev/null; then
    echo -e "${GREEN}✓ Server is responding${NC}"
else
    echo -e "${RED}✗ Server not responding${NC}"
    exit 1
fi

# Test 2: Check HTTP status and headers
echo -e "${YELLOW}Test 2: HTTP headers${NC}"
RESPONSE=$(curl -s -I --max-time 5 "$TEST_URL")
echo "Response headers:"
echo "$RESPONSE"
echo "---"

# Check for proper HTTP status line
if echo "$RESPONSE" | grep -q "^HTTP/1.1 200 OK"; then
    echo -e "${GREEN}✓ Correct HTTP status line${NC}"
else
    echo -e "${RED}✗ Incorrect HTTP status line${NC}"
    exit 1
fi

# Check for Content-Type header
if echo "$RESPONSE" | grep -q "^Content-Type:"; then
    echo -e "${GREEN}✓ Content-Type header present${NC}"
else
    echo -e "${RED}✗ Content-Type header missing${NC}"
    exit 1
fi

# Check for Content-Length header
if echo "$RESPONSE" | grep -q "^Content-Length:"; then
    echo -e "${GREEN}✓ Content-Length header present${NC}"
else
    echo -e "${RED}✗ Content-Length header missing${NC}"
    exit 1
fi

# Check for Connection header (should be keep-alive)
if echo "$RESPONSE" | grep -q "^Connection: keep-alive"; then
    echo -e "${GREEN}✓ Connection: keep-alive header correct${NC}"
else
    echo -e "${RED}✗ Connection header incorrect or missing${NC}"
    exit 1
fi

# Test 3: Check response body
echo -e "${YELLOW}Test 3: Response body${NC}"
BODY=$(curl -s --max-time 5 "$TEST_URL")
if [ -n "$BODY" ]; then
    echo -e "${GREEN}✓ Response body present${NC}"
    echo "Body length: ${#BODY} characters"
    # Try to parse as JSON
    if echo "$BODY" | jq . >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Response is valid JSON${NC}"
    else
        echo -e "${YELLOW}⚠ Response is not JSON (might be expected)${NC}"
    fi
else
    echo -e "${RED}✗ Empty response body${NC}"
    exit 1
fi

# Test 4: Check for malformed headers (should not contain "Connection: Connection: keep-alive")
echo -e "${YELLOW}Test 4: Header formatting${NC}"
if echo "$RESPONSE" | grep -q "Connection: Connection:"; then
    echo -e "${RED}✗ Malformed headers detected (double header names)${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Headers properly formatted${NC}"
fi

echo -e "${GREEN}All tests passed! 🎉${NC}"