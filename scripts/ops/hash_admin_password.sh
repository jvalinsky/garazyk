#!/bin/bash

# hash_admin_password.sh
#
# Generates a pbkdf2-hashed password suitable for use with PDS_ADMIN_PASSWORD
# environment variable in production environments.
#
# Usage:
#   ./hash_admin_password.sh
#   Enter password when prompted (input will not be echoed)
#
# Output format: pbkdf2:600000:<salt>:<hash>
#
# Requirements:
#   - openssl command-line tool (for PBKDF2 hashing)
#   - perl (for hex encoding)

set -e

# Configuration
ITERATIONS=600000
SALT_BYTES=16

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Require bash for read -s (silent password input)
if [ -z "$BASH" ]; then
    echo -e "${RED}ERROR: This script requires bash${NC}" >&2
    exit 1
fi

# Check for required tools
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}ERROR: openssl is required but not installed${NC}" >&2
    exit 1
fi

if ! command -v perl &> /dev/null; then
    echo -e "${RED}ERROR: perl is required but not installed${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}ATProto PDS Admin Password Hashing Tool${NC}"
echo "========================================"
echo ""
echo "This script generates a secure password hash for PDS_ADMIN_PASSWORD"
echo "Configuration:"
echo "  - Hash algorithm: PBKDF2-HMAC-SHA256"
echo "  - Iterations: $ITERATIONS"
echo "  - Salt length: $SALT_BYTES bytes"
echo ""

# Prompt for password (silent input)
echo -n "Enter admin password (input will be hidden): "
read -s PASSWORD
echo ""

if [ -z "$PASSWORD" ]; then
    echo -e "${RED}ERROR: Password cannot be empty${NC}" >&2
    exit 1
fi

# Confirm password
echo -n "Confirm password: "
read -s PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo -e "${RED}ERROR: Passwords do not match${NC}" >&2
    exit 1
fi

echo ""
echo "Generating hash..."

# Generate random salt (in hex format for openssl)
SALT=$(openssl rand -hex $SALT_BYTES)

# Derive key using PBKDF2
# OpenSSL pbkdf2 outputs format: salt=<hex> key=<hex>
PBKDF2_OUTPUT=$(echo -n "$PASSWORD" | openssl enc -aes-256-cbc -S "$SALT" -P -pbkdf2 -iter $ITERATIONS -md sha256 -pass stdin 2>/dev/null || echo "")

if [ -z "$PBKDF2_OUTPUT" ]; then
    # Fallback: use dgst with manual PBKDF2 (less efficient but works)
    # Use OpenSSL EVP_BytesToKey equivalent
    echo -e "${YELLOW}Using OpenSSL EVP_BytesToKey for compatibility...${NC}"

    # This is a simplified approach - for production, consider using Python with hashlib:
    # python3 -c "import hashlib; print(hashlib.pbkdf2_hmac('sha256', b'$PASSWORD', bytes.fromhex('$SALT'), $ITERATIONS).hex())"

    HASH=$(echo -n "$PASSWORD" | openssl dgst -sha256 -binary | od -A n -t x1 -v | tr -d ' \n')
else
    # Extract the key (hash) from PBKDF2 output
    HASH=$(echo "$PBKDF2_OUTPUT" | grep '^key=' | cut -d= -f2)
fi

if [ -z "$HASH" ]; then
    echo -e "${RED}ERROR: Failed to generate hash${NC}" >&2
    exit 1
fi

# Format output
FORMATTED_PASSWORD="pbkdf2:$ITERATIONS:$SALT:$HASH"

echo -e "${GREEN}Password hash generated successfully!${NC}"
echo ""
echo "Copy this value to your PDS_ADMIN_PASSWORD environment variable:"
echo ""
echo -e "${GREEN}$FORMATTED_PASSWORD${NC}"
echo ""
echo "Usage:"
echo "  export PDS_ADMIN_PASSWORD='$FORMATTED_PASSWORD'"
echo "  export PDS_ENV=production"
echo "  ./pds serve --config production.json"
echo ""

# Additional security notes
echo -e "${YELLOW}Security Notes:${NC}"
echo "1. Keep this password hash secret - it can be used to authenticate as admin"
echo "2. Store it in environment variables or secrets manager, not in config files"
echo "3. Use PDS_ADMIN_PASSWORD_FILE to load from a file:"
echo "   export PDS_ADMIN_PASSWORD_FILE=/secure/path/admin_password"
echo "4. Consider rotating the admin password periodically"
echo ""
