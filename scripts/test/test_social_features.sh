#!/usr/bin/env bash
#
# Name: test_social_features.sh
# Description: Comprehensive e2e test for social features (feed, follows, likes, profiles)
# Author: Professional Bash Script Example
# Version: 1.0.0
# Date: 2024-01-01
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
readonly REPO_ROOT
SERVER_BINARY="${SERVER_BINARY:-$REPO_ROOT/build/bin/kaszlak}"
readonly SERVER_BINARY
BASE_URL="${BASE_URL:-http://localhost:2583}"
readonly BASE_URL
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

# Global variables
USER1_DID=""
USER1_TOKEN=""
USER2_DID=""
USER2_TOKEN=""
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

# User management functions
create_test_user() {
    local username="$1"
    local email_suffix="${2:-test.com}"
    local timestamp
    timestamp=$(date +%s)

    local email="${username}${timestamp}@${email_suffix}"
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

# Social features test functions
test_create_post() {
    local user="$1"
    local token_var="USER${user}_TOKEN"
    local did_var="USER${user}_DID"
    local token="${!token_var}"
    local did="${!did_var}"

    log_info "Creating post for user $user"

    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local post_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.feed.post\",
        \"record\": {
            \"\$type\": \"app.bsky.feed.post\",
            \"text\": \"Hello from user $user! #test\",
            \"createdAt\": \"$created_at\"
        }
    }"

    local response
    response=$(api_call POST "com.atproto.repo.createRecord" "$post_data" "$token")

    if ! assert_success "$response" "Post creation (user $user)"; then
        return 1
    fi

    # Extract URI for later use
    local uri
    uri=$(echo "$response" | grep -o '"uri":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ "$user" == "1" ]]; then
        POST1_URI="$uri"
    elif [[ "$user" == "2" ]]; then
        POST2_URI="$uri"
    fi

    return 0
}

test_get_profile() {
    local user="$1"
    local target_did="$2"

    log_info "Getting profile for user $user"

    local response
    response=$(api_call GET "app.bsky.actor.getProfile?actor=$target_did")

    if ! assert_success "$response" "Get profile (user $user)"; then
        return 1
    fi

    assert_contains "$response" '"did":"'"$target_did"'"' "Profile contains correct DID"
}

test_follow_user() {
    local follower="$1"
    local target_did="$2"
    local token_var="USER${follower}_TOKEN"
    local did_var="USER${follower}_DID"
    local token="${!token_var}"
    local did="${!did_var}"

    log_info "User $follower following $target_did"

    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local follow_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.graph.follow\",
        \"record\": {
            \"\$type\": \"app.bsky.graph.follow\",
            \"subject\": \"$target_did\",
            \"createdAt\": \"$created_at\"
        }
    }"

    local response
    response=$(api_call POST "com.atproto.repo.createRecord" "$follow_data" "$token")

    assert_success "$response" "Follow creation (user $follower -> $target_did)"
}

test_like_post() {
    local liker="$1"
    local post_uri="$2"
    local token_var="USER${liker}_TOKEN"
    local did_var="USER${liker}_DID"
    local token="${!token_var}"
    local did="${!did_var}"

    log_info "User $liker liking post: $post_uri"

    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local like_data="{
        \"repo\": \"$did\",
        \"collection\": \"app.bsky.feed.like\",
        \"record\": {
            \"\$type\": \"app.bsky.feed.like\",
            \"subject\": {
                \"uri\": \"$post_uri\",
                \"cid\": \"bafyreib5k7v6x6z7q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6q6\"
            },
            \"createdAt\": \"$created_at\"
        }
    }"

    local response
    response=$(api_call POST "com.atproto.repo.createRecord" "$like_data" "$token")

    assert_success "$response" "Like creation (user $liker)"
}

test_get_timeline() {
    local user="$1"
    local token_var="USER${user}_TOKEN"
    local token="${!token_var}"

    log_info "Getting timeline for user $user"

    local response
    response=$(api_call GET "app.bsky.feed.getTimeline" "" "$token")

    if ! assert_success "$response" "Get timeline (user $user)"; then
        return 1
    fi

    # Check if timeline contains posts
    if echo "$response" | grep -q '"feed":\['; then
        echo -e "${GREEN}PASS:${NC} Timeline contains posts"
        return 0
    else
        echo -e "${YELLOW}WARN:${NC} Timeline is empty (expected for new accounts)"
        return 0
    fi
}

test_get_author_feed() {
    local user="$1"
    local target_did="$2"
    local token_var="USER${user}_TOKEN"
    local token="${!token_var}"

    log_info "Getting author feed for user $user (target: $target_did)"

    local response
    response=$(api_call GET "app.bsky.feed.getAuthorFeed?actor=$target_did" "" "$token")

    if ! assert_success "$response" "Get author feed (user $user)"; then
        return 1
    fi

    assert_contains "$response" '"feed":' "Author feed response contains feed array"
}

test_search_actors() {
    local user="$1"
    local query="$2"
    local token_var="USER${user}_TOKEN"
    local token="${!token_var}"

    log_info "Searching actors for user $user (query: $query)"

    local response
    response=$(api_call GET "app.bsky.actor.searchActors?q=$query&limit=5" "" "$token")

    if ! assert_success "$response" "Actor search (user $user)"; then
        return 1
    fi

    assert_contains "$response" '"actors":' "Search response contains actors array"
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=0

    log_info "=== Starting Social Features E2E Test ==="
    log_debug "Server: $BASE_URL"
    log_debug "Binary: $SERVER_BINARY"

    # Create test users
    ((total_tests++))
    if ! create_test_user "alice"; then ((failed_tests++)); fi

    ((total_tests++))
    if ! create_test_user "bob"; then ((failed_tests++)); fi

    # Test profile retrieval
    ((total_tests++))
    if ! test_get_profile 1 "$USER2_DID"; then ((failed_tests++)); fi

    # Create posts
    ((total_tests++))
    if ! test_create_post 1; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_create_post 2; then ((failed_tests++)); fi

    # Test following
    ((total_tests++))
    if ! test_follow_user 1 "$USER2_DID"; then ((failed_tests++)); fi

    # Test liking posts
    ((total_tests++))
    if ! test_like_post 1 "$POST2_URI"; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_like_post 2 "$POST1_URI"; then ((failed_tests++)); fi

    # Test timeline
    ((total_tests++))
    if ! test_get_timeline 1; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_get_timeline 2; then ((failed_tests++)); fi

    # Test author feeds
    ((total_tests++))
    if ! test_get_author_feed 1 "$USER2_DID"; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_get_author_feed 2 "$USER1_DID"; then ((failed_tests++)); fi

    # Test actor search
    ((total_tests++))
    if ! test_search_actors 1 "alice"; then ((failed_tests++)); fi

    ((total_tests++))
    if ! test_search_actors 2 "bob"; then ((failed_tests++)); fi

    # Summary
    local passed=$((total_tests - failed_tests))
    log_info "=== Social Features E2E Test Complete ==="
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
