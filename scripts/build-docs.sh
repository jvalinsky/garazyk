#!/bin/bash
# Build documentation site using Jekyll or Python fallback

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$REPO_ROOT/docs"
BUILD_DIR="$REPO_ROOT/docs/_site"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building PDS Objective-C Implementation Guide...${NC}"

# Try Jekyll first
if command -v jekyll &> /dev/null; then
    echo -e "${YELLOW}Using Jekyll to build documentation...${NC}"
    
    # Change to docs directory
    cd "$DOCS_DIR"
    
    # Install dependencies if Gemfile exists
    if [ -f "Gemfile" ]; then
        echo -e "${YELLOW}Installing Ruby dependencies...${NC}"
        bundle install
    fi
    
    # Build the site
    echo -e "${YELLOW}Building documentation site...${NC}"
    jekyll build
    
    # Check if build was successful
    if [ -d "$BUILD_DIR" ]; then
        echo -e "${GREEN}Documentation built successfully with Jekyll!${NC}"
        echo -e "${GREEN}Output directory: $BUILD_DIR${NC}"
        echo ""
        echo "To serve locally, run:"
        echo "  cd $DOCS_DIR"
        echo "  jekyll serve"
        exit 0
    else
        echo -e "${RED}Jekyll build failed${NC}"
        exit 1
    fi
else
    # Fallback to Python builder
    echo -e "${YELLOW}Jekyll not found, using Python builder...${NC}"
    
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: Neither Jekyll nor Python 3 is installed${NC}"
        exit 1
    fi
    
    # Check if markdown module is available
    if ! python3 -c "import markdown" 2>/dev/null; then
        echo -e "${YELLOW}Installing Python markdown module...${NC}"
        pip3 install markdown
    fi
    
    # Run Python builder
    echo -e "${YELLOW}Building documentation site with Python...${NC}"
    python3 "$SCRIPT_DIR/build-docs-python.py"
    
    # Check if build was successful
    if [ -d "$BUILD_DIR" ]; then
        echo -e "${GREEN}Documentation built successfully with Python!${NC}"
        echo -e "${GREEN}Output directory: $BUILD_DIR${NC}"
        exit 0
    else
        echo -e "${RED}Documentation build failed${NC}"
        exit 1
    fi
fi
