#!/bin/bash
#
# Security Audit Script
# Automated checks to prevent P0 security vulnerabilities
#
# This script validates that critical security fixes are in place:
# 1. No hardcoded OAuth test clients outside DEBUG
# 2. No weak SHA-256 password hashing
# 3. PBKDF2 with sufficient iterations
# 4. All outbound HTTP uses ATProtoSafeHTTPClient (no raw NSURLSession)
# 5. PDSLogRedactor wired into PDSLogger
# 6. OAuthClientAuthPolicy used for client auth validation
# 7. PDSKeyEnvelope used for key encryption
# 8. PDSSecurityCompare used for secret comparisons
# 9. Redirect URIs use HTTPS in production
# 10. No skipSSRFCheck property (removed)
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
HAS_UNPROTECTED_TESTCLIENT=0

while IFS= read -r file; do
    if [ -f "$file" ]; then
        if grep -q "test-client" "$file"; then
            if grep -A20 "seedTestClient" "$file" | head -1 | grep -q "seedTestClient"; then
                if ! (grep -B5 '"test-client"' "$file" | grep -E "#(ifndef DEBUG|else)"); then
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

# Check 4: No skipSSRFCheck property (removed in Phase 2)
echo "Checking skipSSRFCheck removal..."
if grep -rn "skipSSRFCheck" --include="*.h" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/"; then
    fail "Found skipSSRFCheck property — should be removed (use PDSSafeHTTPClient.allowPrivateHosts)"
    echo "   skipSSRFCheck was removed; tests should use allowPrivateHosts instead"
else
    pass "skipSSRFCheck property removed from codebase"
fi
echo ""

# Check 5: Outbound HTTP uses PDSSafeHTTPClient
echo "Checking outbound HTTP client security..."
# Files that should import PDSSafeHTTPClient
REQUIRED_SAFE_CLIENT_FILES=(
    "XrpcProxyInterceptor.m"
    "FederationClient.m"
    "XrpcLexiconResolver.m"
    "OAuth2Handler.m"
    "HandleResolver.m"
)
MISSING_SAFE_CLIENT=0
for file in "${REQUIRED_SAFE_CLIENT_FILES[@]}"; do
    FOUND=$(find "$PROJECT_ROOT/Garazyk/Sources/" -name "$file" -exec grep -l "PDSSafeHTTPClient" {} \;)
    if [ -z "$FOUND" ]; then
        fail "PDSSafeHTTPClient not imported in $file"
        MISSING_SAFE_CLIENT=$((MISSING_SAFE_CLIENT + 1))
    fi
done
if [ $MISSING_SAFE_CLIENT -eq 0 ]; then
    pass "All outbound HTTP files use PDSSafeHTTPClient"
fi
echo ""

# Check 6: No raw NSURLSession dataTaskWithRequest in outbound files
echo "Checking for raw NSURLSession usage in outbound files..."
OUTBOUND_FILES=(
    "XrpcProxyInterceptor.m"
    "FederationClient.m"
    "XrpcLexiconResolver.m"
    "HandleResolver.m"
)
RAW_SESSION_USAGE=0
for file in "${OUTBOUND_FILES[@]}"; do
    FOUND=$(find "$PROJECT_ROOT/Garazyk/Sources/" -name "$file" -exec grep -l "dataTaskWithRequest" {} \; 2>/dev/null || true)
    if [ -n "$FOUND" ]; then
        fail "Raw NSURLSession dataTaskWithRequest found in $file (should use PDSSafeHTTPClient)"
        RAW_SESSION_USAGE=$((RAW_SESSION_USAGE + 1))
    fi
done
if [ $RAW_SESSION_USAGE -eq 0 ]; then
    pass "No raw NSURLSession usage in outbound request files"
fi
echo ""

# Check 7: PDSLogRedactor wired into PDSLogger
echo "Checking log redaction..."
if grep -q "PDSLogRedactor" "$PROJECT_ROOT/Garazyk/Sources/Debug/PDSLogger.m"; then
    pass "PDSLogRedactor integrated into PDSLogger"
else
    fail "PDSLogRedactor not integrated into PDSLogger"
    echo "   PDSLogger must apply redaction to all log output"
fi
echo ""

# Check 8: OAuthClientAuthPolicy used for client auth
echo "Checking OAuth client authentication policy..."
if grep -q "OAuthClientAuthPolicy" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m"; then
    pass "OAuthClientAuthPolicy used in OAuthProvider"
else
    fail "OAuthClientAuthPolicy not used in OAuthProvider"
    echo "   Client authentication should use OAuthClientAuthPolicy for validation"
fi

if grep -q "OAuthClientAuthPolicy" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuth2Handler.m"; then
    pass "OAuthClientAuthPolicy used in OAuth2Handler"
else
    fail "OAuthClientAuthPolicy not used in OAuth2Handler"
    echo "   Client secret comparison should use OAuthClientAuthPolicy.validateClientSecret"
fi
echo ""

# Check 9: PDSKeyEnvelope used for key encryption
echo "Checking key envelope encryption..."
if grep -q "PDSKeyEnvelope" "$PROJECT_ROOT/Garazyk/Sources/Database/ActorStore/ActorStore.m"; then
    pass "PDSKeyEnvelope used in ActorStore"
else
    fail "PDSKeyEnvelope not used in ActorStore"
    echo "   Key encryption should use PDSKeyEnvelope (encrypt-then-MAC)"
fi

if grep -q "PDSKeyEnvelope" "$PROJECT_ROOT/Garazyk/Sources/PLC/PLCRotationKeyManager.m"; then
    pass "PDSKeyEnvelope used in PLCRotationKeyManager"
else
    fail "PDSKeyEnvelope not used in PLCRotationKeyManager"
    echo "   Key encryption should use PDSKeyEnvelope (encrypt-then-MAC)"
fi
echo ""

# Check 10: PDSSecurityCompare used for secret comparisons
echo "Checking constant-time secret comparisons..."
# Check that no isEqualToString is used for refresh tokens
if grep -rn "refreshToken isEqualToString" --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/Auth/"; then
    fail "Found non-constant-time refresh token comparison (isEqualToString)"
    echo "   Use PDSSecurityCompare.constantTimeEqualString for secret comparisons"
else
    pass "No non-constant-time refresh token comparisons"
fi

# Check that no isEqualToString is used for client_secret in OAuth2Handler
if grep -n "clientSecret isEqualToString" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuth2Handler.m" 2>/dev/null; then
    fail "Found non-constant-time client_secret comparison in OAuth2Handler"
    echo "   Use OAuthClientAuthPolicy.validateClientSecret for client secret checks"
else
    pass "No non-constant-time client_secret comparisons"
fi

# Check that UIAuthManager uses PDSSecurityCompare
if grep -q "PDSSecurityCompare" "$PROJECT_ROOT/Garazyk/Sources/AdminUIServer/UIAuthManager.m"; then
    pass "UIAuthManager uses PDSSecurityCompare"
else
    fail "UIAuthManager does not use PDSSecurityCompare"
    echo "   Password and token comparisons must use constant-time comparison"
fi
echo ""

# Check 11: HTTP redirect URIs in production
echo "Checking redirect URI security..."
if grep -rn '"http://' --include="*.m" "$PROJECT_ROOT/Garazyk/Sources/Database/" | grep redirect_uri | grep -v "localhost" | grep -v "127.0.0.1"; then
    warn "Found HTTP redirect URIs (should use HTTPS in production)"
    echo "   HTTP redirect URIs are only safe for localhost"
else
    pass "No insecure HTTP redirect URIs found"
fi
echo ""

# Check 12: Comprehensive private IP range blocking
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

# Check SSRFValidator (the canonical location) and PDSSafeHTTPClient
SSRF_FILE=$(find "$PROJECT_ROOT/Garazyk/Sources/" -name "SSRFValidator.m" | head -1)
MISSING_RANGES=0
for range in "${REQUIRED_RANGES[@]}"; do
    if [ -n "$SSRF_FILE" ] && ! grep -q "$range" "$SSRF_FILE"; then
        warn "Missing IP range check: $range"
        MISSING_RANGES=$((MISSING_RANGES + 1))
    fi
done

if [ $MISSING_RANGES -eq 0 ]; then
    pass "All critical IP ranges are blocked in SSRFValidator"
else
    warn "Missing $MISSING_RANGES IP range checks"
fi
echo ""

# Check 13: IPv4-mapped IPv6 address checking
echo "Checking IPv6 SSRF protection..."
if [ -n "$SSRF_FILE" ] && grep -q "IPv4-mapped" "$SSRF_FILE"; then
    pass "IPv4-mapped IPv6 addresses are checked"
else
    warn "IPv4-mapped IPv6 address checking not found in SSRFValidator"
    echo "   Add ::ffff:0:0/96 range checking to prevent IPv6 SSRF bypass"
fi
echo ""

# Check 14: DEBUG-only test client seeding
echo "Checking test client seeding protection..."
if grep -B3 "seedTestClient" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuth2Handler.m" | grep -q "#ifdef DEBUG"; then
    pass "Test client seeding protected by DEBUG flag in OAuth2Handler"
else
    warn "Test client seeding may not be properly protected in OAuth2Handler"
    echo "   The seedTestClient call should be wrapped in #ifdef DEBUG"
fi

if grep -A5 -- "- (BOOL)seedTestClient" "$PROJECT_ROOT/Garazyk/Sources/Database/PDSDatabase.m" | grep -q "#ifndef DEBUG"; then
    pass "seedTestClient returns error in release builds"
else
    warn "seedTestClient may not return error in release builds"
    echo "   The method should return NO with error in #ifndef DEBUG block"
fi
echo ""

# Check 15: Redirect URI scheme validation
echo "Checking redirect URI scheme validation..."
if grep -q "url.scheme.*https" "$PROJECT_ROOT/Garazyk/Sources/Auth/OAuth2Handler.m"; then
    pass "Redirect URI scheme validation present"
else
    warn "Redirect URI scheme validation not found"
    echo "   Should enforce HTTPS in production builds"
fi
echo ""

# Check 16: UIAuthManager session security
echo "Checking UIAuthManager session security..."
if grep -q "PBKDF2\|pbkdf2\|CCKeyDerivationPBKDF" "$PROJECT_ROOT/Garazyk/Sources/AdminUIServer/UIAuthManager.m"; then
    pass "UIAuthManager uses PBKDF2 password hashing"
else
    fail "UIAuthManager does not use PBKDF2 password hashing"
    echo "   Plaintext password storage is a critical vulnerability"
fi

if grep -q "SecRandomCopyBytes" "$PROJECT_ROOT/Garazyk/Sources/AdminUIServer/UIAuthManager.m"; then
    pass "UIAuthManager uses CSPRNG for session tokens"
else
    warn "UIAuthManager may not use CSPRNG for session tokens"
    echo "   NSUUID is not a CSPRNG — use SecRandomCopyBytes"
fi

if grep -q "sessionTTL\|expiryTime" "$PROJECT_ROOT/Garazyk/Sources/AdminUIServer/UIAuthManager.m"; then
    pass "UIAuthManager has session TTL/expiry"
else
    warn "UIAuthManager may not have session TTL"
    echo "   Sessions should expire after a reasonable time"
fi
echo ""

# Check 17: SQL injection protection
echo "Checking SQL injection protection..."
if grep -q "isValidColumnType" "$PROJECT_ROOT/Garazyk/Sources/Database/ActorStore/ActorStore.m"; then
    pass "addColumnIfNeeded validates column types"
else
    warn "addColumnIfNeeded may not validate column types"
    echo "   Free-form type strings in ALTER TABLE are an injection vector"
fi

if grep -A5 "SELECT name FROM sqlite_master" "$PROJECT_ROOT/Garazyk/Sources/Database/ActorStore/ActorStore.m" | grep -q "sqlite3_bind_text"; then
    pass "Table name check uses parameterized query"
else
    warn "Table name check may use string interpolation"
    echo "   sqlite_master queries should use parameterized queries"
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
