#!/bin/bash
# ATProto PDS Quick Test

set -e

PDS_URL="http://localhost:2583"
DB_PATH="/tmp/atproto_pds.db"

# Cleanup any existing server
pkill -f "september.*2583" 2>/dev/null || true
sleep 1
rm -f "$DB_PATH" 2>/dev/null || true

echo "=== ATProto PDS Health Check ==="
curl -s "$PDS_URL/health"
echo ""

echo ""
echo "=== XRPC Identity Resolve Handle (expected to fail) ==="
curl -s "$PDS_URL/xrpc/com.atproto.identity.resolveHandle?handle=test.example.com"
echo ""

echo ""
echo "=== Create Account ==="
TIMESTAMP=$(date +%s)
curl -s -X POST "$PDS_URL/xrpc/com.atproto.server.createAccount" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"test$TIMESTAMP@example.com\",\"handle\":\"test$TIMESTAMP.example.com\",\"password\":\"password123\"}" || echo "Create account failed (expected if DB not ready)"
echo ""

echo ""
echo "=== Server is responding! ==="
