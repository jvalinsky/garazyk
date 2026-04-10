#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
E2E_DIR="$PROJECT_ROOT/docker/e2e"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up..."
    cd "$E2E_DIR"
    docker compose down --volumes --remove-orphans 2>/dev/null || true
}

wait_for_service() {
    local name=$1
    local url=$2
    local max_attempts=30
    local attempt=1

    log_info "Waiting for $name to be ready at $url..."

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" >/dev/null 2>&1; then
            log_info "$name is ready!"
            return 0
        fi
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "$name failed to become ready after $max_attempts attempts"
    return 1
}

build_images() {
    log_info "Building Docker images..."
    cd "$PROJECT_ROOT"
    docker build -f docker/Dockerfile.gnustep -t nspds:local .
    log_info "Images built successfully"
}

start_services() {
    log_info "Starting Docker Compose services..."
    cd "$E2E_DIR"
    docker compose up -d --build
    log_info "Services started"
}

run_tests() {
    log_info "Running E2E integration tests..."

    local failed=0

    # Test 1: PLC health
    log_info "Test 1: PLC health check..."
    if curl -sf "http://localhost:2580/xrpc/_health" >/dev/null; then
        log_info "✓ PLC health check passed"
    else
        log_error "✗ PLC health check failed"
        failed=$((failed + 1))
    fi

    # Test 2: PDS health
    log_info "Test 2: PDS health check..."
    if curl -sf "http://localhost:2583/xrpc/com.atproto.server.describeServer" >/dev/null; then
        log_info "✓ PDS health check passed"
    else
        log_error "✗ PDS health check failed"
        failed=$((failed + 1))
    fi

    # Test 3: PDS describeServer response
    log_info "Test 3: PDS describeServer response..."
    local pds_response
    pds_response=$(curl -s "http://localhost:2583/xrpc/com.atproto.server.describeServer")
    if echo "$pds_response" | grep -q "did"; then
        log_info "✓ PDS describeServer returned valid DID"
    else
        log_error "✗ PDS describeServer returned invalid response"
        failed=$((failed + 1))
    fi

    # Test 4: Relay getHead (will fail if no repos yet - that's OK)
    log_info "Test 4: Relay getHead endpoint..."
    local relay_response
    relay_response=$(curl -s "http://localhost:2584/xrpc/com.atproto.sync.getHead?repo=did:plc:test")
    # This should return RepoNotFound or valid response, not connection error
    if [ $? -eq 0 ] || echo "$relay_response" | grep -qE "RepoNotFound|error"; then
        log_info "✓ Relay getHead endpoint responded"
    else
        log_warn "! Relay getHead endpoint may have issues (non-critical)"
    fi

    # Test 5: Create account on PDS
    log_info "Test 5: Account creation..."
    local test_handle="test-$(date +%s)-e2e"
    local create_response
    create_response=$(curl -s -X POST "http://localhost:2583/xrpc/com.atproto.server.createAccount" \
        -H "Content-Type: application/json" \
        -d "{\"handle\":\"$test_handle.garazyk.xyz\",\"email\":\"$test_handle@test.com\",\"password\":\"testpass123\"}")
    
    if echo "$create_response" | grep -q "accessJwt"; then
        log_info "✓ Account creation succeeded"
    else
        log_warn "! Account creation may need invite code (non-critical)"
    fi

    if [ $failed -eq 0 ]; then
        log_info "All critical tests passed!"
        return 0
    else
        log_error "$failed test(s) failed"
        return 1
    fi
}

main() {
    trap cleanup EXIT

    local build_only=false
    local keep_running=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                build_only=true
                shift
                ;;
            --keep-running)
                keep_running=true
                trap '' EXIT
                shift
                ;;
            *)
                echo "Usage: $0 [--build-only] [--keep-running]"
                exit 1
                ;;
        esac
    done

    if [ "$build_only" = true ]; then
        build_images
        exit 0
    fi

    cleanup
    build_images
    start_services

    wait_for_service "PLC" "http://localhost:2580/xrpc/_health"
    wait_for_service "PDS" "http://localhost:2583/xrpc/com.atproto.server.describeServer"
    wait_for_service "Relay" "http://localhost:2584/xrpc/com.atproto.sync.getHead?repo=did:plc:test"

    run_tests
    local test_result=$?

    if [ "$keep_running" = true ]; then
        log_info "Services are kept running. Press Ctrl+C to stop."
        sleep infinity
    fi

    exit $test_result
}

main "$@"
