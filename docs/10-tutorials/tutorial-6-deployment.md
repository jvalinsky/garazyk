# Tutorial 6: Production Deployment

## Overview

This tutorial guides you through deploying an ATProto PDS to production using Docker, covering configuration, security, monitoring, and maintenance. We'll deploy a production-ready instance with proper security defaults, automated backups, and reverse proxy integration.

**What you'll learn:**
- Docker-based production deployment
- Security configuration and hardening
- Reverse proxy setup (nginx)
- Automated backup strategies
- Monitoring and maintenance
- Troubleshooting production issues

**Prerequisites:**
- Completed Tutorials 1-5 (understanding of PDS architecture)
- Linux server with Docker installed
- Domain name with DNS configured
- Basic understanding of nginx and TLS certificates

**Time to complete:** 60-90 minutes

---

## Architecture Overview

Production deployment architecture:

```
Internet
    │
    ▼
[TLS Termination]
    │ (nginx on port 443)
    ▼
[Reverse Proxy]
    │ (nginx forwards to localhost:2583)
    ▼
[Docker Container]
    │ (PDS running on port 2583)
    ▼
[Persistent Volume]
    │ (SQLite databases, blobs, config)
```

**Key components:**
- **nginx**: TLS termination, rate limiting, proxy headers
- **Docker**: Containerized PDS with GNUstep runtime
- **Volume**: Persistent storage for databases and blobs
- **Config**: Read-only mounted configuration file

---

## Step 1: Prepare the Server

### 1.1 System Requirements

**Minimum specifications:**
- 2 CPU cores
- 4 GB RAM
- 50 GB SSD storage
- Ubuntu 22.04 LTS or similar

**Install dependencies:**

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install nginx
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Install SQLite tools (for backups)
sudo apt-get install -y sqlite3

# Log out and back in for Docker group to take effect
```

### 1.2 Create Directory Structure

```bash
# Create deployment directory
sudo mkdir -p /opt/atprotopds
cd /opt/atprotopds

# Create subdirectories
sudo mkdir -p docker/pds
sudo mkdir -p backups
sudo mkdir -p logs

# Set ownership
sudo chown -R $USER:$USER /opt/atprotopds
```

---

## Step 2: Build the Docker Image

### 2.1 Clone the Repository

```bash
cd /opt/atprotopds
git clone https://github.com/yourusername/atprotopds.git src
cd src

# Initialize submodules (required for secp256k1)
git submodule update --init --recursive
```

### 2.2 Build the Image

The multi-stage Dockerfile builds GNUstep runtime and PDS:

```bash
# Build from the GNUstep Dockerfile
docker build -f docker/Dockerfile.gnustep -t nspds:local .

# This takes 15-30 minutes on first build
# Stages:
#   1. Build GNUstep runtime (libobjc2, gnustep-make, gnustep-base)
#   2. Build ATProtoPDS with CMake
#   3. Create minimal runtime image
```

**Verify the build:**

```bash
docker run --rm nspds:local --version
# Expected output: kaszlak version X.Y.Z
```

---

## Step 3: Configure the PDS

### 3.1 Create Production Configuration

Create `docker/pds/config.json` with secure defaults:

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "data_dir": "/var/lib/atprotopds",
    "issuer": "https://pds.yourdomain.com",
    "available_user_domains": [
      "yourdomain.com"
    ]
  },
  "appViewURL": "https://api.bsky.app",
  "appViewDID": "did:web:api.bsky.app",
  "localAppViewEnabled": false,
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
    "refresh_token_ttl_seconds": 2592000,
    "invite_code_required": true
  },
  "links": {
    "privacy_policy": "https://yourdomain.com/privacy",
    "terms_of_service": "https://yourdomain.com/terms"
  },
  "relays": [
    "https://bsky.network"
  ],
  "plc": {
    "url": "https://plc.directory",
    "retry_count": 5,
    "retry_delay_ms": 2000
  },
  "cors": {
    "allowed_origins": [
      "https://bsky.app",
      "https://pds.yourdomain.com"
    ],
    "allowed_methods": [
      "GET",
      "POST",
      "PUT",
      "DELETE",
      "OPTIONS",
      "HEAD"
    ],
    "allowed_headers": [
      "DPoP",
      "Authorization",
      "Content-Type",
      "*"
    ],
    "max_age": 86400
  },
  "rate_limit": {
    "enabled": true,
    "requests_per_minute": 10000,
    "burst_size": 1000,
    "did_limit": 10000,
    "did_window": 60,
    "ip_limit": 10000,
    "ip_window": 60,
    "blob_limit": 1000,
    "blob_window": 3600
  },
  "debug": {
    "skip_plc_operations": false
  }
}
```

**CRITICAL SECURITY DEFAULTS:**

⚠️ **Never change these without explicit approval:**
- `session.invite_code_required`: `true` (prevents open registration)
- `plc.url`: `"https://plc.directory"` (never `"mock"` in production)
- All `debug.*` flags: `false`
- `rate_limit.enabled`: `true`
- `server.issuer`: Must match your domain

### 3.2 Create Docker Compose File

Create `docker/pds/docker-compose.yml`:

```yaml
services:
  pds:
    image: nspds:local
    container_name: nspds
    ports:
      - "127.0.0.1:2583:2583"  # Bind to localhost only
    volumes:
      - pds_data:/var/lib/atprotopds
      - ./config.json:/var/lib/atprotopds/config.json:ro
    environment:
      - TZ=UTC
      - PDS_PORT=2583
      - PDS_HOST=0.0.0.0
      - PDS_ISSUER=https://pds.yourdomain.com
      - PDS_LEXICON_PATH=/usr/share/atprotopds/lexicons
      - HOME=/var/lib/atprotopds
      - PDS_DATA_DIR=/var/lib/atprotopds
      - PDS_TRUST_PROXY_HEADERS=1  # Trust X-Forwarded-For from nginx
    command: ["serve", "--config", "/var/lib/atprotopds/config.json", "--foreground"]
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  pds_data:
    name: pds_pds_data
```

**Key configuration notes:**
- Port binding to `127.0.0.1` prevents direct external access
- `PDS_TRUST_PROXY_HEADERS=1` enables rate limiting by client IP
- Read-only config mount prevents accidental modification
- Log rotation prevents disk space issues

---

## Step 4: Set Up Reverse Proxy

### 4.1 Obtain TLS Certificate

```bash
# Request Let's Encrypt certificate
sudo certbot certonly --nginx -d pds.yourdomain.com

# Certificate will be saved to:
# /etc/letsencrypt/live/pds.yourdomain.com/fullchain.pem
# /etc/letsencrypt/live/pds.yourdomain.com/privkey.pem
```

### 4.2 Configure nginx

Create `/etc/nginx/sites-available/pds`:

```nginx
# Rate limiting zones
limit_req_zone $binary_remote_addr zone=pds_general:10m rate=100r/s;
limit_req_zone $binary_remote_addr zone=pds_auth:10m rate=10r/s;

# Upstream PDS
upstream pds_backend {
    server 127.0.0.1:2583 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name pds.yourdomain.com;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name pds.yourdomain.com;

    # TLS configuration
    ssl_certificate /etc/letsencrypt/live/pds.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pds.yourdomain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    access_log /var/log/nginx/pds_access.log;
    error_log /var/log/nginx/pds_error.log;

    # Client limits
    client_max_body_size 50M;  # For blob uploads
    client_body_timeout 60s;
    client_header_timeout 60s;

    # Rate limiting (stricter for auth endpoints)
    location ~ ^/xrpc/(com\.atproto\.server\.createSession|com\.atproto\.server\.createAccount) {
        limit_req zone=pds_auth burst=5 nodelay;
        proxy_pass http://pds_backend;
        include /etc/nginx/proxy_params_pds;
    }

    # General endpoints
    location / {
        limit_req zone=pds_general burst=50 nodelay;
        proxy_pass http://pds_backend;
        include /etc/nginx/proxy_params_pds;
    }

    # WebSocket upgrade for firehose
    location /xrpc/com.atproto.sync.subscribeRepos {
        proxy_pass http://pds_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;  # 1 hour for long-lived connections
        proxy_send_timeout 3600s;
    }
}
```

Create `/etc/nginx/proxy_params_pds`:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;

proxy_http_version 1.1;
proxy_set_header Connection "";

proxy_buffering off;
proxy_request_buffering off;

proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;
```

### 4.3 Enable and Test nginx

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/pds /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Enable nginx on boot
sudo systemctl enable nginx
```

---

## Step 5: Start the PDS

### 5.1 Create Docker Volume

```bash
# Create persistent volume
docker volume create pds_pds_data

# Verify
docker volume inspect pds_pds_data
```

### 5.2 Start the Container

```bash
cd /opt/atprotopds/src/docker/pds

# Start in foreground (for initial testing)
docker compose up

# Watch logs for errors
# Expected output:
#   [INFO] Starting ATProto PDS on 0.0.0.0:2583
#   [INFO] Issuer: https://pds.yourdomain.com
#   [INFO] HTTP server listening on port 2583
```

**Verify the server:**

```bash
# Test from localhost
curl http://localhost:2583/xrpc/com.atproto.server.describeServer

# Test from external
curl https://pds.yourdomain.com/xrpc/com.atproto.server.describeServer

# Expected response:
{
  "did": "did:web:pds.yourdomain.com",
  "availableUserDomains": ["yourdomain.com"],
  "inviteCodeRequired": true
}
```

### 5.3 Start in Background

```bash
# Stop foreground process (Ctrl+C)

# Start detached
docker compose up -d

# View logs
docker compose logs -f pds

# Check status
docker compose ps
```

---

## Step 6: Create First Account

### 6.1 Generate Invite Code

```bash
# Generate invite code
docker exec nspds kaszlak invite create

# Output: inv-abc123xyz456
```

### 6.2 Create Account via API

```bash
curl -X POST https://pds.yourdomain.com/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@yourdomain.com",
    "handle": "admin.yourdomain.com",
    "password": "secure-password-here",
    "inviteCode": "inv-abc123xyz456"
  }'

# Response includes DID and access tokens
```

### 6.3 Verify Account

```bash
# Create session
curl -X POST https://pds.yourdomain.com/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "admin.yourdomain.com",
    "password": "secure-password-here"
  }'

# Save the accessJwt from response for authenticated requests
```

---

## Step 7: Set Up Automated Backups

### 7.1 Install Backup Script

The repository includes a production-ready backup script:

```bash
# Copy backup script
sudo cp /opt/atprotopds/src/scripts/backup_pds.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/backup_pds.sh

# Create backup directory
sudo mkdir -p /var/backups/atprotopds
sudo chown $USER:$USER /var/backups/atprotopds
```

### 7.2 Test Manual Backup

```bash
# Run manual backup
/usr/local/bin/backup_pds.sh \
  --data-dir /var/lib/docker/volumes/pds_pds_data/_data \
  --backup-dir /var/backups/atprotopds \
  --retention 14

# Output:
#   === ATProto PDS Backup ===
#   Timestamp:     20260303_120000
#   Data dir:      /var/lib/docker/volumes/pds_pds_data/_data
#   Backup dest:   /var/backups/atprotopds/20260303_120000
#   
#   Service databases:
#     Backing up service/service.db... OK (2.3M)
#   
#   User databases:
#     Backing up user/abc123... OK (1.1M)
#   
#   Compressing backup... OK (1.8M)
#   
#   === Backup Complete ===
#   Archive: /var/backups/atprotopds/pds-backup-20260303_120000.tar.gz
#   Status: All databases backed up successfully (2 DBs)
```

### 7.3 Schedule Automated Backups

```bash
# Edit crontab
crontab -e

# Add daily backup at 3 AM
0 3 * * * /usr/local/bin/backup_pds.sh \
  --data-dir /var/lib/docker/volumes/pds_pds_data/_data \
  --backup-dir /var/backups/atprotopds \
  --retention 14 \
  >> /var/log/atprotopds/backup.log 2>&1
```

### 7.4 Restore from Backup

```bash
# Stop the PDS
cd /opt/atprotopds/src/docker/pds
docker compose down

# Extract backup
cd /var/backups/atprotopds
tar -xzf pds-backup-20260303_120000.tar.gz

# Restore to volume
sudo rsync -av 20260303_120000/ /var/lib/docker/volumes/pds_pds_data/_data/

# Restart PDS
cd /opt/atprotopds/src/docker/pds
docker compose up -d
```

---

## Step 8: Monitoring and Maintenance

### 8.1 View Logs

```bash
# Real-time logs
docker compose logs -f pds

# Last 100 lines
docker compose logs --tail=100 pds

# nginx logs
sudo tail -f /var/log/nginx/pds_access.log
sudo tail -f /var/log/nginx/pds_error.log
```

### 8.2 Monitor Resource Usage

```bash
# Container stats
docker stats nspds

# Disk usage
docker system df
du -sh /var/lib/docker/volumes/pds_pds_data/_data

# Database sizes
docker exec nspds sh -c 'du -sh /var/lib/atprotopds/data/*'
```

### 8.3 Health Checks

Create a monitoring script `/usr/local/bin/check_pds_health.sh`:

```bash
#!/bin/bash
set -euo pipefail

ENDPOINT="https://pds.yourdomain.com/xrpc/com.atproto.server.describeServer"
TIMEOUT=10

if ! response=$(curl -sf --max-time "$TIMEOUT" "$ENDPOINT"); then
    echo "ERROR: PDS health check failed"
    exit 1
fi

if ! echo "$response" | jq -e '.did' >/dev/null 2>&1; then
    echo "ERROR: Invalid response from PDS"
    exit 1
fi

echo "OK: PDS is healthy"
exit 0
```

Schedule health checks:

```bash
# Add to crontab (every 5 minutes)
*/5 * * * * /usr/local/bin/check_pds_health.sh || \
  echo "PDS health check failed at $(date)" >> /var/log/atprotopds/health.log
```

### 8.4 Update the PDS

```bash
# Pull latest code
cd /opt/atprotopds/src
git pull origin main
git submodule update --init --recursive

# Rebuild image
docker build -f docker/Dockerfile.gnustep -t nspds:local .

# Stop current container
cd docker/pds
docker compose down

# Start with new image
docker compose up -d

# Verify
docker compose logs -f pds
```

---

## Step 9: Security Hardening

### 9.1 Firewall Configuration

```bash
# Install ufw
sudo apt-get install -y ufw

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status
```

### 9.2 Fail2ban for Rate Limiting

```bash
# Install fail2ban
sudo apt-get install -y fail2ban

# Create PDS filter
sudo tee /etc/fail2ban/filter.d/pds.conf <<EOF
[Definition]
failregex = ^.*"remote_addr":"<HOST>".*"status":429.*$
ignoreregex =
EOF

# Create jail
sudo tee /etc/fail2ban/jail.d/pds.conf <<EOF
[pds]
enabled = true
port = http,https
filter = pds
logpath = /var/log/nginx/pds_access.log
maxretry = 10
findtime = 60
bantime = 3600
EOF

# Restart fail2ban
sudo systemctl restart fail2ban
```

### 9.3 Automatic Security Updates

```bash
# Install unattended-upgrades
sudo apt-get install -y unattended-upgrades

# Enable automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## Step 10: Troubleshooting

### Common Issues

#### Issue: Container won't start

```bash
# Check logs
docker compose logs pds

# Common causes:
# 1. Port 2583 already in use
sudo lsof -i :2583

# 2. Config file syntax error
docker run --rm -v $(pwd)/config.json:/config.json nspds:local \
  sh -c 'cat /config.json | jq .'

# 3. Volume permissions
docker exec nspds ls -la /var/lib/atprotopds
```

#### Issue: 502 Bad Gateway from nginx

```bash
# Verify PDS is running
docker compose ps

# Test direct connection
curl http://localhost:2583/xrpc/com.atproto.server.describeServer

# Check nginx error log
sudo tail -f /var/log/nginx/pds_error.log

# Verify proxy headers
docker compose logs pds | grep "X-Forwarded-For"
```

#### Issue: Rate limiting not working

```bash
# Verify PDS_TRUST_PROXY_HEADERS is set
docker exec nspds env | grep TRUST_PROXY

# Check nginx is sending headers
curl -H "X-Forwarded-For: 1.2.3.4" http://localhost:2583/xrpc/com.atproto.server.describeServer

# Verify rate limit config
docker exec nspds cat /var/lib/atprotopds/config.json | jq '.rate_limit'
```

#### Issue: Database corruption

```bash
# Check database integrity
docker exec nspds sqlite3 /var/lib/atprotopds/data/service/service.db "PRAGMA integrity_check;"

# If corrupted, restore from backup
cd /opt/atprotopds/src/docker/pds
docker compose down
# ... restore from backup (see Step 7.4)
docker compose up -d
```

---

## Production Checklist

Before going live, verify:

- [ ] TLS certificate is valid and auto-renewing
- [ ] `invite_code_required` is `true`
- [ ] `plc.url` is `"https://plc.directory"` (not `"mock"`)
- [ ] All `debug.*` flags are `false`
- [ ] Rate limiting is enabled and tested
- [ ] Firewall rules are configured
- [ ] Automated backups are scheduled and tested
- [ ] Health checks are running
- [ ] Monitoring is in place
- [ ] Privacy policy and ToS links are valid
- [ ] nginx security headers are present
- [ ] Log rotation is configured
- [ ] Disk space monitoring is set up

---

## Next Steps

**Congratulations!** You've deployed a production ATProto PDS.

**Further reading:**
- [Configuration Reference](../11-reference/config-reference) — All config options
- [Troubleshooting Guide](../11-reference/troubleshooting) — Common issues
- [API Reference](../11-reference/api-reference) — XRPC endpoints

**Production considerations:**
- Set up external monitoring (UptimeRobot, Pingdom)
- Configure log aggregation (ELK, Loki)
- Implement metrics collection (Prometheus)
- Plan for horizontal scaling (multiple PDS instances)
- Document incident response procedures

**Community:**
- Join the ATProto Discord
- Report issues on GitHub
- Contribute improvements back to the project
