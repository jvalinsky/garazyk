#!/bin/bash
# Verify VitePress documentation deployment

set -e

# Configuration
BASE_URL="${1:-https://pds.garazyk.xyz}"
DOCS_PATH="/docs"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== VitePress Deployment Verification ==="
echo "Base URL: $BASE_URL"
echo ""

# Test counters
PASSED=0
FAILED=0
WARNINGS=0

# Function to test a URL
test_url() {
    local url="$1"
    local expected_status="${2:-200}"
    local description="$3"
    
    echo -n "Testing: $description... "
    
    response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" "$url")
    status=$(echo "$response" | cut -d'|' -f1)
    time=$(echo "$response" | cut -d'|' -f2)
    
    if [ "$status" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $status, ${time}s)"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} (Expected HTTP $expected_status, got HTTP $status)"
        ((FAILED++))
    fi
}

# Function to check header
check_header() {
    local url="$1"
    local header_name="$2"
    local expected_value="$3"
    local description="$4"
    
    echo -n "Checking: $description... "
    
    actual_value=$(curl -s -I "$url" | grep -i "^$header_name:" | cut -d' ' -f2- | tr -d '\r\n')
    
    if [[ "$actual_value" == *"$expected_value"* ]]; then
        echo -e "${GREEN}✓ PASS${NC} ($actual_value)"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠ WARNING${NC} (Expected: $expected_value, Got: $actual_value)"
        ((WARNINGS++))
    fi
}

echo "=== Testing Core Pages ==="
test_url "$BASE_URL$DOCS_PATH/" "200" "Home page"
test_url "$BASE_URL$DOCS_PATH/01-getting-started/overview" "200" "Getting Started"
test_url "$BASE_URL$DOCS_PATH/10-tutorials/tutorial-1-hello-pds" "200" "Tutorial 1"
test_url "$BASE_URL$DOCS_PATH/11-reference/api-reference" "200" "API Reference"
test_url "$BASE_URL$DOCS_PATH/GLOSSARY" "200" "Glossary"

echo ""
echo "=== Testing 404 Handling ==="
test_url "$BASE_URL$DOCS_PATH/nonexistent-page" "404" "Nonexistent page"

echo ""
echo "=== Testing Static Assets ==="
test_url "$BASE_URL$DOCS_PATH/diagrams/system-architecture.svg" "200" "System architecture diagram"

echo ""
echo "=== Testing HTTPS Configuration ==="
if [[ "$BASE_URL" == https://* ]]; then
    echo -n "Testing SSL certificate... "
    if curl -s --head "$BASE_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ Skipping (not HTTPS)${NC}"
fi

echo ""
echo "=== Testing Caching Headers ==="
check_header "$BASE_URL$DOCS_PATH/assets/app.js" "Cache-Control" "immutable" "JS caching"
check_header "$BASE_URL$DOCS_PATH/" "Cache-Control" "no-cache" "HTML no-cache"

echo ""
echo "=== Testing Security Headers ==="
check_header "$BASE_URL$DOCS_PATH/" "X-Content-Type-Options" "nosniff" "X-Content-Type-Options"
check_header "$BASE_URL$DOCS_PATH/" "X-Frame-Options" "SAMEORIGIN" "X-Frame-Options"

echo ""
echo "=== Testing Search Functionality ==="
echo -n "Checking for search index... "
if curl -s "$BASE_URL$DOCS_PATH/" | grep -q "search"; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ WARNING${NC} (Search not detected)"
    ((WARNINGS++))
fi

echo ""
echo "=== Testing Navigation ==="
echo -n "Checking for sidebar navigation... "
if curl -s "$BASE_URL$DOCS_PATH/" | grep -q "sidebar"; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ WARNING${NC} (Sidebar not detected)"
    ((WARNINGS++))
fi

echo ""
echo "=== Testing Performance ==="
echo -n "Measuring page load time... "
load_time=$(curl -s -o /dev/null -w "%{time_total}" "$BASE_URL$DOCS_PATH/")
if (( $(echo "$load_time < 3.0" | bc -l) )); then
    echo -e "${GREEN}✓ PASS${NC} (${load_time}s)"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ WARNING${NC} (${load_time}s - slower than 3s)"
    ((WARNINGS++))
fi

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment verification successful!${NC}"
    exit 0
else
    echo -e "${RED}✗ Deployment verification failed.${NC}"
    exit 1
fi
