#!/bin/bash
set -e

echo "=== Setting up garazyk configuration ==="

# Create .letta directory
mkdir -p /home/exedev/.letta

# Copy configuration files
cat > /home/exedev/.letta/garazyk.json << 'EOF'
{
  "database": {
    "service_pool_max_size": 20,
    "user_pool_max_size": 200
  },
  "logging": {
    "format": "text",
    "level": "info"
  },
  "session": {
    "access_token_ttl_seconds": 1800,
    "refresh_token_ttl_seconds": 259200,
    "invite_code_required": false
  },
  "server": {
    "data_dir": "./data",
    "host": "garazyk.xyz",
    "port": 2583
  },
  "links": {
    "privacy_policy": "",
    "terms_of_service": ""
  },
  "relays": [
    "https://bsky.network"
  ]
}
EOF

cat > /home/exedev/.letta/pds.garazyk.json << 'EOF'
{
  "url": "mock",
  "retry_count": 5,
  "retry_delay_ms": 2000
}
EOF

echo "Configuration files created!"
echo ""
echo "Next steps:"
echo "1. Build Docker image on VM:"
echo "   docker compose build pds"
echo ""
echo "2. Start services:"
echo "   docker compose up -d"
echo ""
echo "3. Set up demo account:"
echo "   docker exec -it nspds /usr/local/bin/kaszlak account create --handle demo.bsky.local"
echo "   docker exec -it nspds /usr/local/bin/kaszlak account update --handle demo.bsky.local --invites true"
echo ""
echo "4. Verify deployment:"
echo "   curl http://localhost:2583/explore/api/accounts"
