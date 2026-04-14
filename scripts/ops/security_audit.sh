#!/bin/bash
#
# Security Audit Script
# Automated checks to prevent P0 security vulnerabilities
#
# This script validates that critical security fixes are in place:
# 1. No hardcoded OAuth test clients outside DEBUG
# 2. No weak SHA-256 password hashing
# 3. PBKDF2 with sufficient iterations
# 4. SSRF protection cannot be disabled
# 5. Redirect URIs use HTTPS in production
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"

echo "========================================="
echo "  Security Audit - P0 Vulnerability Check"
echo "========================================="
echo ""
echo "Project: $PROJECT_ROOT"
echo "Date: $(date)"
echo ""

FAILURES=0
WARNINGS=0

# Color output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILURES=$((FAILURES + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

# Check 1: No hardcoded test-client outside DEBUG blocks
echo "Checking for hardcoded OAuth credentials..."
# This is a more sophisticated check that looks for test-client not within DEBUG guards
# We check files and ensure test-client only appears in DEBUG-protected sections
HAS_UNPROTECTED_TESTCLIENT=0

while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Check if file contains test-client
        if grep -q "test-client" "$file"; then
            # Extract the seedTestClient method and check it's protected
            if grep -A20 "seedTestClient" "$file" | head -1 | grep -q "seedTestClient"; then
                # Check if #ifndef DEBUG or #else appears before test-client in the method
                if ! (grep -B5 '"test-client"' "$file" | grep -E "#(ifndef DEBUG|else)"); then
                    # Check if it's the call site wrapped in #ifdef DEBUG
                    if ! (grep -B2 "seedTestClient" "$file" | grep -q "#ifdef DEBUG"); then
                        HAS_UNPROTECTED_TESTCLIENT=1
                        echo "   Unprotected test-client in: $file"
                    fi
                fi
            fi
        fi
    fi
done < <(find "$PROJECT_ROOT/Garazyk/Sources/" -name "*.m")

if [ $HAS_UNPROTECTED_TESTCLIENT -eq 1 ]; then
    fail "Found hardcoded 'test-client' outside DEBUG guards"
    echo "   Found in production code - this is a CRITICAL vulnerability"
else
    pass "No hardcoded OAuth credentials in production code"
fi
echo ""

# Check 2: No SHA-256 password hashing
echo "Checking for weak password hashing..."
if grep -rn "CC_SHA256.*password" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/" | grep -v "Legacy" | grep -v "legacy" | grep -v "//"; then
    fail "Found SHA-256 password hashing (use PBKDF2 instead)"
    echo "   SHA-256 is not a password hashing algorithm - use PBKDF2"
else
    pass "No weak SHA-256 password hashing found"
fi
echo ""

# Check 3: PBKDF2 with sufficient iterations
echo "Checking PBKDF2 iteration count..."
if grep -rn "600000" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/" | grep -i "iteration"; then
    pass "PBKDF2 using recommended 600,000 iterations"
elif grep -rn "CCKeyDerivationPBKDF" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/"; then
    # Found PBKDF2 but not 600k iterations
    ITER_COUNT=$(grep -rn "iterations.*=" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/" | grep -oE "[0-9]+" | sort -n | tail -1)
    if [ -n "$ITER_COUNT" ]; then
        if [ "$ITER_COUNT" -ge 600000 ]; then
            pass "PBKDF2 using $ITER_COUNT iterations (sufficient)"
        else
            warn "PBKDF2 using only $ITER_COUNT iterations (recommend 600,000+ for HMAC-SHA256)"
            echo "   Current OWASP recommendation: 600,000 iterations"
        fi
    else
        warn "Could not determine PBKDF2 iteration count"
    fi
else
    warn "PBKDF2 password hashing not found"
fi
echo ""

# Check 4: SSRF protection cannot be disabled
echo "Checking SSRF protection..."
if grep -rn "skipSSRFCheck.*=.*YES" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/" | grep -v "//"; then
    fail "Found code that sets skipSSRFCheck = YES"
    echo "   SSRF protection should not be disabled in production"
elif grep -rn "skipSSRFCheck.*=" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/" | grep -v "//"; then
    fail "Found code that modifies skipSSRFCheck"
    echo "   skipSSRFCheck should be readonly"
else
    pass "SSRF protection cannot be disabled"
fi

# Verify skipSSRFCheck is readonly
if grep -rn "readonly.*skipSSRFCheck" --include="*.h" "$PROJECT_ROOT/Garazyk/Sources/"; then
    pass "skipSSRFCheck is marked readonly in header"
else
    warn "skipSSRFCheck should be marked readonly in HandleResolver.h"
fi
echo ""

# Check 5: HTTP redirect URIs in production
echo "Checking redirect URI security..."
if grep -rn '"http://' --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/Database/" | grep redirect_uri | grep -v "localhost" | grep -v "127.0.0.1"; then
    warn "Found HTTP redirect URIs (should use HTTPS in production)"
    echo "   HTTP redirect URIs are only safe for localhost"
else
    pass "No insecure HTTP redirect URIs found"
fi
echo ""

# Check 6: Comprehensive private IP range blocking
echo "Checking SSRF IP range coverage..."
REQUIRED_RANGES=(
    "0x0A000000"  # 10.0.0.0/8
    "0xAC100000"  # 172.16.0.0/12
    "0xC0A80000"  # 192.168.0.0/16
    "0x7F000000"  # 127.0.0.0/8
    "0xA9FE0000"  # 169.254.0.0/16 (cloud metadata!)
    "0x00000000"  # 0.0.0.0/8
    "0x64400000"  # 100.64.0.0/10
    "0xE0000000"  # 224.0.0.0/4 (multicast)
    "0xF0000000"  # 240.0.0.0/4 (reserved)
)

MISSING_RANGES=0
for range in "${REQUIRED_RANGES[@]}"; do
    if ! grep -q "$range" "$PROJECT_ROOT/Garazyk/Sources/Identity/HandleResolver.m"; then
        warn "Missing IP range check: $range"
        MISSING_RANGES=$((MISSING_RANGES + 1))
    fi
done

if [ $MISSING_RANGES -eq 0 ]; then
    pass "All critical IP ranges are blocked"
else
    warn "Missing $MISSING_RANGES IP range checks"
fi
echo ""

# Check 7: IPv4-mapped IPv6 address checking
echo "Checking IPv6 SSRF protection..."
if grep -q "IPv4-mapped" "$PROJECT_ROOT/Garazyk/Sources/Identity/HandleResolver.m"; then
    if grep -q "::ffff:0:0/96" "$PROJECT_ROOT/Garazyk/Sources/Identity/HandleResolver.m"; then
        pass "IPv4-mapped IPv6 addresses are checked"
    else
        warn "IPv4-mapped IPv6 comment found but implementation unclear"
    fi
else
    warn "IPv4-mapped IPv6 address checking not found"
    echo "   Add ::ffff:0:0/96 range checking to prevent IPv6 SSRF bypass"
fi
echo ""

# Check 8: DEBUG-only test client seeding
echo "Checking test client seeding protection..."
# Check OAuth2Handler.m has #ifdef DEBUG before seedTestClient call
if grep -B3 "seedTestClient" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuth2Handler.m" | grep -q "#ifdef DEBUG"; then
    pass "Test client seeding protected by DEBUG flag in OAuth2Handler"
else
    warn "Test client seeding may not be properly protected in OAuth2Handler"
    echo "   The seedTestClient call should be wrapped in #ifdef DEBUG"
fi

# Check PDSDatabase.m seedTestClient method blocks in release
if grep -A5 -- "- (BOOL)seedTestClient" "$PROJECT_ROOT/Garazyk/Sources/Database/PDSDatabase.m" | grep -q "#ifndef DEBUG"; then
    pass "seedTestClient returns error in release builds"
else
    warn "seedTestClient may not return error in release builds"
    echo "   The method should return NO with error in #ifndef DEBUG block"
fi
echo ""

# Check 9: Redirect URI scheme validation
echo "Checking redirect URI scheme validation..."
if grep -q "url.scheme.*https" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuth2Handler.m"; then
    pass "Redirect URI scheme validation present"
else
    warn "Redirect URI scheme validation not found"
    echo "   Should enforce HTTPS in production builds"
fi
echo ""

# Summary
echo "========================================="
echo "  Security Audit Summary"
echo "========================================="
if [ $FAILURES -gt 0 ]; then
    echo -e "${RED}FAILED:${NC} $FAILURES critical security issues found"
    echo ""
    echo "These vulnerabilities must be fixed before production deployment."
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}WARNINGS:${NC} $WARNINGS potential security concerns"
    echo ""
    echo "Review warnings and address if applicable."
    exit 0
else
    echo -e "${GREEN}PASSED:${NC} No critical security vulnerabilities detected"
    echo ""
    echo "All P0 security checks passed."
    exit 0
fi
