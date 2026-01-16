#!/bin/bash

# PLC E2E Test Runner
# Tests for simulating writes to plc.directory when creating new accounts

set -e

PLC_URL="${PLC_URL:-http://localhost:2582}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-plc}"
DB_PASSWORD="${DB_PASSWORD:-plc_secret}"
DB_NAME="${DB_NAME:-plc}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

wait_for_plc() {
    log_info "Waiting for PLC server to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "${PLC_URL}/_health" | grep -q '"status":"ok"'; then
            log_success "PLC server is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    
    log_error "PLC server failed to become ready"
    return 1
}

test_health_check() {
    log_info "Testing health check endpoint..."
    
    local response=$(curl -s "${PLC_URL}/_health")
    
    if echo "$response" | grep -q '"status":"ok"'; then
        log_success "Health check passed"
        return 0
    else
        log_error "Health check failed: $response"
        return 1
    fi
}

test_create_account() {
    log_info "Testing account creation..."
    
    local signing_key="kixi7nxzyoun6zhxrhs64oizlq37wd9ku6q6mws6lwhl77k6"
    local rotation_key1="kixk7nxzyoun6zhxrhs64oizlq37wd9ku6q6mws6lwhl77k6"
    local rotation_key2="kixl7nxzyoun6zhxrhs64oizlq37wd9ku6q6mws6lwhl77k6"
    local handle="testuser${RANDOM}.test"
    
    local response=$(curl -s -X POST "${PLC_URL}/xrpc/plc.createAccount" \
        -H "Content-Type: application/json" \
        -d "{
            \"signingKey\": \"${signing_key}\",
            \"rotationKeys\": [\"${rotation_key1}\", \"${rotation_key2}\"],
            \"handle\": \"${handle}\",
            \"services\": {
                \"atproto_pds\": {
                    \"type\": \"AtprotoPersonalDataServer\",
                    \"endpoint\": \"http://localhost:2583\"
                }
            }
        }")
    
    if echo "$response" | grep -q '"did":"did:plc:'; then
        log_success "Account created successfully: $(echo $response | jq -r '.did')"
        echo "$response" | jq -r '.did'
        return 0
    else
        log_error "Account creation failed: $response"
        return 1
    fi
}

test_get_account() {
    local did=$1
    
    log_info "Testing get account for: $did"
    
    local response=$(curl -s "${PLC_URL}/xrpc/plc.getAccount?did=${did}")
    
    if echo "$response" | grep -q '"did":"'"$did"'"'; then
        log_success "Account retrieved successfully"
        echo "$response" | jq '.'
        return 0
    else
        log_error "Failed to get account: $response"
        return 1
    fi
}

test_resolve_did() {
    local did=$1
    
    log_info "Testing DID resolution for: $did"
    
    local response=$(curl -s "${PLC_URL}/xrpc/com.atproto.identity.resolveDid?did=${did}")
    
    if echo "$response" | grep -q '"@context"'; then
        log_success "DID resolved successfully"
        echo "$response" | jq '.id'
        return 0
    else
        log_error "Failed to resolve DID: $response"
        return 1
    fi
}

test_update_account() {
    local did=$1
    local prev=$2
    
    log_info "Testing account update for: $did"
    
    local new_handle="updated${RANDOM}.test"
    
    local response=$(curl -s -X POST "${PLC_URL}/xrpc/plc.updateAccount" \
        -H "Content-Type: application/json" \
        -d "{
            \"did\": \"${did}\",
            \"handle\": \"${new_handle}\",
            \"prev\": \"${prev}\"
        }")
    
    if echo "$response" | grep -q '"success":true'; then
        log_success "Account updated successfully"
        return 0
    else
        log_error "Failed to update account: $response"
        return 1
    fi
}

test_get_operation_log() {
    local did=$1
    
    log_info "Testing operation log for: $did"
    
    local response=$(curl -s "${PLC_URL}/xrpc/plc.getOperationLog?did=${did}")
    
    if echo "$response" | grep -q '"operations"'; then
        local count=$(echo "$response" | jq -r '.operations | length')
        log_success "Operation log retrieved with $count operations"
        return 0
    else
        log_error "Failed to get operation log: $response"
        return 1
    fi
}

run_all_tests() {
    echo "========================================"
    echo "PLC Directory E2E Tests"
    echo "========================================"
    echo ""
    
    wait_for_plc || exit 1
    
    local passed=0
    local failed=0
    
    if test_health_check; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    local did=$(test_create_account) || exit 1
    passed=$((passed + 1))
    
    if test_get_account "$did"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    if test_resolve_did "$did"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    if test_get_operation_log "$did"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    
    echo ""
    echo "========================================"
    echo "Test Results: $passed passed, $failed failed"
    echo "========================================"
    
    if [ $failed -gt 0 ]; then
        exit 1
    fi
}

show_help() {
    echo "PLC E2E Test Runner"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  health        Test health check endpoint"
    echo "  create        Test account creation"
    echo "  get           Test get account (requires DID)"
    echo "  resolve       Test DID resolution (requires DID)"
    echo "  update        Test account update (requires DID and prev)"
    echo "  log           Test operation log (requires DID)"
    echo "  all           Run all tests (default)"
    echo ""
    echo "Environment Variables:"
    echo "  PLC_URL       PLC server URL (default: http://localhost:2582)"
}

case "${1:-all}" in
    health)
        wait_for_plc || exit 1
        test_health_check
        ;;
    create)
        wait_for_plc || exit 1
        test_create_account
        ;;
    get)
        wait_for_plc || exit 1
        test_get_account "$2"
        ;;
    resolve)
        wait_for_plc || exit 1
        test_resolve_did "$2"
        ;;
    update)
        wait_for_plc || exit 1
        test_update_account "$2" "$3"
        ;;
    log)
        wait_for_plc || exit 1
        test_get_operation_log "$2"
        ;;
    all|*)
        run_all_tests
        ;;
esac
