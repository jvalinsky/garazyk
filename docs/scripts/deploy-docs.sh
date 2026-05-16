#!/bin/bash
# Deploy VitePress documentation to production

set -e

# Configuration
DEPLOY_ENV="${1:-production}"
DOCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$DOCS_DIR/.vitepress/dist"
DOCKER_DIR="$(cd "$DOCS_DIR/../docker/docs" && pwd)"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== VitePress Documentation Deployment ==="
echo "Environment: $DEPLOY_ENV"
echo "Docs directory: $DOCS_DIR"
echo ""

# Step 1: Validate environment
echo -e "${YELLOW}Step 1: Validating environment...${NC}"
if [ ! -f "$DOCS_DIR/package.json" ]; then
    echo -e "${RED}Error: package.json not found in $DOCS_DIR${NC}"
    exit 1
fi

if [ ! -f "$DOCS_DIR/.vitepress/config.ts" ]; then
    echo -e "${RED}Error: VitePress config not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Environment validated${NC}"
echo ""

# Step 2: Run validation checks
echo -e "${YELLOW}Step 2: Running validation checks...${NC}"
cd "$DOCS_DIR"

if [ -f "scripts/validate-docs.ts" ]; then
    echo "Running documentation validation..."
    npm run validate:all || {
        echo -e "${RED}✗ Validation failed${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Validation passed${NC}"
else
    echo -e "${YELLOW}⚠ Validation script not found, skipping${NC}"
fi
echo ""

# Step 3: Build documentation
echo -e "${YELLOW}Step 3: Building VitePress documentation...${NC}"
npm run docs:build || {
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
}

if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${RED}Error: Build directory not found at $BUILD_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build completed${NC}"
echo ""

# Step 4: Verify build output
echo -e "${YELLOW}Step 4: Verifying build output...${NC}"
if [ ! -f "$BUILD_DIR/index.html" ]; then
    echo -e "${RED}Error: index.html not found in build output${NC}"
    exit 1
fi

# Count files
FILE_COUNT=$(find "$BUILD_DIR" -type f | wc -l)
echo "Build contains $FILE_COUNT files"
echo -e "${GREEN}✓ Build output verified${NC}"
echo ""

# Step 5: Deploy based on environment
if [ "$DEPLOY_ENV" = "production" ]; then
    echo -e "${YELLOW}Step 5: Deploying to production...${NC}"
    
    # Check if we're on the production server
    if [ -f "$DEPLOY_DIR/objpds/docker/docs/docker-compose.yml" ]; then
        echo "Deploying on production server ($DEPLOY_HOST)"
        
        # Stop existing container
        cd $DEPLOY_DIR/objpds/docker/docs
        docker compose down || true
        
        # Rebuild and start
        docker compose up -d --build
        
        echo -e "${GREEN}✓ Deployed to production${NC}"
    else
        echo -e "${YELLOW}⚠ Not on production server${NC}"
        echo "To deploy to production, run this script on $DEPLOY_HOST"
        echo "Or manually copy $BUILD_DIR to the production server"
    fi
    
elif [ "$DEPLOY_ENV" = "staging" ]; then
    echo -e "${YELLOW}Step 5: Deploying to staging...${NC}"
    
    # Start local Docker container for staging
    cd "$DOCKER_DIR"
    docker compose down || true
    docker compose up -d --build
    
    echo -e "${GREEN}✓ Deployed to staging (http://localhost:8080/docs)${NC}"
    
elif [ "$DEPLOY_ENV" = "preview" ]; then
    echo -e "${YELLOW}Step 5: Starting preview server...${NC}"
    
    cd "$DOCS_DIR"
    npm run docs:preview &
    PREVIEW_PID=$!
    
    echo -e "${GREEN}✓ Preview server started (PID: $PREVIEW_PID)${NC}"
    echo "Preview available at: http://localhost:4173/docs"
    echo "Press Ctrl+C to stop"
    
    wait $PREVIEW_PID
    
else
    echo -e "${RED}Error: Unknown environment '$DEPLOY_ENV'${NC}"
    echo "Usage: $0 [production|staging|preview]"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
