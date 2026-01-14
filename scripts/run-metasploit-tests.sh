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
if ! command -v msfconsole &> /dev/null; then
    echo -e "${RED}Error: msfconsole not found. Please install Metasploit Framework.${NC}"
    exit 1
fi

if ! pgrep -f "atprotopds-cli serve" > /dev/null; then
    echo -e "${RED}Error: PDS Server not running.${NC}"
    echo "Please start it with: ./build/bin/atprotopds-cli serve --foreground &"
    exit 1
fi

# 2. Setup Environment (Symlinks)
echo "Setting up Metasploit environment..."
mkdir -p "$MSF_DIR/auxiliary/scanner/atproto"
mkdir -p "$MSF_DIR/auxiliary/dos/atproto"
mkdir -p "$MSF_DIR/auxiliary/admin/atproto"

# Link modules if not present or updated
ln -sf "$MODULES_DIR/atproto_pds_scanner.rb" "$MSF_DIR/auxiliary/scanner/atproto/"
ln -sf "$MODULES_DIR/atproto_cbor_dos.rb" "$MSF_DIR/auxiliary/dos/atproto/"
ln -sf "$MODULES_DIR/atproto_jwt_bypass.rb" "$MSF_DIR/auxiliary/admin/atproto/"

echo -e "${GREEN}✓ Modules linked${NC}"

# 3. Run Test Suite
echo "Running automated security suite against localhost:$PDS_PORT..."
echo "---------------------------------------------------"

# We use -x to execute commands on startup: set the port globally, then run the resource script
# -q: Quiet mode (suppress banner)
msfconsole -q -x "setg RPORT $PDS_PORT; resource $RC_SCRIPT; exit"

echo "---------------------------------------------------"
echo -e "${GREEN}>>> Test Suite Completed <<<${NC}"
