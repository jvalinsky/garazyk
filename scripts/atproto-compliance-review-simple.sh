#!/bin/bash

# ATProto Compliance Review Tool - Simplified Version
# Comprehensive compliance analysis of ATProto PDS implementations

set -euo pipefail

# Configuration
CODEBASE_PATH="${1:-.}"
FOCUS_AREAS="${2:-all}"
COMPLIANCE_LEVEL="${3:-standard}"
OUTPUT_FORMAT="${4:-executive_summary}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CRITICAL_COUNT=0
IMPORTANT_COUNT=0
MINOR_COUNT=0
PASS_COUNT=0

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_critical() {
    echo -e "${RED}🚨 $1${NC}"
}

add_issue() {
    local severity="$1"
    local title="$2"
    local description="$3"

    case "$severity" in
        "critical")
            ((CRITICAL_COUNT++))
            echo "🚨 CRITICAL: $title"
            echo "   $description"
            echo ""
            ;;
        "important")
            ((IMPORTANT_COUNT++))
            echo "⚠️  IMPORTANT: $title"
            echo "   $description"
            echo ""
            ;;
        "minor")
            ((MINOR_COUNT++))
            echo "ℹ️  MINOR: $title"
            echo "   $description"
            echo ""
            ;;
    esac
}

mark_pass() {
    local check="$1"
    ((PASS_COUNT++))
    echo "✅ $check"
}

# ATProto Specification Checks

check_oauth_compliance() {
    log_info "Checking OAuth 2.0 compliance..."

    # Check for OAuth 2.0 server metadata endpoint
    if grep -r "\.well-known/oauth-authorization-server" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "OAuth server metadata endpoint found"
    else
        add_issue "critical" "Missing OAuth Server Metadata" \
            "OAuth 2.0 server metadata endpoint (/.well-known/oauth-authorization-server) not implemented"
    fi

    # Check for DPoP implementation
    if grep -r "DPoP\|dpop" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "DPoP support detected"
    else
        add_issue "critical" "Missing DPoP Support" \
            "DPoP (Demonstrating Proof of Possession) not implemented - required for ATProto OAuth"
    fi

    # Check for PKCE support
    if grep -r "PKCE\|code_challenge\|code_verifier" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "PKCE support detected"
    else
        add_issue "critical" "Missing PKCE Support" \
            "PKCE (Proof Key for Code Exchange) not implemented - required for ATProto OAuth"
    fi
}

check_xrpc_compliance() {
    log_info "Checking XRPC (HTTP API) compliance..."

    # Check for /xrpc/ endpoint handling
    if grep -r "/xrpc/" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "XRPC endpoint prefix (/xrpc/) found"
    else
        add_issue "critical" "Missing XRPC Endpoint Handling" \
            "XRPC endpoints with /xrpc/ prefix not implemented"
    fi
}

check_repository_compliance() {
    log_info "Checking Repository compliance..."

    # Check for repository-related structures
    if grep -r "repo_root\|records\|ipld_blocks" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "Basic repository structures detected"
    else
        add_issue "important" "Missing Repository Structures" \
            "Core repository structures (repo_root, records, ipld_blocks) not found"
    fi
}

# Report generation

generate_executive_summary() {
    echo "# ATProto Compliance Executive Summary"
    echo ""
    echo "## Compliance Status"

    local total_issues=$((CRITICAL_COUNT + IMPORTANT_COUNT + MINOR_COUNT))
    local total_checks=$((PASS_COUNT + total_issues))

    if [ $CRITICAL_COUNT -eq 0 ] && [ $IMPORTANT_COUNT -le 2 ]; then
        echo "🎉 **GOOD COMPLIANCE** - Ready for production"
    elif [ $CRITICAL_COUNT -eq 0 ]; then
        echo "⚠️ **MODERATE COMPLIANCE** - Production ready with minor fixes"
    else
        echo "🚨 **POOR COMPLIANCE** - Critical issues must be addressed"
    fi

    echo ""
    echo "## Metrics"
    echo "- **Total Checks:** $total_checks"
    if [ $total_checks -gt 0 ]; then
        echo "- **Pass Rate:** $((PASS_COUNT * 100 / total_checks))%"
    fi
    echo "- **Critical Issues:** $CRITICAL_COUNT"
    echo "- **Important Issues:** $IMPORTANT_COUNT"
    echo "- **Minor Issues:** $MINOR_COUNT"
    echo ""

    if [ $CRITICAL_COUNT -gt 0 ]; then
        echo "## 🚨 Immediate Actions Required"
        echo "Critical compliance issues must be addressed before deployment."
        echo ""
    fi
}

# Main execution
main() {
    echo "🔍 ATProto Compliance Review"
    echo "==========================="
    echo ""
    echo "Codebase: $CODEBASE_PATH"
    echo "Focus Areas: $FOCUS_AREAS"
    echo "Compliance Level: $COMPLIANCE_LEVEL"
    echo "Output Format: $OUTPUT_FORMAT"
    echo ""

    # Run compliance checks
    check_oauth_compliance
    check_xrpc_compliance
    check_repository_compliance

    echo ""
    echo "## Results Summary"
    echo "- Critical Issues: $CRITICAL_COUNT"
    echo "- Important Issues: $IMPORTANT_COUNT"
    echo "- Minor Issues: $MINOR_COUNT"
    echo "- Passed Checks: $PASS_COUNT"
    echo ""

    # Generate requested report
    case "$OUTPUT_FORMAT" in
        "executive_summary")
            generate_executive_summary
            ;;
        *)
            generate_executive_summary
            ;;
    esac
}

main "$@"