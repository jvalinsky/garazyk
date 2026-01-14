#!/bin/bash

# Test the new getUserStats endpoint
echo "Testing getUserStats endpoint..."

# Test with user parameter
echo "Test 1: GET /xrpc/app.bsky.user.getUserStats?user=testuser"
curl -s "http://localhost:3000/xrpc/app.bsky.user.getUserStats?user=testuser" | jq '.'

# Test without user parameter (should return error)
echo -e "\nTest 2: GET /xrpc/app.bsky.user.getUserStats (missing user parameter)"
curl -s "http://localhost:3000/xrpc/app.bsky.user.getUserStats" | jq '.'

echo -e "\nTest completed."