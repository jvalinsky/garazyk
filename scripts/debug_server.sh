#!/bin/bash

# Debug server startup script

set -e

echo "🔍 Debugging server startup..."

# Use CMake build path
CLI_PATH="./build/bin/september"
TEST_PORT=2583

echo "Testing server startup..."
echo "Command: $CLI_PATH serve --port $TEST_PORT --verbose"

# Start server in background and capture output
$CLI_PATH serve --port $TEST_PORT --verbose &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

# Wait a bit
sleep 2

# Check if process is still running
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process is running"
else
    echo "❌ Server process exited immediately"
    exit 1
fi

# Test if port is listening
if lsof -i :$TEST_PORT > /dev/null 2>&1; then
    echo "✅ Port $TEST_PORT is listening"
else
    echo "❌ Port $TEST_PORT is not listening"
fi

# Try a quick curl test
echo "Testing HTTP request..."
if curl -s --max-time 2 "http://localhost:$TEST_PORT/explore" > /dev/null; then
    echo "✅ HTTP request succeeded"
else
    echo "❌ HTTP request failed"
fi

# Kill the server
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

echo "Debug complete"