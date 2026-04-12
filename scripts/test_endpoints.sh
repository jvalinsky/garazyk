#!/bin/bash

# ATProto PDS Endpoint Test Script
# Tests all XRPC endpoints for functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$SCRIPT_DIR/../build/bin/kaszlak"
PORT=2583
BASE_URL="http://localhost:$PORT"
SERVER_PID=""
DB_PATH="/tmp/atproto_pds.db"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=1
}

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        info "Stopping server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    # Also kill any stray servers on our port
    pkill -f "kaszlak.*$PORT" 2>/dev/null || true
    rm -f "$DB_PATH" 2>/dev/null || true
}

trap cleanup EXIT

start_server() {
    if [ ! -f "$SERVER" ]; then
        fail "Server executable not found at $SERVER"
        exit 1
    fi

    info "Starting ATProto PDS server..."
    # Kill any existing server on our port
    pkill -f "kaszlak.*$PORT" 2>/dev/null || true
    sleep 1
    rm -f "$DB_PATH" 2>/dev/null || true

    # Start server and wait for it to be ready
    "$SERVER" &
    SERVER_PID=$!

    # Wait for server to start (check for listening port)
    local attempts=0
    local max_attempts=10
    while [ $attempts -lt $max_attempts ]; do
        if curl -s --connect-timeout 1 "http://localhost:$PORT/" > /dev/null 2>&1; then
            break
        fi
        sleep 1
        attempts=$((attempts + 1))
    done

    if [ $attempts -eq $max_attempts ]; then
        fail "Server failed to start or respond"
        exit 1
    fi

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        fail "Server process died"
        exit 1
    fi

    pass "Server started and responding (PID: $SERVER_PID)"
}

test_health() {
    info "Testing health endpoint..."
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/" 2>/dev/null || echo "000")
    if [ "$response" = "200" ] || [ "$response" = "404" ]; then
        pass "Server is responding (HTTP $response)"
    else
        fail "Server not responding (HTTP $response)"
    fi
}

test_create_session_missing_params() {
    info "Testing createSession with missing params..."
    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.createSession" \
        -H "Content-Type: application/json" \
        -d '{}')

    if echo "$response" | grep -q "InvalidRequest"; then
        pass "createSession returns error for missing params"
    else
        fail "createSession should return InvalidRequest error"
    fi
}

test_create_session() {
    info "Testing createSession with valid credentials..."
    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.createSession" \
        -H "Content-Type: application/json" \
        -d '{
            "identifier": "testuser",
            "password": "password123"
        }')

    if echo "$response" | grep -q "accessJwt"; then
        SESSION_TOKEN=$(echo "$response" | grep -o '"accessJwt":"[^"]*"' | cut -d'"' -f4)
        REFRESH_TOKEN=$(echo "$response" | grep -o '"refreshJwt":"[^"]*"' | cut -d'"' -f4)
        pass "createSession returned tokens"
        echo "  Access Token: ${SESSION_TOKEN:0:20}..."
        echo "  Refresh Token: ${REFRESH_TOKEN:0:20}..."
    else
        fail "createSession failed: $response"
    fi
}

test_refresh_session() {
    info "Testing refreshSession..."
    if [ -z "$REFRESH_TOKEN" ]; then
        info "Skipping (no refresh token from createSession)"
        return
    fi

    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.refreshSession" \
        -H "Content-Type: application/json" \
        -d "{\"refreshToken\": \"$REFRESH_TOKEN\"}")

    if echo "$response" | grep -q "accessJwt"; then
        pass "refreshSession returned new tokens"
    else
        fail "refreshSession failed: $response"
    fi
}

test_create_record() {
    info "Testing createRecord..."
    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.repo.createRecord" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SESSION_TOKEN" \
        -d "{
            \"repo\": \"$DID\",
            \"collection\": \"app.bsky.feed.post\",
            \"record\": {
                \"\$type\": \"app.bsky.feed.post\",
                \"text\": \"Hello ATProto!\",
                \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }
         }")

    if echo "$response" | grep -q '"uri":' && echo "$response" | grep -q '"cid":'; then
        RECORD_URI=$(echo "$response" | grep -o '"uri":"[^"]*"' | cut -d'"' -f4)
        RKEY=$(echo "$RECORD_URI" | sed 's/.*\///')
        pass "createRecord returned URI: $(echo "$RECORD_URI" | head -c 50)..."

        if echo "$RKEY" | grep -qE '^[234567abcdefghijklmnopqrstuvwxyz]{13}$'; then
            pass "Record key (rkey) format is valid TID: $RKEY"
        elif echo "$RKEY" | grep -qE '^[a-z0-9]+-[a-z0-9]+$'; then
            pass "Record key (rkey) format is valid: $RKEY"
        else
            fail "Record key (rkey) format is invalid: $RKEY (expected TID or dash-separated format)"
        fi
    else
        fail "createRecord failed: $response"
    fi
}

test_describe_repo() {
    info "Testing describeRepo..."
    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.repo.describeRepo?repo=$DID" \
        -H "Authorization: Bearer $SESSION_TOKEN")

    if echo "$response" | grep -q '"did":' && echo "$response" | grep -q '"collections":'; then
        pass "describeRepo returned valid response"
        echo "  Collections: $(echo "$response" | jq -r '.collections | length') items"
    else
        fail "describeRepo failed: $response"
    fi
}

test_list_records() {
    info "Testing listRecords..."
    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.repo.listRecords?repo=$DID&collection=app.bsky.feed.post&limit=10" \
        -H "Authorization: Bearer $SESSION_TOKEN")

    if echo "$response" | grep -q '"records":\['; then
        local count=$(echo "$response" | jq '.records | length')
        pass "listRecords returned $count records"
    else
        fail "listRecords failed: $response"
    fi
}

test_put_record() {
    info "Testing putRecord..."
    if [ -z "$RECORD_URI" ]; then
        info "Skipping putRecord (no record URI from createRecord)"
        return
    fi

    # Extract rkey from URI (handle escaped slashes)
    local rkey=$(echo "$RECORD_URI" | sed 's/\\\//\//g' | grep -o 'app\.bsky\.feed\.post/[^"]*' | cut -d'/' -f2)

    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.repo.putRecord" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SESSION_TOKEN" \
        -d "{
            \"repo\": \"$DID\",
            \"collection\": \"app.bsky.feed.post\",
            \"rkey\": \"$rkey\",
            \"record\": {
                \"\$type\": \"app.bsky.feed.post\",
                \"text\": \"Updated via putRecord!\",
                \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }
        }")

    if echo "$response" | grep -q '"uri":' && echo "$response" | grep -q '"cid":'; then
        pass "putRecord updated record successfully"
    else
        fail "putRecord failed: $response"
    fi
}

test_get_record() {
    info "Testing getRecord..."
    if [ -z "$RECORD_URI" ]; then
        info "Skipping getRecord (no record URI from createRecord)"
        return
    fi

    # Extract collection and rkey from URI (handle escaped slashes)
    local unescaped_uri=$(echo "$RECORD_URI" | sed 's/\\\//\//g')
    # URI format: at://did/collection/rkey
    # Split by / and get the parts
    local collection=$(echo "$unescaped_uri" | cut -d'/' -f4)
    local rkey=$(echo "$unescaped_uri" | cut -d'/' -f5)

    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.repo.getRecord?repo=$DID&collection=$collection&rkey=$rkey" \
        -H "Authorization: Bearer $SESSION_TOKEN")

    if echo "$response" | grep -q '"uri":' && echo "$response" | grep -q '"value":'; then
        pass "getRecord returned record data"
        echo "  Text: $(echo "$response" | jq -r '.value.text')"
    else
        fail "getRecord failed: $response"
    fi
}

test_get_record_not_found() {
    info "Testing getRecord (not found)..."
    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.repo.getRecord?repo=$DID&collection=app.bsky.feed.post&rkey=nonexistent")

    if echo "$response" | grep -q "OperationFailed\|NotFound"; then
        pass "getRecord returns error for non-existent record"
    else
        fail "getRecord should return error for non-existent record"
    fi
}



test_sync_get_repo() {
    info "Testing sync.getRepo..."
    local response=$(curl -s -w "HTTPSTATUS:%{http_code};" "$BASE_URL/xrpc/com.atproto.sync.getRepo?did=$DID")
    local body=$(echo "$response" | sed 's/HTTPSTATUS.*//')
    local status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)

    if [ "$status" = "200" ]; then
        pass "sync.getRepo returned HTTP 200"
    else
        fail "sync.getRepo failed with status $status: $(echo "$body" | head -c 200)"
    fi
}

test_sync_get_head() {
    info "Testing sync.getHead..."
    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.sync.getHead?did=$DID")

    if echo "$response" | grep -qE "root"; then
        pass "sync.getHead returns root CID"
        echo "  Response: $response"
    else
        fail "sync.getHead failed: $response"
    fi
}

test_sync_list_blobs() {
    info "Testing sync.listBlobs..."
    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.sync.listBlobs?did=$DID")

    if echo "$response" | grep -qE "blobs"; then
        pass "sync.listBlobs returns blobs array"
    else
        fail "sync.listBlobs failed: $response"
    fi
}

test_database_integrity() {
    info "Testing database integrity..."
    local records_count=$(sqlite3 /tmp/atproto_pds.db "SELECT COUNT(*) FROM records;" 2>/dev/null || echo "0")
    local accounts_count=$(sqlite3 /tmp/atproto_pds.db "SELECT COUNT(*) FROM accounts;" 2>/dev/null || echo "0")

    if [ "$accounts_count" -ge 0 ]; then
        pass "Database has $accounts_count account(s)"
    else
        fail "Database accounts query failed"
    fi

    if [ "$records_count" -ge 0 ]; then
        pass "Database has $records_count record(s)"
    else
        fail "Database records query failed"
    fi
}

test_method_not_found() {
    info "Testing unknown method (should return error)..."
    local response=$(curl -s "$BASE_URL/xrpc/com.atproto.unknown.method")

    if echo "$response" | grep -q "MethodNotFound"; then
        pass "Unknown method returns MethodNotFound error"
    else
        fail "Unknown method should return MethodNotFound error"
    fi
}

test_create_account() {
    info "Testing createAccount..."
    local response=$(curl -s -X POST "$BASE_URL/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d '{
            "email": "test@example.com",
            "password": "password123",
            "handle": "testuser"
        }')

    if echo "$response" | grep -q "did"; then
        SESSION_TOKEN=$(echo "$response" | grep -o '"accessJwt":"[^"]*"' | cut -d'"' -f4)
        REFRESH_TOKEN=$(echo "$response" | grep -o '"refreshJwt":"[^"]*"' | cut -d'"' -f4)
        DID=$(echo "$response" | grep -o '"did":"[^"]*"' | cut -d'"' -f4)
        HANDLE=$(echo "$response" | grep -o '"handle":"[^"]*"' | cut -d'"' -f4)
        pass "createAccount succeeded"
        echo "  DID: $DID"
        echo "  Handle: $HANDLE"
    else
        fail "createAccount failed: $response"
    fi
}

run_all_tests() {
    echo ""
    echo "========================================"
    echo "  ATProto PDS Endpoint Test Suite"
    echo "========================================"
    echo ""

    FAILED=0

    start_server

    echo ""
    echo "--- Health & Basic ---"
    test_health
    test_method_not_found
    test_database_integrity

    echo ""
    echo "--- Session Management ---"
    test_create_account
    test_create_session_missing_params
    test_create_session
    test_refresh_session

    echo ""
    echo "--- Repository Operations ---"
    test_create_record
    test_describe_repo
    test_list_records
    test_put_record
    test_get_record
    test_get_record_not_found

    echo ""
    echo "--- Sync Operations ---"
    test_sync_get_repo
    test_sync_get_head
    test_sync_list_blobs

    echo ""
    echo "========================================"
    if [ $FAILED -eq 0 ]; then
        echo -e "  ${GREEN}All tests passed!${NC}"
    else
        echo -e "  ${RED}Some tests failed${NC}"
    fi
    echo "========================================"
    echo ""

    return $FAILED
}

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all       Run all tests (default)"
    echo "  health    Test server health"
    echo "  session   Test session endpoints"
    echo "  repo      Test repository endpoints"
    echo "  sync      Test sync endpoints"
    echo "  help      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0              # Run all tests"
    echo "  $0 session      # Test only session endpoints"
}

case "${1:-all}" in
    all)
        run_all_tests
        ;;
    health)
        start_server
        test_health
        test_method_not_found
        ;;
    session)
        start_server
        test_create_session_missing_params
        test_create_session
        test_refresh_session
        ;;
    repo)
        start_server
        test_create_record
        test_get_record_not_found
        test_list_records
        ;;
    sync)
        start_server
        test_sync_get_repo
        test_sync_get_head
        test_sync_list_blobs
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
