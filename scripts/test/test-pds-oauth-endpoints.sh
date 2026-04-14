#!/bin/bash
# Test PDS OAuth endpoints without SSH dependency

PDS_URL="https://pds.garazyk.xyz"

echo "Testing PDS OAuth Endpoints at ${PDS_URL}"
echo "=========================================="
echo ""

# Test 1: OPTIONS /oauth/authorize
echo "Test 1: OPTIONS /oauth/authorize"
curl -X OPTIONS "${PDS_URL}/oauth/authorize" -i -s | head -20
echo ""
echo "---"
echo ""

# Test 2: OPTIONS /oauth/token  
echo "Test 2: OPTIONS /oauth/token"
curl -X OPTIONS "${PDS_URL}/oauth/token" -i -s | head -20
echo ""
echo "---"
echo ""

# Test 3: OPTIONS /oauth/par
echo "Test 3: OPTIONS /oauth/par"
curl -X OPTIONS "${PDS_URL}/oauth/par" -i -s | head -20
echo ""
echo "---"
echo ""

# Test 4: GET /oauth/authorize (should return 400 or redirect, not 502)
echo "Test 4: GET /oauth/authorize?client_id=test"
curl "${PDS_URL}/oauth/authorize?client_id=test" -i -s | head -20
echo ""
echo "---"
echo ""

# Test 5: OAuth metadata endpoint
echo "Test 5: GET /.well-known/oauth-authorization-server"
curl "${PDS_URL}/.well-known/oauth-authorization-server" -i -s | head -20
echo ""

echo "=========================================="
echo "Testing complete"
