#!/bin/bash
set -e

PDS_HOST="${PDS_HOST:-pds.garazyk.xyz}"
PDS_URL="https://${PDS_HOST}"

echo "==================================="
echo "PDS Integration Testing"
echo "==================================="
echo "Target: ${PDS_URL}"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

echo "=== 1. Checking PDS Service Status ==="
if ssh crimson-comet.exe.xyz 'cd /home/exedev/objpds && docker compose ps pds' 2>/dev/null | grep -q "Up"; then
    pass "PDS container is running"
else
    fail "PDS container is not running"
    ssh crimson-comet.exe.xyz 'cd /home/exedev/objpds/docker/pds && docker compose logs --tail=20 pds' 2>/dev/null || true
    exit 1
fi
echo ""

echo "=== 2. Testing CORS Preflight - /oauth/authorize ==="
RESPONSE=$(curl -s -i -X OPTIONS "${PDS_URL}/oauth/authorize" 2>&1)
STATUS=$(echo "$RESPONSE" | grep -i "^HTTP" | awk '{print $2}')

if [ "$STATUS" = "204" ] || [ "$STATUS" = "200" ]; then
    pass "OPTIONS /oauth/authorize returned ${STATUS}"
    echo "$RESPONSE" | grep -qi "access-control-allow-origin" && pass "  Access-Control-Allow-Origin present" || fail "  Access-Control-Allow-Origin missing"
    echo "$RESPONSE" | grep -qi "access-control-allow-methods" && pass "  Access-Control-Allow-Methods present" || fail "  Access-Control-Allow-Methods missing"
    echo "$RESPONSE" | grep -qi "access-control-allow-headers" && pass "  Access-Control-Allow-Headers present" || fail "  Access-Control-Allow-Headers missing"
else
    fail "OPTIONS /oauth/authorize returned ${STATUS}"
    echo "$RESPONSE" | head -20
fi
echo ""

echo "=== 3. Testing CORS Preflight - /oauth/token ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${PDS_URL}/oauth/token")
[ "$STATUS" = "204" ] || [ "$STATUS" = "200" ] && pass "OPTIONS /oauth/token returned ${STATUS}" || fail "OPTIONS /oauth/token returned ${STATUS}"
echo ""

echo "=== 4. Testing CORS Preflight - /oauth/par ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${PDS_URL}/oauth/par")
[ "$STATUS" = "204" ] || [ "$STATUS" = "200" ] && pass "OPTIONS /oauth/par returned ${STATUS}" || fail "OPTIONS /oauth/par returned ${STATUS}"
echo ""

echo "=== 5. Testing OAuth Endpoint Registration ==="
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${PDS_URL}/oauth/authorize?client_id=test")
[ "$RESPONSE" != "502" ] && [ "$RESPONSE" != "404" ] && pass "GET /oauth/authorize is registered (${RESPONSE})" || fail "GET /oauth/authorize returned ${RESPONSE}"
echo ""

echo "==================================="
echo "Integration Testing Complete"
echo "==================================="
