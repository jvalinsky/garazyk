#!/bin/bash
# update.sh — Update script for ATProto PDS
#
# Usage: ./scripts/update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$PROJECT_DIR/../../.."

echo "=== ATProto PDS Update Script ==="
echo ""

# Backup before update
backup_before_update() {
    echo "Creating backup before update..."
    
    if [ -f "$SCRIPT_DIR/backup.sh" ]; then
        "$SCRIPT_DIR/backup.sh"
        echo "✓ Backup complete"
    else
        echo "⚠ Backup script not found, skipping backup"
    fi
    
    echo ""
}

# Pull latest code
pull_code() {
    echo "Pulling latest code..."
    
    cd "$REPO_DIR"
    
    # Stash local changes
    if ! git diff-index --quiet HEAD --; then
        echo "Stashing local changes..."
        git stash
    fi
    
    # Pull
    git pull origin main
    
    # Update submodules
    git submodule update --init --recursive
    
    echo "✓ Code updated"
    echo ""
}

# Rebuild image
rebuild_image() {
    echo "Rebuilding Docker image..."
    echo "This may take 15-30 minutes."
    echo ""
    
    cd "$REPO_DIR"
    
    if ! docker build -f docker/Dockerfile.gnustep -t nspds:local .; then
        echo "ERROR: Docker build failed"
        exit 1
    fi
    
    echo ""
    echo "✓ Image rebuilt"
    echo ""
}

# Restart container
restart_container() {
    echo "Restarting PDS..."
    
    cd "$PROJECT_DIR/docker"
    
    # Stop
    docker compose down
    
    # Start with new image
    docker compose up -d
    
    echo "✓ PDS restarted"
    echo ""
    
    # Wait for health check
    echo "Waiting for PDS to be ready..."
    sleep 5
    
    for i in {1..30}; do
        if curl -sf http://localhost:2583/xrpc/com.atproto.server.describeServer >/dev/null 2>&1; then
            echo "✓ PDS is ready"
            break
        fi
        
        if [ $i -eq 30 ]; then
            echo "ERROR: PDS health check timed out"
            echo "Check logs with: docker compose logs pds"
            exit 1
        fi
        
        sleep 2
    done
    
    echo ""
}

# Verify update
verify_update() {
    echo "Verifying update..."
    
    # Get version
    VERSION=$(docker exec nspds kaszlak --version 2>&1 || echo "unknown")
    echo "  Version: $VERSION"
    
    # Test endpoint
    if curl -sf http://localhost:2583/xrpc/com.atproto.server.describeServer >/dev/null; then
        echo "  ✓ Endpoint responding"
    else
        echo "  ✗ Endpoint not responding"
        exit 1
    fi
    
    echo ""
}

# Main execution
main() {
    backup_before_update
    pull_code
    rebuild_image
    restart_container
    verify_update
    
    echo "=== Update Complete ==="
    echo ""
    echo "Monitor logs with:"
    echo "  docker compose -f $PROJECT_DIR/docker/docker-compose.yml logs -f pds"
    echo ""
}

main "$@"
