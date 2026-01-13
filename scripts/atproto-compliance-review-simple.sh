#!/bin/bash

# ATProto Compliance Review Tool - Simplified Version
# Comprehensive compliance analysis of ATProto PDS implementations
#
# Usage:
#   ./atproto-compliance-review-simple.sh [codebase_path] [focus_areas] [compliance_level] [output_format]
#
# Arguments:
#   codebase_path    - Path to the codebase root (default: current directory)
#   focus_areas      - Comma-separated areas to check: oauth,xrpc,repository,did,lexicon,all (default: all)
#   compliance_level - Strictness: basic, standard, comprehensive (default: standard)
#   output_format    - Report format: executive_summary (default: executive_summary)

set -euo pipefail

# Configuration
CODEBASE_PATH="${1:-.}"
FOCUS_AREAS="${2:-all}"
COMPLIANCE_LEVEL="${3:-standard}"
OUTPUT_FORMAT="${4:-executive_summary}"

# Validate codebase path exists
if [[ ! -d "$CODEBASE_PATH" ]]; then
    echo "Error: Codebase path does not exist: $CODEBASE_PATH" >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
# Note: Initialize to -1 so first increment brings to 0, avoiding the bash
# arithmetic gotcha where ((var++)) returns exit code 1 when var=0 under set -e.
# We adjust final counts by adding 1 when displaying.
# Alternative: Use VARNAME=$((VARNAME + 1)) which doesn't have this issue.
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
            # Use $((var + 1)) instead of ((var++)) to avoid exit code 1 when var=0 under set -e
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            echo "🚨 CRITICAL: $title"
            echo "   $description"
            echo ""
            ;;
        "important")
            IMPORTANT_COUNT=$((IMPORTANT_COUNT + 1))
            echo "⚠️  IMPORTANT: $title"
            echo "   $description"
            echo ""
            ;;
        "minor")
            MINOR_COUNT=$((MINOR_COUNT + 1))
            echo "ℹ️  MINOR: $title"
            echo "   $description"
            echo ""
            ;;
    esac
}

mark_pass() {
    local check="$1"
    # Use $((var + 1)) instead of ((var++)) to avoid exit code 1 when var=0 under set -e
    PASS_COUNT=$((PASS_COUNT + 1))
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

    # Check for CID handling (Content Identifiers for IPLD)
    if grep -r "CID\|cid" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "CID support detected"
    else
        add_issue "important" "Missing CID Support" \
            "Content Identifier (CID) handling not implemented"
    fi
}

check_did_compliance() {
    log_info "Checking DID compliance..."

    # Check for DID resolution functionality
    if grep -r "resolveDID\|DID.*resolve\|DIDResolver" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "DID resolution support detected"
    else
        add_issue "important" "Missing DID Resolution" \
            "DID document resolution functionality not implemented"
    fi

    # Check for did:plc support (ATProto's primary DID method)
    if grep -r "did:plc\|plc\.directory" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "did:plc support detected"
    else
        add_issue "important" "Missing did:plc Support" \
            "did:plc method not implemented - primary DID method for ATProto"
    fi
}

check_lexicon_compliance() {
    log_info "Checking Lexicon compliance..."

    # Check for schema/lexicon validation
    if grep -r "lexicon\|Lexicon\|schema.*valid" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "Lexicon schema validation detected"
    else
        add_issue "minor" "Limited Schema Validation" \
            "Lexicon schema validation may be incomplete"
    fi

    # Check for NSID (Namespaced Identifier) handling
    if grep -r "NSID\|nsid\|com\.atproto\|app\.bsky" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "NSID handling detected"
    else
        add_issue "minor" "Missing NSID Handling" \
            "Namespaced Identifier (NSID) parsing/validation not found"
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
    check_did_compliance
    check_lexicon_compliance

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