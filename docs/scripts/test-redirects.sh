#!/bin/bash
# Test URL redirects for VitePress documentation

set -e

BASE_URL="${1:-http://localhost:4173}"
DOCS_PATH="/docs"

echo "Testing URL redirects for VitePress documentation"
echo "Base URL: $BASE_URL"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0

# Function to test a URL
test_url() {
    local url="$1"
    local expected_status="${2:-200}"
    local description="$3"
    
    echo -n "Testing: $description... "
    
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$status" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $status)"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} (Expected HTTP $expected_status, got HTTP $status)"
        ((FAILED++))
    fi
}

echo "=== Testing Main Pages ==="
test_url "$BASE_URL$DOCS_PATH/" "200" "Home page"
test_url "$BASE_URL$DOCS_PATH/01-getting-started/overview" "200" "Getting Started overview"
test_url "$BASE_URL$DOCS_PATH/10-tutorials/tutorial-1-hello-pds" "200" "Tutorial 1"

echo ""
echo "=== Testing Extension Handling ==="
# VitePress should handle .html extensions gracefully
test_url "$BASE_URL$DOCS_PATH/01-getting-started/overview.html" "200" "Page with .html extension"
test_url "$BASE_URL$DOCS_PATH/01-getting-started/overview.md" "200" "Page with .md extension"

echo ""
echo "=== Testing Trailing Slashes ==="
test_url "$BASE_URL$DOCS_PATH/01-getting-started/overview/" "200" "Page with trailing slash"
test_url "$BASE_URL$DOCS_PATH/01-getting-started/" "200" "Section with trailing slash"

echo ""
echo "=== Testing 404 Handling ==="
test_url "$BASE_URL$DOCS_PATH/nonexistent-page" "404" "Nonexistent page"
test_url "$BASE_URL$DOCS_PATH/01-getting-started/nonexistent" "404" "Nonexistent page in section"

echo ""
echo "=== Testing Static Assets ==="
test_url "$BASE_URL$DOCS_PATH/diagrams/system-architecture.svg" "200" "SVG diagram"

echo ""
echo "=== Testing Anchor Links ==="
# These should return 200 (the page exists, anchor is client-side)
test_url "$BASE_URL$DOCS_PATH/01-getting-started/overview#architecture" "200" "Page with anchor"

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
