#!/bin/bash
set -e

# Configuration
MSF_DIR="$HOME/.msf4/modules"
PROJECT_ROOT="$(pwd)"
MODULES_DIR="$PROJECT_ROOT/security/metasploit"
RC_SCRIPT="$MODULES_DIR/run_pds_suite.rc"
PDS_PORT=2583

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> AT Protocol PDS Metasploit Test Runner <<<${NC}"

# 1. Verify Prerequisites
HAS_MSF=0
if command -v msfconsole &> /dev/null; then
    HAS_MSF=1
elif command -v docker &> /dev/null; then
    echo "msfconsole not found, falling back to Docker..."
    HAS_MSF=2
else
    echo -e "${RED}Error: Neither msfconsole nor docker found.${NC}"
    exit 1
fi

if ! pgrep -f "kaszlak serve" > /dev/null; then
    echo -e "${RED}Error: PDS Server not running.${NC}"
    echo "Please start it with: ./build/bin/kaszlak serve --foreground &"
    exit 1
fi

# 2. Setup Environment (Symlinks)
echo "Setting up Metasploit environment..."

    # Link all modules in the directories
    for category in scanner dos admin; do
        mkdir -p "$MSF_DIR/auxiliary/$category/atproto"
        ln -sf "$MODULES_DIR/auxiliary/$category/atproto"/*.rb "$MSF_DIR/auxiliary/$category/atproto/"
    done
    
    echo -e "${GREEN}✓ Modules linked to ~/.msf4${NC}"
else
    echo -e "${GREEN}✓ Modules ready for Docker mount${NC}"
fi

# 3. Run Test Suite
echo "Running automated security suite against localhost:$PDS_PORT..."
echo "---------------------------------------------------"

if [ "$HAS_MSF" -eq 1 ]; then
    # Local Run
    msfconsole -q -x "setg RPORT $PDS_PORT; resource $RC_SCRIPT; exit"
elif [ -f /.dockerenv ]; then
    # Inside Docker (e.g., via docker-compose)
    # RHOSTS and RPORT are expected to be set via ENV
    msfconsole -q -x "setg RHOSTS $RHOSTS; setg RPORT $RPORT; resource $RC_SCRIPT; exit"
else
    # One-off Docker Run from Host
    # We map the project directory to /app and run the script inside
    docker run --rm \
        -v "$PROJECT_ROOT:/app" \
        -e RHOSTS=host.docker.internal \
        -e RPORT=$PDS_PORT \
        metasploitframework/metasploit-framework \
        /bin/bash /app/scripts/run-metasploit-tests.sh
fi

echo "---------------------------------------------------"
echo -e "${GREEN}>>> Test Suite Completed <<<${NC}"
