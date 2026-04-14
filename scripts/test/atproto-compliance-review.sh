#!/bin/bash

# ATProto Compliance Review Tool
# Comprehensive compliance analysis of ATProto PDS implementations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODEBASE_PATH="${1:-$REPO_ROOT}"
FOCUS_AREAS="${2:-all}"
COMPLIANCE_LEVEL="${3:-standard}"
OUTPUT_FORMAT="${4:-all}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Compliance check results (using files for storage)
COMPLIANCE_CHECKS_FILE="/tmp/atproto_compliance_checks.txt"
CRITICAL_ISSUES_FILE="/tmp/atproto_critical_issues.txt"
IMPORTANT_ISSUES_FILE="/tmp/atproto_important_issues.txt"
MINOR_ISSUES_FILE="/tmp/atproto_minor_issues.txt"

# Clean up any existing files
rm -f "$COMPLIANCE_CHECKS_FILE" "$CRITICAL_ISSUES_FILE" "$IMPORTANT_ISSUES_FILE" "$MINOR_ISSUES_FILE"

# Initialize counters
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
    local category="$1"
    local severity="$2"
    local title="$3"
    local description="$4"
    local file="$5"
    local recommendation="$6"

    case "$severity" in
        "critical")
            echo "$category|$title|$description|$file|$recommendation" >> "$CRITICAL_ISSUES_FILE"
            ((CRITICAL_COUNT++))
            ;;
        "important")
            echo "$category|$title|$description|$file|$recommendation" >> "$IMPORTANT_ISSUES_FILE"
            ((IMPORTANT_COUNT++))
            ;;
        "minor")
            echo "$category|$title|$description|$file|$recommendation" >> "$MINOR_ISSUES_FILE"
            ((MINOR_COUNT++))
            ;;
    esac
}

mark_pass() {
    local category="$1"
    local check="$2"
    echo "$category|$check|PASS" >> "$COMPLIANCE_CHECKS_FILE"
    ((PASS_COUNT++))
}

# ATProto Specification Checks

check_oauth_compliance() {
    log_info "Checking OAuth 2.0 compliance..."

    # Check for OAuth 2.0 server metadata endpoint
    if grep -r "\.well-known/oauth-authorization-server" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "oauth" "server_metadata_endpoint"
        log_success "OAuth server metadata endpoint found"
    else
        add_issue "oauth" "critical" "Missing OAuth Server Metadata" \
            "OAuth 2.0 server metadata endpoint (/.well-known/oauth-authorization-server) not implemented" \
            "" \
            "Implement OAuth 2.0 server metadata endpoint as per RFC 8414 and ATProto OAuth spec"
    fi

    # Check for DPoP implementation
    if grep -r "DPoP\|dpop" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "oauth" "dpop_support"
        log_success "DPoP support detected"
    else
        add_issue "oauth" "critical" "Missing DPoP Support" \
            "DPoP (Demonstrating Proof of Possession) not implemented - required for ATProto OAuth" \
            "" \
            "Implement DPoP proof-of-possession for OAuth tokens as per ATProto OAuth specification"
    fi

    # Check for PKCE support
    if grep -r "PKCE\|code_challenge\|code_verifier" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "oauth" "pkce_support"
        log_success "PKCE support detected"
    else
        add_issue "oauth" "critical" "Missing PKCE Support" \
            "PKCE (Proof Key for Code Exchange) not implemented - required for ATProto OAuth" \
            "" \
            "Implement PKCE for OAuth authorization code flow as per ATProto OAuth specification"
    fi
}

check_xrpc_compliance() {
    log_info "Checking XRPC (HTTP API) compliance..."

    # Check for /xrpc/ endpoint handling
    if grep -r "/xrpc/" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "xrpc" "endpoint_prefix"
        log_success "XRPC endpoint prefix (/xrpc/) found"
    else
        add_issue "xrpc" "critical" "Missing XRPC Endpoint Handling" \
            "XRPC endpoints with /xrpc/ prefix not implemented" \
            "" \
            "Implement XRPC endpoint routing with /xrpc/ prefix as per ATProto XRPC specification"
    fi

    # Check for standard error responses
    if grep -r "error.*message" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "xrpc" "error_format"
        log_success "Standard error response format detected"
    else
        add_issue "xrpc" "important" "Non-standard Error Responses" \
            "Error responses may not follow ATProto XRPC standard format" \
            "" \
            "Ensure error responses include 'error' and 'message' fields as per XRPC specification"
    fi
}

check_repository_compliance() {
    log_info "Checking Repository compliance..."

    # Check for repository-related structures
    if grep -r "repo_root\|records\|ipld_blocks" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "repository" "basic_structure"
        log_success "Basic repository structures detected"
    else
        add_issue "repository" "important" "Missing Repository Structures" \
            "Core repository structures (repo_root, records, ipld_blocks) not found" \
            "" \
            "Implement ATProto repository data structures as per Repository specification"
    fi

    # Check for CID handling
    if grep -r "CID\|cid" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "repository" "cid_support"
        log_success "CID support detected"
    else
        add_issue "repository" "important" "Missing CID Support" \
            "Content Identifier (CID) handling not implemented" \
            "" \
            "Implement CID generation and validation for repository records"
    fi
}

check_did_compliance() {
    log_info "Checking DID compliance..."

    # Check for DID resolution
    if grep -r "resolveDID\|DID.*resolve" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "did" "resolution_support"
        log_success "DID resolution support detected"
    else
        add_issue "did" "important" "Missing DID Resolution" \
            "DID resolution functionality not implemented" \
            "" \
            "Implement DID document resolution as per ATProto DID specification"
    fi
}

check_lexicon_compliance() {
    log_info "Checking Lexicon compliance..."

    # Check for schema validation
    if grep -r "lexicon\|schema.*valid" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "lexicon" "schema_validation"
        log_success "Lexicon schema validation detected"
    else
        add_issue "lexicon" "minor" "Limited Schema Validation" \
            "Lexicon schema validation may be incomplete" \
            "" \
            "Implement comprehensive Lexicon schema validation for API requests/responses"
    fi
}

# Report generation functions

generate_structured_checklist() {
    echo "# ATProto Compliance Checklist"
    echo ""
    echo "## Summary"
    echo "- **Critical Issues:** $CRITICAL_COUNT"
    echo "- **Important Issues:** $IMPORTANT_COUNT"
    echo "- **Minor Issues:** $MINOR_COUNT"
    echo "- **Passed Checks:** $PASS_COUNT"
    echo ""

    if [ $CRITICAL_COUNT -gt 0 ]; then
        echo "## 🚨 Critical Issues (Must Fix)"
        while IFS='|' read -r category title description file recommendation; do
            echo "### $title"
            echo "**Description:** $description"
            [ -n "$file" ] && echo "**File:** $file"
            echo "**Recommendation:** $recommendation"
            echo ""
        done < "$CRITICAL_ISSUES_FILE"
    fi

    if [ $IMPORTANT_COUNT -gt 0 ]; then
        echo "## ⚠️ Important Issues (Should Fix)"
        while IFS='|' read -r category title description file recommendation; do
            echo "### $title"
            echo "**Description:** $description"
            [ -n "$file" ] && echo "**File:** $file"
            echo "**Recommendation:** $recommendation"
            echo ""
        done < "$IMPORTANT_ISSUES_FILE"
    fi

    if [ $MINOR_COUNT -gt 0 ]; then
        echo "## ℹ️ Minor Issues (Nice to Have)"
        while IFS='|' read -r category title description file recommendation; do
            echo "### $title"
            echo "**Description:** $description"
            [ -n "$file" ] && echo "**File:** $file"
            echo "**Recommendation:** $recommendation"
            echo ""
        done < "$MINOR_ISSUES_FILE"
    fi

    echo "## ✅ Passed Checks"
    while IFS='|' read -r category check status; do
        if [ "$status" = "PASS" ]; then
            echo "- $check"
        fi
    done < "$COMPLIANCE_CHECKS_FILE"
}

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
    echo "- **Pass Rate:** $((PASS_COUNT * 100 / total_checks))%"
    echo "- **Critical Issues:** $CRITICAL_COUNT"
    echo "- **Risk Level:** $([ $CRITICAL_COUNT -gt 0 ] && echo 'HIGH' || echo 'LOW')"
    echo ""

    if [ $CRITICAL_COUNT -gt 0 ]; then
        echo "## 🚨 Immediate Actions Required"
        echo "Critical compliance issues must be addressed before deployment:"
        for key in "${!CRITICAL_ISSUES[@]}"; do
            echo "- ${key#*|}"
        done
        echo ""
    fi

    echo "## 📋 Recommendations"
    if [ $total_issues -eq 0 ]; then
        echo "✅ Excellent compliance - no immediate actions required"
    else
        echo "Priority order: Critical → Important → Minor"
        echo "Focus on authentication and API compliance first"
    fi
}

generate_detailed_gap_analysis() {
    echo "# ATProto Compliance Gap Analysis"
    echo ""

    echo "## Executive Summary"
    echo "This analysis identifies gaps between the current implementation and ATProto specification requirements."
    echo ""

    echo "## Methodology"
    echo "- Automated code analysis for specification adherence"
    echo "- Manual verification of critical compliance areas"
    echo "- Risk assessment based on interoperability impact"
    echo ""

    echo "## Gap Analysis by Category"

    # OAuth Gaps
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ] || [ ${#IMPORTANT_ISSUES[@]} -gt 0 ]; then
        echo "### 🔐 OAuth 2.0 Compliance Gaps"
        for key in "${!CRITICAL_ISSUES[@]}"; do
            if [[ $key == oauth* ]]; then
                IFS='|' read -r description file recommendation <<< "${CRITICAL_ISSUES[$key]}"
                echo "**CRITICAL:** ${key#*|}"
                echo "- $description"
                echo "- **Fix:** $recommendation"
                echo ""
            fi
        done
    fi

    # XRPC Gaps
    echo "### 🌐 XRPC (HTTP API) Compliance Gaps"
    for key in "${!CRITICAL_ISSUES[@]} ${!IMPORTANT_ISSUES[@]}"; do
        if [[ $key == xrpc* ]]; then
            IFS='|' read -r description file recommendation <<< "${CRITICAL_ISSUES[$key]}${IMPORTANT_ISSUES[$key]}"
            echo "**${key%:*}:** ${key#*|}"
            echo "- $description"
            echo "- **Fix:** $recommendation"
            echo ""
        fi
    done

    # Repository Gaps
    echo "### 🏛️ Repository Compliance Gaps"
    for key in "${!CRITICAL_ISSUES[@]} ${!IMPORTANT_ISSUES[@]}"; do
        if [[ $key == repository* ]]; then
            IFS='|' read -r description file recommendation <<< "${CRITICAL_ISSUES[$key]}${IMPORTANT_ISSUES[$key]}"
            echo "**${key%:*}:** ${key#*|}"
            echo "- $description"
            echo "- **Fix:** $recommendation"
            echo ""
        fi
    done

    echo "## Implementation Priority Matrix"
    echo ""
    echo "| Priority | Issues | Timeline | Impact |"
    echo "|----------|--------|----------|--------|"
    if [ $CRITICAL_COUNT -gt 0 ]; then
        echo "| 🚨 Critical | $CRITICAL_COUNT | Immediate (1-2 days) | Blocks deployment |"
    fi
    if [ $IMPORTANT_COUNT -gt 0 ]; then
        echo "| ⚠️ Important | $IMPORTANT_COUNT | Short-term (1 week) | Affects usability |"
    fi
    if [ $MINOR_COUNT -gt 0 ]; then
        echo "| ℹ️ Minor | $MINOR_COUNT | Medium-term (2-4 weeks) | Best practices |"
    fi
    echo ""

    echo "## Next Steps"
    echo "1. Address critical issues immediately"
    echo "2. Implement important fixes for production readiness"
    echo "3. Plan minor improvements for future iterations"
    echo "4. Schedule follow-up compliance reviews"
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

    # Generate reports
    case "$OUTPUT_FORMAT" in
        "structured_checklist")
            generate_structured_checklist
            ;;
        "executive_summary")
            generate_executive_summary
            ;;
        "detailed_gap_analysis")
            generate_detailed_gap_analysis
            ;;
        "all")
            generate_executive_summary
            echo ""
            echo "---"
            echo ""
            generate_structured_checklist
            echo ""
            echo "---"
            echo ""
            generate_detailed_gap_analysis
            ;;
    esac
}

main "$@"