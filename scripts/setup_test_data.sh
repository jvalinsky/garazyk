#!/bin/bash

# Setup script for ATProto PDS
# Creates test accounts and sample posts for the explore interface

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up ATProto PDS with test data...${NC}"

# CLI path using CMake build location
CLI_PATH="./build/bin/kaszlak"

# Check if CLI exists
if [ ! -f "$CLI_PATH" ]; then
    echo -e "${RED}❌ CLI not found at $CLI_PATH${NC}"
    echo -e "${YELLOW}Please build the project first${NC}"
    exit 1
fi

echo -e "${YELLOW}Creating test accounts...${NC}"

# Create test accounts
accounts=(
    "alice@example.com:alice:password123"
    "bob@example.com:bob:password123"
    "carol@example.com:carol:password123"
    "dave@example.com:dave:password123"
    "eve@example.com:eve:password123"
)

for account in "${accounts[@]}"; do
    IFS=':' read -r email handle password <<< "$account"
    echo -e "${YELLOW}Creating account: $handle ($email)${NC}"

    if $CLI_PATH account create --email "$email" --handle "$handle" --password "$password" --verbose; then
        echo -e "${GREEN}✅ Created account: $handle${NC}"
    else
        echo -e "${RED}❌ Failed to create account: $handle${NC}"
    fi
done

echo -e "${YELLOW}Creating sample posts...${NC}"

# Get account DIDs for posting
echo -e "${YELLOW}Getting account information...${NC}"
account_info=$($CLI_PATH account list)
echo "$account_info"

# For now, skip post creation since we need to implement record creation
echo -e "${YELLOW}Note: Post creation not yet implemented in this setup script${NC}"
did_array=()

echo -e "${YELLOW}Found ${#did_array[@]} accounts${NC}"

# Sample posts to create
posts=(
    "Hello world! This is my first post on ATProto. 🌍 #introduction"
    "Just setting up my PDS server. Excited to be part of the decentralized social web! 🚀"
    "The weather is beautiful today. Perfect day for some coding and testing. ☀️"
    "Working on some cool new features for the ATProto ecosystem. Stay tuned! ⚡"
    "Had a great time exploring the decentralized web today. So many possibilities! 🌐"
    "Testing post creation and threading capabilities. How does this look? 📝"
    "Another day, another commit. Open source development is so rewarding! 💻"
    "Just discovered some amazing decentralized technologies. The future is bright! ✨"
    "Coffee and code - the perfect combination for a productive morning. ☕👨‍💻"
    "Experimenting with new UI designs for the explore interface. What do you think? 🎨"
)

echo -e "${GREEN}🎉 Setup complete!${NC}"
echo -e "${BLUE}You can now run the server with:${NC}"
echo -e "${YELLOW}  $CLI_PATH serve --port 2583 --verbose${NC}"
echo -e "${BLUE}And visit:${NC}"
echo -e "${YELLOW}  http://localhost:2583/explore${NC}"
echo -e "${BLUE}Accounts created: ${#accounts[@]}${NC}"
echo -e "${BLUE}Note: Click 'Accounts' in the explore interface to see the account table${NC}"