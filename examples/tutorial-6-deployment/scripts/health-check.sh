#!/bin/bash
# health-check.sh — Health check script for ATProto PDS
#
# Usage: ./scripts/health-check.sh
# Exit codes: 0 = healthy, 1 = unhealthy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment
if [ -f "$PROJECT_DIR/docker/.env" ]; then
    source "$PROJECT_DIR/docker/.env"
fi

DOMAIN="${PDS_DOMAIN:-pds.example.com}"
TIMEOUT=10

echo "=== ATProto PDS Health Check ==="
echo "Domain: $DOMAIN"
echo ""

# Check 1: Container running
echo -n "Container status... "
if docker ps --filter "name=nspds" --filter "status=running" | grep -q nspds; then
    echo "✓ Running"
else
    echo "✗ Not running"
    exit 1
fi

# Check 2: Local endpoint
echo -n "Local endpoint... "
if response=$(curl -sf --max-time "$TIMEOUT" http://localhost:2583/xrpc/com.atproto.server.describeServer 2>&1); then
    if echo "$response" | jq -e '.did' >/dev/null 2>&1; then
        echo "✓ Responding"
    else
        echo "✗ Invalid response"
        exit 1
    fi
else
    echo "✗ Not responding"
    exit 1
fi

# Check 3: External endpoint
echo -n "External endpoint... "
if response=$(curl -sf --max-time "$TIMEOUT" "https://$DOMAIN/xrpc/com.atproto.server.describeServer" 2>&1); then
    if echo "$response" | jq -e '.did' >/dev/null 2>&1; then
        echo "✓ Responding"
    else
        echo "✗ Invalid response"
        exit 1
    fi
else
    echo "✗ Not responding"
    exit 1
fi

# Check 4: Disk space
echo -n "Disk space... "
USAGE=$(df -h /var/lib/docker/volumes/pds_pds_data/_data 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
if [ -n "$USAGE" ] && [ "$USAGE" -lt 90 ]; then
    echo "✓ ${USAGE}% used"
else
    echo "⚠ ${USAGE}% used (high)"
fi

# Check 5: Container health
echo -n "Container health... "
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' nspds 2>/dev/null || echo "unknown")
if [ "$HEALTH" = "healthy" ]; then
    echo "✓ Healthy"
elif [ "$HEALTH" = "unknown" ]; then
    echo "⚠ No healthcheck configured"
else
    echo "✗ $HEALTH"
    exit 1
fi

echo ""
echo "=== All Checks Passed ==="
exit 0
