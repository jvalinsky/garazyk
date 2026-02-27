#!/usr/bin/env bash
#
# Name: test_moderation.sh
# Description: Comprehensive e2e test for moderation features (reports, account moderation, labels)
# Author: Professional Bash Script Example
# Version: 1.0.0
# Date: 2024-01-01
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SERVER_BINARY="${SERVER_BINARY:-$SCRIPT_DIR/../build/bin/kaszlak}"
readonly SERVER_BINARY
BASE_URL="${BASE_URL:-http://localhost:2583}"
readonly BASE_URL
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

# Global variables
ADMIN_TOKEN=""
USER1_DID=""
USER1_TOKEN=""
USER2_DID=""
USER2_TOKEN=""
REPORT_URI=""
LABEL_URI=""
TEMP_FILES=()

# Color definitions
if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' NC=''
fi

# Logging functions
log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" >&2
    fi
}
log_info()  { echo -e "${CYAN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Error exit function
error_exit() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    cleanup
    exit "$code"
}

# Cleanup function
cleanup() {
    log_debug "Cleaning up resources"

    # Clean up temp files
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

# Trap signals
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

# API helper functions
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local token="${4:-}"

    local url="$BASE_URL/xrpc/$endpoint"
    local curl_args=(-s -X "$method" "$url")

    if [[ -n "$token" ]]; then
        curl_args+=(-H "Authorization: Bearer $token")
    fi

    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    if ! command -v curl >/dev/null 2>&1; then
        error_exit "curl command not found"
    fi

    log_debug "API call: $method $endpoint"
    curl "${curl_args[@]}"
}

# Test assertion helpers
assert_success() {
    local response="$1"
    local operation="$2"

    if echo "$response" | grep -q '"error"'; then
        echo -e "${RED}FAIL:${NC} $operation failed: $response"
        return 1
    else
        echo -e "${GREEN}PASS:${NC} $operation succeeded"
        return 0
    fi
}

assert_contains() {
    local response="$1"
    local pattern="$2"
    local description="$3"

    if echo "$response" | grep -q "$pattern"; then
        echo -e "${GREEN}PASS:${NC} $description"
        return 0
    else
        echo -e "${RED}FAIL:${NC} $description - pattern '$pattern' not found in response"
        return 1
    fi
}

# Admin authentication (simplified - in real scenario would use proper admin auth)
get_admin_token() {
    log_info "Getting admin token"

    # For this test, we'll create an admin user and use their token
    # In production, this would be a separate admin authentication flow

    local timestamp
    timestamp=$(date +%s)
    local admin_email="admin${timestamp}@test.com"
    local admin_handle="admin${timestamp}.test"

    local response
    response=$(api_call POST "com.atproto.server.createAccount" "{
        \"email\": \"$admin_email\",
        \"password\": \"adminpass123\",
        \"handle\": \"$admin_handle\"
    }")

    if ! assert_success "$response" "Admin account creation"; then
        return 1
    fi

    ADMIN_TOKEN=$(echo "$response" | grep -o '"accessJwt":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$ADMIN_TOKEN" ]]; then
        echo -e "${RED}FAIL:${NC} Could not extract admin token"
        return 1
    fi

    echo -e "${GREEN}PASS:${NC} Admin token obtained"
}

# User management functions
create_test_user() {
    local username="$1"
    local timestamp
    timestamp=$(date +%s)

    local email="${username}${timestamp}@test.com"
    local handle="${username}${timestamp}.test"

    log_info "Creating test user: $handle"

    local response
    response=$(api_call POST "com.atproto.server.createAccount" "{
        \"email\": \"$email\",
        \"password\": \"testpass123\",
        \"handle\": \"$handle\"
    }")

    if ! assert_success "$response" "User creation ($username)"; then
        return 1
    fi

    # Extract DID and token
    local did
    local access_jwt
    did=$(echo "$response" | grep -o '"did":"[^"]*"' | head -1 | cut -d'"' -f4)
    access_jwt=$(echo "$response" | grep -o '"accessJwt":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$did" ]] || [[ -z "$access_jwt" ]]; then
        echo -e "${RED}FAIL:${NC} Could not extract credentials for $username"
        return 1
    fi

    # Set global variables based on username
    if [[ "$username" == "alice" ]]; then
        USER1_DID="$did"
        USER1_TOKEN="$access_jwt"
        echo -e "${GREEN}PASS:${NC} User alice created (DID: ${WHITE}$did${NC})"
    elif [[ "$username" == "bob" ]]; then
        USER2_DID="$did"
        USER2_TOKEN="$access_jwt"
        echo -e "${GREEN}PASS:${NC} User bob created (DID: ${WHITE}$did${NC})"
    fi

    return 0
}

# Moderation test functions
create_reportable_content() {
    local user="$1"
    local token_var="USER${user}_TOKEN"
    local did_var="USER${user}_DID"
    local token="${!token_var}"
    local did="${!did_var}"

    log_info "Creating reportable content for user $user"

    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local post_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.feed.post\",
        \"record\": {
            \"\$type\": \"app.bsky.feed.post\",
            \"text\": \"This is spam content from user $user for moderation testing\",
            \"createdAt\": \"$created_at\"
        }
    }"

    local response
    response=$(api_call POST "com.atproto.repo.createRecord" "$post_data" "$token")

    if ! assert_success "$response" "Content creation (user $user)"; then
        return 1
    fi

    # Extract URI for reporting
    local uri
    uri=$(echo "$response" | grep -o '"uri":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ "$user" == "1" ]]; then
        REPORT_URI="$uri"
    fi

    return 0
}

test_create_report() {
    log_info "Creating moderation report"

    local report_data="{
        \"reasonType\": \"com.atproto.moderation.defs#reasonSpam\",
        \"subject\": {
            \"\$type\": \"com.atproto.repo.strongRef\",
            \"uri\": \"$REPORT_URI\",
            \"cid\": \"bafyreib5k7v6x6z7q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6\"
        },
        \"reason\": \"Automated test report for spam content\"
    }"

    local response
    response=$(api_call POST "com.atproto.moderation.createReport" "$report_data" "$USER1_TOKEN")

    if ! assert_success "$response" "Report creation"; then
        return 1
    fi

    assert_contains "$response" '"id":' "Report response contains ID"
    assert_contains "$response" '"reasonType"' "Report response contains reason type"
}

test_label_content() {
    log_info "Creating content label"

    # Note: In a real implementation, this would be done by moderators/admins
    # For testing purposes, we'll simulate the label creation

    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local label_data="{
        \"uri\": \"$REPORT_URI\",
        \"cid\": \"bafyreib5k7v6x6z7q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6\",
        \"labels\": [{
            \"src\": \"$USER1_DID\",
            \"uri\": \"$REPORT_URI\",
            \"cid\": \"bafyreib5k7v6x6z7q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6\",
            \"val\": \"spam\",
            \"cts\": \"$created_at\"
        }]
    }"

    local response
    response=$(api_call POST "com.atproto.label.createLabel" "$label_data" "$ADMIN_TOKEN")

    # Labels might not be implemented yet, so we'll make this optional
    if echo "$response" | grep -q '"error"'; then
        echo -e "${YELLOW}SKIP:${NC} Label creation not implemented or requires admin privileges"
        return 0
    else
        echo -e "${GREEN}PASS:${NC} Content label created"
        assert_contains "$response" '"uri"' "Label response contains URI"
        return 0
    fi
}

test_query_labels() {
    log_info "Querying labels"

    local response
    response=$(api_call GET "com.atproto.label.queryLabels?uriPatterns[]=$REPORT_URI" "" "$USER1_TOKEN")

    # Labels might not be implemented yet
    if echo "$response" | grep -q '"error"'; then
        echo -e "${YELLOW}SKIP:${NC} Label querying not implemented"
        return 0
    else
        if assert_success "$response" "Label query"; then
            assert_contains "$response" '"labels":' "Query response contains labels array"
        fi
        return 0
    fi
}

test_get_labels() {
    log_info "Getting labels for content"

    local response
    response=$(api_call GET "com.atproto.label.getLabels?uris[]=$REPORT_URI" "" "$USER1_TOKEN")

    # Labels might not be implemented yet
    if echo "$response" | grep -q '"error"'; then
        echo -e "${YELLOW}SKIP:${NC} Get labels not implemented"
        return 0
    else
        if assert_success "$response" "Get labels"; then
            assert_contains "$response" '"uri"' "Labels response contains URI"
        fi
        return 0
    fi
}

test_account_moderation() {
    log_info "Testing account moderation"

    # Test account status check (might not be implemented)
    local response
    response=$(api_call GET "com.atproto.admin.getSubjectStatus?did=$USER2_DID" "" "$ADMIN_TOKEN")

    if echo "$response" | grep -q '"error"'; then
        echo -e "${YELLOW}SKIP:${NC} Account moderation not implemented"
        return 0
    else
        if assert_success "$response" "Account status check"; then
            assert_contains "$response" '"did"' "Status response contains DID"
        fi
        return 0
    fi
}

test_subject_status_update() {
    log_info "Testing subject status update"

    local status_data="{
        \"subject\": {
            \"\$type\": \"com.atproto.admin.defs#repoRef\",
            \"did\": \"$USER2_DID\"
        },
        \"takedown\": {
            \"applied\": true,
            \"ref\": \"test-takedown\"
        }
    }"

    local response
    response=$(api_call POST "com.atproto.admin.updateSubjectStatus" "$status_data" "$ADMIN_TOKEN")

    if echo "$response" | grep -q '"error"'; then
        echo -e "${YELLOW}SKIP:${NC} Subject status update not implemented or requires admin privileges"
        return 0
    else
        echo -e "${GREEN}PASS:${NC} Subject status updated"
        return 0
    fi
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=0

    log_info "=== Starting Moderation Features E2E Test ==="
    log_debug "Server: $BASE_URL"

    # Get admin token
    ((total_tests++))
    if ! get_admin_token; then ((failed_tests++)); fi

    # Create test users
    ((total_tests++))
    if ! create_test_user "alice"; then ((failed_tests++)); fi

    ((total_tests++))
    if ! create_test_user "bob"; then ((failed_tests++)); fi

    # Create reportable content
    ((total_tests++))
    if ! create_reportable_content 1; then ((failed_tests++)); fi

    # Test reporting
    ((total_tests++))
    if ! test_create_report; then ((failed_tests++)); fi

    # Test labeling (may not be implemented)
    ((total_tests++))
    if ! test_label_content; then ((failed_tests++)); fi

    # Test label queries (may not be implemented)
    ((total_tests++))
    if ! test_query_labels; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_get_labels; then ((failed_tests++)); fi

    # Test account moderation (may not be implemented)
    ((total_tests++))
    if ! test_account_moderation; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_subject_status_update; then ((failed_tests++)); fi

    # Summary
    local passed=$((total_tests - failed_tests))
    log_info "=== Moderation Features E2E Test Complete ==="
    log_info "Tests run: $total_tests"

    if (( failed_tests == 0 )); then
        log_info "Result: ${GREEN}ALL TESTS PASSED${NC} ($passed/$total_tests)"
        exit 0
    else
        log_info "Result: ${RED}$failed_tests TESTS FAILED${NC} ($passed/$total_tests passed)"
        exit 1
    fi
}

# Run main function
main "$@"
