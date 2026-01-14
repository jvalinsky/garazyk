#!/bin/bash

# Test OAuth2 endpoints - quick curl test script

echo "=== OAuth2 Endpoint Testing ==="

BASE_URL="http://localhost:2583"
CLIENT_ID="test-client"
REDIRECT_URI="http://localhost:3000/callback"
SCOPE="atproto:identify"

echo ""
echo "1. Testing Authorization Endpoint"
echo "GET /oauth/authorize"

AUTH_URL="${BASE_URL}/oauth/authorize?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&response_type=code&scope=${SCOPE}&state=test123"

echo "Request: ${AUTH_URL}"
echo "Response:"
curl -v "${AUTH_URL}" 2>&1

echo ""
echo ""
echo "2. Testing Token Endpoint"
echo "POST /oauth/token"

TOKEN_DATA="grant_type=authorization_code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&code=test-code&code_verifier=test-verifier"

echo "Request: POST ${BASE_URL}/oauth/token"
echo "Data: ${TOKEN_DATA}"
echo "Response:"
curl -v -X POST "${BASE_URL}/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "${TOKEN_DATA}" 2>&1

echo ""
echo ""
echo "3. Testing Revoke Endpoint"
echo "POST /oauth/revoke"

REVOKE_DATA="client_id=${CLIENT_ID}&token=test-token"

echo "Request: POST ${BASE_URL}/oauth/revoke"
echo "Data: ${REVOKE_DATA}"
echo "Response:"
curl -v -X POST "${BASE_URL}/oauth/revoke" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "${REVOKE_DATA}" 2>&1

echo ""
echo "=== Testing Complete ==="