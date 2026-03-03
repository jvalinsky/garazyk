#!/bin/bash
# deploy.sh — Automated deployment script for ATProto PDS
#
# Usage: ./scripts/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== ATProto PDS Deployment Script ==="
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    local missing=0
    
    if ! command -v docker &>/dev/null; then
        echo "  ✗ docker not found"
        missing=1
    else
        echo "  ✓ docker"
    fi
    
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        echo "  ✗ docker-compose not found"
        missing=1
    else
        echo "  ✓ docker-compose"
    fi
    
    if ! command -v nginx &>/dev/null; then
        echo "  ✗ nginx not found"
        missing=1
    else
        echo "  ✓ nginx"
    fi
    
    if ! command -v certbot &>/dev/null; then
        echo "  ✗ certbot not found"
        missing=1
    else
        echo "  ✓ certbot"
    fi
    
    if ! command -v sqlite3 &>/dev/null; then
        echo "  ✗ sqlite3 not found"
        missing=1
    else
        echo "  ✓ sqlite3"
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo "ERROR: Missing prerequisites. Install with:"
        echo "  sudo apt-get install -y docker.io docker-compose nginx certbot python3-certbot-nginx sqlite3"
        exit 1
    fi
    
    echo ""
}

# Prompt for configuration
configure() {
    echo "Configuration:"
    echo ""
    
    # Check if .env exists
    if [ -f "$PROJECT_DIR/docker/.env" ]; then
        echo "Found existing .env file. Using existing configuration."
        source "$PROJECT_DIR/docker/.env"
    else
        # Prompt for domain
        read -rp "Enter your domain (e.g., pds.example.com): " DOMAIN
        
        # Prompt for email
        read -rp "Enter email for Let's Encrypt: " EMAIL
        
        # Create .env file
        cat > "$PROJECT_DIR/docker/.env" <<EOF
PDS_ISSUER=https://$DOMAIN
PDS_DOMAIN=$DOMAIN
LETSENCRYPT_EMAIL=$EMAIL
TZ=UTC
BACKUP_DIR=/var/backups/atprotopds
BACKUP_RETENTION_DAYS=14
EOF
        
        echo "Created .env file"
        
        # Update config.json
        sed -i "s|pds.example.com|$DOMAIN|g" "$PROJECT_DIR/docker/config.json"
        sed -i "s|example.com|${DOMAIN#pds.}|g" "$PROJECT_DIR/docker/config.json"
        
        echo "Updated config.json"
    fi
    
    echo ""
}

# Build Docker image
build_image() {
    echo "Building Docker image..."
    echo "This may take 15-30 minutes on first build."
    echo ""
    
    cd "$PROJECT_DIR/../../.."
    
    if ! docker build -f docker/Dockerfile.gnustep -t nspds:local .; then
        echo "ERROR: Docker build failed"
        exit 1
    fi
    
    echo ""
    echo "✓ Docker image built successfully"
    echo ""
}

# Create Docker volume
create_volume() {
    echo "Creating Docker volume..."
    
    if docker volume inspect pds_pds_data &>/dev/null; then
        echo "Volume pds_pds_data already exists"
    else
        docker volume create pds_pds_data
        echo "✓ Created volume pds_pds_data"
    fi
    
    echo ""
}

# Set up nginx
setup_nginx() {
    echo "Setting up nginx..."
    
    source "$PROJECT_DIR/docker/.env"
    
    # Copy nginx config
    sudo cp "$PROJECT_DIR/nginx/pds.conf" /etc/nginx/sites-available/pds
    sudo cp "$PROJECT_DIR/nginx/proxy_params_pds" /etc/nginx/proxy_params_pds
    
    # Update domain in config
    sudo sed -i "s|pds.example.com|$PDS_DOMAIN|g" /etc/nginx/sites-available/pds
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/pds /etc/nginx/sites-enabled/pds
    
    # Test config
    if ! sudo nginx -t; then
        echo "ERROR: nginx configuration test failed"
        exit 1
    fi
    
    echo "✓ nginx configured"
    echo ""
}

# Obtain TLS certificate
setup_tls() {
    echo "Setting up TLS certificate..."
    
    source "$PROJECT_DIR/docker/.env"
    
    # Check if certificate already exists
    if [ -f "/etc/letsencrypt/live/$PDS_DOMAIN/fullchain.pem" ]; then
        echo "Certificate already exists for $PDS_DOMAIN"
    else
        echo "Requesting certificate from Let's Encrypt..."
        sudo certbot certonly --nginx -d "$PDS_DOMAIN" --email "$LETSENCRYPT_EMAIL" --agree-tos --non-interactive
        
        if [ $? -eq 0 ]; then
            echo "✓ Certificate obtained"
        else
            echo "ERROR: Failed to obtain certificate"
            echo "Make sure DNS is configured correctly for $PDS_DOMAIN"
            exit 1
        fi
    fi
    
    # Reload nginx with TLS
    sudo systemctl reload nginx
    
    echo ""
}

# Start PDS
start_pds() {
    echo "Starting PDS..."
    
    cd "$PROJECT_DIR/docker"
    
    docker compose up -d
    
    echo "✓ PDS started"
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
            echo "WARNING: PDS health check timed out"
            echo "Check logs with: docker compose logs pds"
        fi
        
        sleep 2
    done
    
    echo ""
}

# Verify deployment
verify() {
    echo "Verifying deployment..."
    
    source "$PROJECT_DIR/docker/.env"
    
    # Test local endpoint
    if curl -sf http://localhost:2583/xrpc/com.atproto.server.describeServer >/dev/null; then
        echo "  ✓ Local endpoint responding"
    else
        echo "  ✗ Local endpoint not responding"
    fi
    
    # Test external endpoint
    if curl -sf "https://$PDS_DOMAIN/xrpc/com.atproto.server.describeServer" >/dev/null; then
        echo "  ✓ External endpoint responding"
    else
        echo "  ✗ External endpoint not responding"
    fi
    
    echo ""
}

# Print next steps
next_steps() {
    source "$PROJECT_DIR/docker/.env"
    
    echo "=== Deployment Complete ==="
    echo ""
    echo "Your PDS is running at: https://$PDS_DOMAIN"
    echo ""
    echo "Next steps:"
    echo "  1. Create an invite code:"
    echo "     docker exec nspds kaszlak invite create"
    echo ""
    echo "  2. Create an account:"
    echo "     curl -X POST https://$PDS_DOMAIN/xrpc/com.atproto.server.createAccount \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"email\":\"you@example.com\",\"handle\":\"you.$PDS_DOMAIN\",\"password\":\"...\",\"inviteCode\":\"...\"}'"
    echo ""
    echo "  3. Set up automated backups:"
    echo "     crontab -e"
    echo "     # Add: 0 3 * * * $PROJECT_DIR/scripts/backup.sh"
    echo ""
    echo "  4. Monitor logs:"
    echo "     docker compose -f $PROJECT_DIR/docker/docker-compose.yml logs -f pds"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    configure
    build_image
    create_volume
    setup_nginx
    setup_tls
    start_pds
    verify
    next_steps
}

main "$@"
