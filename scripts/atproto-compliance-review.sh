#!/bin/bash

# ATProto Compliance Review Tool
# Comprehensive compliance analysis of ATProto PDS implementations
#
# Usage:
#   ./atproto-compliance-review.sh [codebase_path] [focus_areas] [compliance_level] [output_format]
#
# Arguments:
#   codebase_path    - Path to the codebase root (default: parent of scripts directory)
#   focus_areas      - Comma-separated areas: oauth,xrpc,repository,did,lexicon,handle,crypto,all (default: all)
#   compliance_level - Strictness: basic, standard, comprehensive (default: standard)
#   output_format    - Report format: structured_checklist, executive_summary, detailed_gap_analysis, all (default: all)
#
# Examples:
#   ./atproto-compliance-review.sh /path/to/pds
#   ./atproto-compliance-review.sh . oauth,xrpc standard executive_summary

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is one level up from scripts/ directory
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

# Validate codebase path exists
if [[ ! -d "$CODEBASE_PATH" ]]; then
    echo "Error: Codebase path does not exist: $CODEBASE_PATH" >&2
    exit 1
fi

# Compliance check results (using files for storage)
# These temp files store structured issue data in pipe-delimited format:
#   category|title|description|file|recommendation
COMPLIANCE_CHECKS_FILE="/tmp/atproto_compliance_checks_$$.txt"
CRITICAL_ISSUES_FILE="/tmp/atproto_critical_issues_$$.txt"
IMPORTANT_ISSUES_FILE="/tmp/atproto_important_issues_$$.txt"
MINOR_ISSUES_FILE="/tmp/atproto_minor_issues_$$.txt"

# Clean up temp files on exit
cleanup() {
    rm -f "$COMPLIANCE_CHECKS_FILE" "$CRITICAL_ISSUES_FILE" "$IMPORTANT_ISSUES_FILE" "$MINOR_ISSUES_FILE"
}
trap cleanup EXIT

# Clean up any existing files from previous runs
rm -f "$COMPLIANCE_CHECKS_FILE" "$CRITICAL_ISSUES_FILE" "$IMPORTANT_ISSUES_FILE" "$MINOR_ISSUES_FILE"

# Create empty files to avoid "file not found" errors when reading
touch "$COMPLIANCE_CHECKS_FILE" "$CRITICAL_ISSUES_FILE" "$IMPORTANT_ISSUES_FILE" "$MINOR_ISSUES_FILE"

# Initialize counters
# Note: Use $((var + 1)) for increments to avoid bash arithmetic gotcha where
# ((var++)) returns exit code 1 when var=0, which fails under set -e
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
    local file="${5:-}"  # Optional file reference
    local recommendation="${6:-}"

    # Store issue in pipe-delimited format for later report generation
    case "$severity" in
        "critical")
            echo "$category|$title|$description|$file|$recommendation" >> "$CRITICAL_ISSUES_FILE"
            # Use $((var + 1)) to avoid exit code 1 when var=0 under set -e
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            ;;
        "important")
            echo "$category|$title|$description|$file|$recommendation" >> "$IMPORTANT_ISSUES_FILE"
            IMPORTANT_COUNT=$((IMPORTANT_COUNT + 1))
            ;;
        "minor")
            echo "$category|$title|$description|$file|$recommendation" >> "$MINOR_ISSUES_FILE"
            MINOR_COUNT=$((MINOR_COUNT + 1))
            ;;
    esac
}

mark_pass() {
    local category="$1"
    local check="$2"
    echo "$category|$check|PASS" >> "$COMPLIANCE_CHECKS_FILE"
    # Use $((var + 1)) to avoid exit code 1 when var=0 under set -e
    PASS_COUNT=$((PASS_COUNT + 1))
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
    if grep -r "lexicon\|Lexicon\|schema.*valid" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "lexicon" "schema_validation"
        log_success "Lexicon schema validation detected"
    else
        add_issue "lexicon" "minor" "Limited Schema Validation" \
            "Lexicon schema validation may be incomplete" \
            "" \
            "Implement comprehensive Lexicon schema validation for API requests/responses"
    fi

    # Check for NSID (Namespaced Identifier) handling
    if grep -r "NSID\|nsid\|com\.atproto\|app\.bsky" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "lexicon" "nsid_handling"
        log_success "NSID handling detected"
    else
        add_issue "lexicon" "minor" "Missing NSID Handling" \
            "Namespaced Identifier (NSID) parsing/validation not found" \
            "" \
            "Implement NSID format validation per ATProto NSID specification"
    fi
}

check_handle_compliance() {
    log_info "Checking Handle compliance..."

    # Check for handle resolution
    if grep -r "resolveHandle\|handle.*resolve\|HandleResolver" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "handle" "resolution"
        log_success "Handle resolution support detected"
    else
        add_issue "handle" "important" "Missing Handle Resolution" \
            "Handle resolution functionality not implemented" \
            "" \
            "Implement handle resolution via DNS TXT records and /.well-known/atproto-did"
    fi

    # Check for handle validation
    if grep -r "validateHandle\|handle.*valid\|isValidHandle" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "handle" "validation"
        log_success "Handle validation detected"
    else
        add_issue "handle" "minor" "Limited Handle Validation" \
            "Handle format validation may be incomplete" \
            "" \
            "Implement handle format validation per ATProto Handle specification"
    fi
}

check_crypto_compliance() {
    log_info "Checking Cryptography compliance..."

    # Check for secp256k1 support (required for ATProto)
    if grep -r "secp256k1\|SECP256K1" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "crypto" "secp256k1"
        log_success "secp256k1 curve support detected"
    else
        add_issue "crypto" "critical" "Missing secp256k1 Support" \
            "secp256k1 elliptic curve not implemented - required for ATProto" \
            "" \
            "Implement secp256k1 key generation and signing per ATProto Cryptography spec"
    fi

    # Check for P-256 support (alternative curve)
    if grep -r "P-256\|p256\|prime256v1\|secp256r1" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "crypto" "p256"
        log_success "P-256 curve support detected"
    else
        add_issue "crypto" "minor" "Missing P-256 Support" \
            "P-256 elliptic curve not implemented - optional but recommended" \
            "" \
            "Consider implementing P-256 as alternative signing curve"
    fi

    # Check for SHA-256 hashing
    if grep -r "SHA256\|sha256\|SHA-256" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "crypto" "sha256"
        log_success "SHA-256 hashing detected"
    else
        add_issue "crypto" "critical" "Missing SHA-256 Support" \
            "SHA-256 hashing not implemented - required for CID generation" \
            "" \
            "Implement SHA-256 hashing for content addressing"
    fi
}

check_data_model_compliance() {
    log_info "Checking Data Model compliance..."

    # Check for CBOR serialization
    if grep -r "CBOR\|cbor" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "data_model" "cbor"
        log_success "CBOR serialization detected"
    else
        add_issue "data_model" "critical" "Missing CBOR Support" \
            "CBOR serialization not implemented - required for ATProto data model" \
            "" \
            "Implement DAG-CBOR encoding/decoding per ATProto Data Model spec"
    fi

    # Check for CAR file support
    if grep -r "CAR\|car.*file\|carFile" "$CODEBASE_PATH" --include="*.m" --include="*.h" >/dev/null 2>&1; then
        mark_pass "data_model" "car_files"
        log_success "CAR file support detected"
    else
        add_issue "data_model" "important" "Missing CAR File Support" \
            "CAR (Content Addressable aRchive) file handling not implemented" \
            "" \
            "Implement CAR v1 file format for repository export/import"
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
    if [ $total_checks -gt 0 ]; then
        echo "- **Pass Rate:** $((PASS_COUNT * 100 / total_checks))%"
    else
        echo "- **Pass Rate:** N/A"
    fi
    echo "- **Critical Issues:** $CRITICAL_COUNT"
    echo "- **Important Issues:** $IMPORTANT_COUNT"
    echo "- **Minor Issues:** $MINOR_COUNT"
    echo "- **Risk Level:** $([ $CRITICAL_COUNT -gt 0 ] && echo 'HIGH' || echo 'LOW')"
    echo ""

    # Show critical issues summary if any exist (read from file, not array)
    if [ $CRITICAL_COUNT -gt 0 ]; then
        echo "## 🚨 Immediate Actions Required"
        echo "Critical compliance issues must be addressed before deployment:"
        while IFS='|' read -r category title description file recommendation; do
            echo "- **$title**: $description"
        done < "$CRITICAL_ISSUES_FILE"
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
    echo ""

    # Helper function to print issues from a file filtered by category
    print_issues_by_category() {
        local file="$1"
        local category_filter="$2"
        local severity_label="$3"
        
        if [[ -s "$file" ]]; then
            while IFS='|' read -r category title description file_ref recommendation; do
                if [[ "$category" == "$category_filter" ]]; then
                    echo "**$severity_label:** $title"
                    echo "- $description"
                    if [[ -n "$recommendation" ]]; then
                        echo "- **Fix:** $recommendation"
                    fi
                    echo ""
                fi
            done < "$file"
        fi
    }

    # OAuth Gaps
    echo "### 🔐 OAuth 2.0 Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "oauth" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "oauth" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "oauth" "MINOR"
    echo ""

    # XRPC Gaps
    echo "### 🌐 XRPC (HTTP API) Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "xrpc" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "xrpc" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "xrpc" "MINOR"
    echo ""

    # Repository Gaps
    echo "### 🏛️ Repository Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "repository" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "repository" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "repository" "MINOR"
    echo ""

    # DID Gaps
    echo "### 🆔 DID (Decentralized Identifier) Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "did" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "did" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "did" "MINOR"
    echo ""

    # Lexicon Gaps
    echo "### 📖 Lexicon Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "lexicon" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "lexicon" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "lexicon" "MINOR"
    echo ""

    # Handle Gaps
    echo "### 🏷️ Handle Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "handle" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "handle" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "handle" "MINOR"
    echo ""

    # Cryptography Gaps
    echo "### 🔐 Cryptography Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "crypto" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "crypto" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "crypto" "MINOR"
    echo ""

    # Data Model Gaps
    echo "### 🗃️ Data Model Compliance Gaps"
    print_issues_by_category "$CRITICAL_ISSUES_FILE" "data_model" "CRITICAL"
    print_issues_by_category "$IMPORTANT_ISSUES_FILE" "data_model" "IMPORTANT"
    print_issues_by_category "$MINOR_ISSUES_FILE" "data_model" "MINOR"
    echo ""

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
    if [ $CRITICAL_COUNT -eq 0 ] && [ $IMPORTANT_COUNT -eq 0 ] && [ $MINOR_COUNT -eq 0 ]; then
        echo "| ✅ None | 0 | N/A | Fully compliant |"
    fi
    echo ""

    echo "## Next Steps"
    if [ $CRITICAL_COUNT -eq 0 ] && [ $IMPORTANT_COUNT -eq 0 ] && [ $MINOR_COUNT -eq 0 ]; then
        echo "1. ✅ No compliance gaps identified"
        echo "2. Continue monitoring for ATProto specification updates"
        echo "3. Schedule periodic compliance reviews"
    else
        echo "1. Address critical issues immediately"
        echo "2. Implement important fixes for production readiness"
        echo "3. Plan minor improvements for future iterations"
        echo "4. Schedule follow-up compliance reviews"
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
    # Core protocol checks
    check_oauth_compliance
    check_xrpc_compliance
    check_repository_compliance
    check_did_compliance
    check_lexicon_compliance
    # Additional checks for comprehensive coverage
    check_handle_compliance
    check_crypto_compliance
    check_data_model_compliance

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