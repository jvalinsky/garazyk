#!/usr/bin/env bash
#
# Name: simple_test.sh
# Description: Simple test script to isolate ATProto PDS server issues
# Author: Professional Bash Script Example
# Version: 1.0.0
# Date: 2024-01-01
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SERVER="$SCRIPT_DIR/../build/bin/september"
readonly SERVER
PORT="${PORT:-2583}"
readonly PORT
BASE_URL="http://localhost:$PORT"
readonly BASE_URL
DB_PATH="${DB_PATH:-/tmp/atproto_pds.db}"
readonly DB_PATH
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

# Global variables for cleanup
SERVER_PID=""
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
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly NC=''
fi

# Logging functions with colors
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

    # Stop server
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Stopping server (PID: $SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    # Kill any remaining server processes
    pkill -f "september.*$PORT" 2>/dev/null || true

    # Remove temporary files
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done

    # Clean up database
    [[ -f "$DB_PATH" ]] && rm -f "$DB_PATH" 2>/dev/null || true
}

# Trap signals
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

# test_health: Test server health endpoint
# Returns: 0 on success, 1 on failure
test_health() {
    log_info "Testing health endpoint"

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl command not found"
        return 1
    fi

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/" 2>/dev/null) || response="000"

    case "$response" in
        200|404)
            echo -e "${GREEN}PASS:${NC} Server is responding (HTTP $response)"
            return 0
            ;;
        *)
            echo -e "${RED}FAIL:${NC} Server not responding (HTTP $response)"
            return 1
            ;;
    esac
}

# test_create_account: Test account creation endpoint
# Returns: 0 on success, 1 on failure
# Sets: DID global variable on success
test_create_account() {
    log_info "Testing createAccount endpoint"

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl command not found"
        return 1
    fi

    local timestamp
    timestamp=$(date +%s)

    local response
    response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"test${timestamp}@example.com\",
            \"password\": \"password123\",
            \"handle\": \"testuser${timestamp}\"
        }")

    if echo "$response" | grep -q '"did"'; then
        # Extract DID safely
        DID=$(echo "$response" | grep -o '"did":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [[ -n "$DID" ]]; then
            echo -e "${GREEN}PASS:${NC} createAccount succeeded - DID: ${WHITE}$DID${NC}"
            return 0
        else
            echo -e "${RED}FAIL:${NC} Could not extract DID from response: $response"
            return 1
        fi
    else
        echo -e "${RED}FAIL:${NC} createAccount failed: $response"
        return 1
    fi
}

# test_create_record: Test record creation endpoint
# Arguments: None (uses global DID)
# Returns: 0 on success, 1 on failure
test_create_record() {
    if [[ -z "${DID:-}" ]]; then
        echo -e "${YELLOW}SKIP:${NC} test_create_record - no DID available"
        return 0
    fi

    log_info "Testing createRecord endpoint"

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl command not found"
        return 1
    fi

    local created_at
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local response
    response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.repo.createRecord" \
        -H "Content-Type: application/json" \
        -d "{
            \"repo\": \"$DID\",
            \"collection\": \"app.bsky.feed.post\",
            \"record\": {
                \"\$type\": \"app.bsky.feed.post\",
                \"text\": \"Hello ATProto!\",
                \"createdAt\": \"$created_at\"
            }
        }")

    if echo "$response" | grep -q '"uri"'; then
        echo -e "${GREEN}PASS:${NC} createRecord succeeded"
        [[ "$VERBOSE" == "true" ]] && echo "Response: $response"
        return 0
    else
        echo -e "${RED}FAIL:${NC} createRecord failed: $response"
        return 1
    fi
}

# test_list_records: Test record listing endpoint
# Arguments: None (uses global DID)
# Returns: 0 on success, 1 on failure
test_list_records() {
    if [[ -z "${DID:-}" ]]; then
        echo -e "${YELLOW}SKIP:${NC} test_list_records - no DID available"
        return 0
    fi

    log_info "Testing listRecords endpoint"

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl command not found"
        return 1
    fi

    local url="$BASE_URL/xrpc/com.atproto.repo.listRecords?repo=$DID&collection=app.bsky.feed.post"
    local response
    response=$(curl -s "$url")

    if echo "$response" | grep -q '"records"'; then
        echo -e "${GREEN}PASS:${NC} listRecords succeeded"
        [[ "$VERBOSE" == "true" ]] && echo "Response: $response"
        return 0
    else
        echo -e "${RED}FAIL:${NC} listRecords failed: $response"
        return 1
    fi
}

# test_get_record: Test record retrieval endpoint
# Arguments: None (uses global DID)
# Returns: 0 on success, 1 on failure
test_get_record() {
    if [[ -z "${DID:-}" ]]; then
        echo -e "${YELLOW}SKIP:${NC} test_get_record - no DID available"
        return 0
    fi

    log_info "Testing getRecord endpoint"

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl command not found"
        return 1
    fi

    local url="$BASE_URL/xrpc/com.atproto.repo.getRecord?repo=$DID&collection=app.bsky.feed.post&rkey=test"
    local response
    response=$(curl -s "$url")

    if echo "$response" | grep -q '"uri"\|"error"'; then
        echo -e "${GREEN}PASS:${NC} getRecord responded"
        [[ "$VERBOSE" == "true" ]] && echo "Response: $response"
        return 0
    else
        echo -e "${RED}FAIL:${NC} getRecord failed: $response"
        return 1
    fi
}

# Dependency check
check_dependencies() {
    local deps=("curl" "pkill" "date")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        error_exit "Missing dependencies: ${missing[*]}" 3
    fi
}

# Validate server binary
validate_server() {
    if [[ ! -x "$SERVER" ]]; then
        error_exit "Server binary not found or not executable: $SERVER" 5
    fi

    log_debug "Server binary validated: $SERVER"
}

# start_server: Start the ATProto PDS server
# Returns: 0 on success, 1 on failure
start_server() {
    log_info "Starting ATProto PDS server"

    # Clean up any existing server processes
    pkill -f "september.*$PORT" 2>/dev/null || true
    sleep 1

    # Remove old database
    [[ -f "$DB_PATH" ]] && rm -f "$DB_PATH" 2>/dev/null || true

    # Start server in background
    "$SERVER" &
    SERVER_PID=$!

    # Wait for server to start
    local retries=10
    local i=0
    while (( i < retries )); do
        if kill -0 "$SERVER_PID" 2>/dev/null; then
            sleep 1  # Give server time to fully initialize
            if test_health >/dev/null 2>&1; then
                echo -e "${GREEN}PASS:${NC} Server started (PID: ${WHITE}$SERVER_PID${NC})"
                return 0
            fi
        fi
        ((i++))
        sleep 1
    done

    error_exit "Server failed to start or respond" 1
}

# run_tests: Execute all test functions
# Returns: Number of failed tests
run_tests() {
    local failed=0

    log_info "Running test suite"

    if ! test_health; then ((failed++)); fi
    if ! test_create_account; then ((failed++)); fi
    if ! test_create_record; then ((failed++)); fi
    if ! test_get_record; then ((failed++)); fi
    if ! test_list_records; then ((failed++)); fi

    if (( failed == 0 )); then
        log_info "Test suite completed: ${GREEN}$((5 - failed))/5 tests passed${NC}"
    else
        log_info "Test suite completed: ${GREEN}$((5 - failed))/5 tests passed${NC} (${RED}$failed failed${NC})"
    fi
    return "$failed"
}

# Main function
main() {
    local failed_tests=0

    log_info "Starting ATProto PDS simple test suite"
    log_debug "Configuration: PORT=$PORT, SERVER=$SERVER, DB_PATH=$DB_PATH"

    # Validate prerequisites
    check_dependencies
    validate_server

    # Start server
    start_server

    # Run tests
    if ! run_tests; then
        failed_tests=$?
        log_error "Test suite failed with $failed_tests failures"
        exit 1
    fi

    log_info "All tests passed successfully"
}

# Run main function with all arguments
main "$@"
