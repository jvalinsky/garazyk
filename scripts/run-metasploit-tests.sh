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

if ! pgrep -f "atprotopds-cli serve" > /dev/null; then
    echo -e "${RED}Error: PDS Server not running.${NC}"
    echo "Please start it with: ./build/bin/atprotopds-cli serve --foreground &"
    exit 1
fi

# 2. Setup Environment (Symlinks)
echo "Setting up Metasploit environment..."

if [ "$HAS_MSF" -eq 1 ]; then
    # Local setup
    mkdir -p "$MSF_DIR/auxiliary/scanner/atproto"
    mkdir -p "$MSF_DIR/auxiliary/dos/atproto"
    mkdir -p "$MSF_DIR/auxiliary/admin/atproto"

    # Link modules if not present or updated
    ln -sf "$MODULES_DIR/auxiliary/scanner/atproto/atproto_pds_scanner.rb" "$MSF_DIR/auxiliary/scanner/atproto/"
    ln -sf "$MODULES_DIR/auxiliary/dos/atproto/atproto_cbor_dos.rb" "$MSF_DIR/auxiliary/dos/atproto/"
    ln -sf "$MODULES_DIR/auxiliary/admin/atproto/atproto_jwt_bypass.rb" "$MSF_DIR/auxiliary/admin/atproto/"
    
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
else
    # Docker Run
    # We map the project directory to /modules and run the script inside
    # We set RHOSTS to host.docker.internal to access the host machine
    docker run --rm \
        -v "$MODULES_DIR:/modules" \
        -v "$HOME/.msf4:/root/.msf4" \
        metasploitframework/metasploit-framework \
        ./msfconsole -q -x "loadpath /modules; setg RHOSTS host.docker.internal; setg RPORT $PDS_PORT; resource /modules/run_pds_suite.rc; exit"
fi

echo "---------------------------------------------------"
echo -e "${GREEN}>>> Test Suite Completed <<<${NC}"
