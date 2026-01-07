#!/bin/bash

# PLC and PDS Integration Test
# Tests the complete flow of creating an account and registering with PLC

set -e

PLC_URL="${PLC_URL:-http://localhost:2582}"
PDS_URL="${PDS_URL:-http://localhost:2583}"

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

test_pds_account_creation_with_plc() {
    log_info "Testing PDS account creation with PLC registration..."
    
    local handle="integration-test-${RANDOM}.test"
    local email="test-${RANDOM}@example.com"
    local password="testpassword123"
    
    log_info "Creating account with handle: $handle"
    
    local pds_response=$(curl -s -X POST "${PDS_URL}/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${email}\",
            \"handle\": \"${handle}\",
            \"password\": \"${password}\"
        }")
    
    if echo "$pds_response" | grep -q '"did":"did:plc:'; then
        local did=$(echo "$pds_response" | jq -r '.did')
        log_success "PDS account created: $did"
        
        log_info "Verifying DID can be resolved via PLC..."
        sleep 2
        
        local plc_response=$(curl -s "${PLC_URL}/xrpc/com.atproto.identity.resolveDid?did=${did}")
        
        if echo "$plc_response" | grep -q '"@context"'; then
            log_success "DID resolved successfully via PLC"
            
            local resolved_did=$(echo "$plc_response" | jq -r '.id')
            if [ "$resolved_did" = "$did" ]; then
                log_success "DID matches expected value"
                echo ""
                echo "========================================"
                echo "Full Integration Test: SUCCESS"
                echo "========================================"
                echo "PDS Handle: $handle"
                echo "DID: $did"
                echo "PLC Resolution: $resolved_did"
                return 0
            else
                log_error "DID mismatch: expected $did, got $resolved_did"
                return 1
            fi
        else
            log_error "Failed to resolve DID via PLC: $plc_response"
            return 1
        fi
    else
        log_error "PDS account creation failed: $pds_response"
        return 1
    fi
}

run_integration_tests() {
    echo "========================================"
    echo "PDS + PLC Integration Tests"
    echo "========================================"
    echo ""
    
    log_info "PLC URL: $PLC_URL"
    log_info "PDS URL: $PDS_URL"
    echo ""
    
    test_pds_account_creation_with_plc
}

show_help() {
    echo "PDS + PLC Integration Test"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  test     Run integration test (default)"
    echo "  help     Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  PLC_URL  PLC server URL (default: http://localhost:2582)"
    echo "  PDS_URL  PDS server URL (default: http://localhost:2583)"
}

case "${1:-test}" in
    help|--help|-h)
        show_help
        ;;
    test|*)
        run_integration_tests
        ;;
esac
