---
title: "Tutorial 6: Production Deployment"
---

# Tutorial 6: Production Deployment

## Overview

In this tutorial, you'll deploy a production-ready ATProto Personal Data Server using Docker, nginx, and industry-standard security practices. This is where everything you've learned in previous tutorials comes together into a real-world deployment that can serve actual users.

Deploying a PDS isn't just about getting the server running—it's about creating a reliable, secure, maintainable system that can operate 24/7. You'll learn how to configure proper security defaults, set up automated backups, implement monitoring, and troubleshoot common production issues.

By the end of this tutorial, you'll have a fully functional PDS accessible over HTTPS, protected by rate limiting and firewalls, with automated backups and health monitoring in place.

### What You'll Build

A production-ready PDS deployment featuring:
- **Docker containerization** for isolation and reproducibility
- **nginx reverse proxy** for TLS termination and rate limiting
- **Let's Encrypt TLS certificates** for secure HTTPS connections
- **Automated backup system** with retention policies
- **Health monitoring** and alerting
- **Security hardening** with firewall rules and fail2ban

This tutorial focuses on real-world production concerns: security, reliability, maintainability, and operational excellence.

**Learning Objectives:**
- Deploy containerized services with Docker Compose
- Configure nginx as a reverse proxy with TLS
- Implement defense-in-depth security practices
- Set up automated backup and restore procedures
- Monitor production systems and respond to issues
- Understand the production deployment architecture

**Estimated Time:** 60-90 minutes

## Prerequisites

Before starting this tutorial, you should have:

- **Completed Tutorials:**
  - Tutorial 1-5 (understanding of PDS architecture, authentication, and firehose)
  - Familiarity with PDS configuration from previous tutorials
  
- **Infrastructure:**
  - Linux server (Ubuntu 22.04 LTS recommended, 2+ CPU cores, 4+ GB RAM, 50+ GB SSD)
  - Root or sudo access to the server
  - Domain name with DNS A record pointing to your server's IP
  - SSH access to the server
  
- **Software Knowledge:**
  - Basic Docker and Docker Compose concepts
  - Understanding of HTTP/HTTPS and reverse proxies
  - Familiarity with nginx configuration syntax
  - Basic Linux system administration (systemd, cron, firewall)
  
- **Optional but Helpful:**
  - Experience with Let's Encrypt and certbot
  - Understanding of SQLite backup strategies
  - Familiarity with systemd services and timers

### Why These Prerequisites Matter

Production deployment requires a broader skill set than development. You need to understand not just how the PDS works, but how to operate it reliably. The infrastructure requirements ensure your server can handle real-world load, while the software knowledge helps you troubleshoot issues when they arise.

**Important:** This tutorial assumes you're deploying to a dedicated server or VPS. Don't deploy to production on your development machine—production systems need isolation, proper networking, and 24/7 availability.

---

## Architecture Overview

Before diving into deployment, let's understand the production architecture. This isn't just about running a server—it's about creating a layered defense system where each component has a specific role.

### Production Architecture Diagram

```objc
Internet (Untrusted)
    │
    ▼
[TLS Termination Layer]
    │ (nginx on port 443)
    │ • Validates TLS certificates
    │ • Terminates HTTPS connections
    │ • Adds security headers
    ▼
[Reverse Proxy Layer]
    │ (nginx forwards to localhost:2583)
    │ • Rate limiting per IP
    │ • Request buffering
    │ • Proxy headers (X-Forwarded-For, etc.)
    ▼
[Application Layer]
    │ (Docker container with PDS)
    │ • Isolated process space
    │ • Resource limits
    │ • Restart policies
    ▼
[Data Layer]
    │ (Docker volume with SQLite databases)
    │ • Persistent storage
    │ • Atomic writes (WAL mode)
    │ • Backup snapshots
```objc

### Why This Architecture?

**Separation of concerns:** Each layer handles specific responsibilities. nginx handles TLS and rate limiting (it's battle-tested for this), while the PDS focuses on AT Protocol logic. Docker provides isolation and reproducibility.

**Defense in depth:** Multiple security layers protect your system. Even if one layer is compromised, others provide protection. Rate limiting at nginx prevents DoS attacks before they reach the PDS. Firewall rules block unauthorized ports. Docker isolation limits the blast radius of any security issue.

**Operational simplicity:** This architecture is well-understood and widely deployed. When something goes wrong, you can find solutions quickly. The components (nginx, Docker, Let's Encrypt) have excellent documentation and community support.

**Scalability path:** While this tutorial deploys a single instance, this architecture scales horizontally. You can add more PDS containers behind a load balancer, separate the database layer, or add caching layers—all without fundamental architectural changes.

### Key Components Explained

**nginx (Reverse Proxy):**
- Handles TLS certificate management and renewal
- Implements rate limiting to prevent abuse
- Adds security headers (HSTS, X-Frame-Options, etc.)
- Buffers requests to protect the backend
- Provides detailed access logs for monitoring

**Docker Container:**
- Isolates the PDS from the host system
- Ensures consistent runtime environment (GNUstep, libraries)
- Enables easy updates (rebuild image, restart container)
- Provides resource limits (CPU, memory)
- Implements automatic restart on failure

**Docker Volume:**
- Persists data across container restarts
- Survives container deletion (your data is safe)
- Enables atomic backups (snapshot the volume)
- Separates data from application code

**Configuration File:**
- Mounted read-only to prevent accidental modification
- Centralized settings management
- Easy to version control and audit
- Can be updated without rebuilding the image

### Production vs Development

In development (Tutorials 1-5), you ran the PDS directly on your machine, often without TLS or rate limiting. That's fine for learning, but production requires:

- **TLS everywhere:** Clients expect HTTPS. AT Protocol clients may refuse to connect over HTTP.
- **Rate limiting:** Without it, a single misbehaving client can overwhelm your server.
- **Monitoring:** You need to know when something breaks, ideally before users notice.
- **Backups:** Hardware fails. Databases corrupt. Backups are your insurance policy.
- **Security hardening:** Default configurations are rarely secure enough for production.

This tutorial implements all of these production requirements.

---

## Step 1: Prepare the Server

Server preparation is about creating a solid foundation. Rushing this step leads to problems later—missing dependencies, permission issues, or security vulnerabilities.

### 1.1 System Requirements

**Minimum specifications:**
- **CPU:** 2 cores (4+ recommended for production load)
- **RAM:** 4 GB (8+ GB recommended, especially with multiple users)
- **Storage:** 50 GB SSD (100+ GB recommended for growth)
- **OS:** Ubuntu 22.04 LTS or similar (Debian 12, Rocky Linux 9)

**Why these specs?**

The PDS is surprisingly lightweight for a single user, but production deployments need headroom:
- **CPU:** Cryptographic operations (JWT signing, DPoP verification) are CPU-intensive. Multiple concurrent users multiply this load.
- **RAM:** Each user's repository is cached in memory for performance. The SQLite connection pool also consumes RAM.
- **Storage:** User repositories grow over time. Blobs (images, videos) consume significant space. You need room for backups too.
- **SSD:** SQLite performance depends heavily on disk I/O. SSDs provide the random access patterns SQLite needs.

**Install dependencies:**

```bash
# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker (official script)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install nginx (reverse proxy)
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Install SQLite tools (for backup verification)
sudo apt-get install -y sqlite3

# Log out and back in for Docker group to take effect
# Or run: newgrp docker
```objc

**Understanding the dependencies:**

- **Docker:** Provides containerization. The official script installs the latest stable version and configures systemd integration.
- **nginx:** Industry-standard reverse proxy. Handles TLS termination and rate limiting better than most application servers.
- **certbot:** Let's Encrypt client for automated TLS certificate management. The nginx plugin integrates seamlessly.
- **sqlite3:** Command-line tools for database inspection and integrity checks during backups.

**Security note:** The Docker installation script adds your user to the `docker` group, which grants root-equivalent privileges. This is necessary for running Docker commands without `sudo`, but be aware of the security implications. Never run untrusted containers.

## 1.2 Create Directory Structure

```bash
# Create deployment directory
sudo mkdir -p /opt/atprotopds
cd /opt/atprotopds

# Create subdirectories
sudo mkdir -p docker/pds    # Docker Compose files and config
sudo mkdir -p backups       # Backup archives
sudo mkdir -p logs          # Application logs (if not using Docker logs)

# Set ownership to your user
sudo chown -R $USER:$USER /opt/atprotopds
```objc

**Why `/opt/atprotopds`?**

The `/opt` directory is the standard location for third-party software on Linux systems. It's separate from system directories (`/usr`, `/etc`), making it clear this is custom software. It also survives system upgrades.

**Directory purposes:**
- `docker/pds/`: Contains `docker-compose.yml` and `config.json`. This is your deployment's "source of truth."
- `backups/`: Stores compressed backup archives. Keep this on a separate disk or sync to remote storage.
- `logs/`: Optional. Docker's logging driver handles most logging, but you might want application-specific logs here.

**Permissions matter:** Setting ownership to your user (not root) follows the principle of least privilege. You don't need root to manage the deployment, only to install system packages and configure nginx.

---

## Step 2: Build the Docker Image

Docker images are like templates for containers—they contain everything needed to run your application. Building the image compiles the PDS and packages it with the GNUstep runtime.

### 2.1 Clone the Repository

```bash
cd /opt/atprotopds
git clone https://github.com/yourusername/atprotopds.git src
cd src

# Initialize submodules (required for secp256k1)
git submodule update --init --recursive
```objc

**Why submodules?**

The PDS depends on `libsecp256k1` for cryptographic operations (specifically, signing AT Protocol operations). Rather than requiring you to install it system-wide, the repository includes it as a Git submodule. The `--recursive` flag ensures nested submodules are also initialized.

**Submodule gotcha:** If you later `git pull` to update the PDS, remember to run `git submodule update` again. Submodules don't automatically update with the parent repository.

## 2.2 Build the Image

The multi-stage Dockerfile builds the GNUstep runtime and PDS in a reproducible environment:

```bash
# Build from the GNUstep Dockerfile
docker build -f docker/Dockerfile.gnustep -t nspds:local .

# This takes 15-30 minutes on first build
# Subsequent builds use Docker's layer cache and complete in 2-5 minutes
```objc

**What happens during the build?**

The Dockerfile has three stages:

1. **Build GNUstep runtime** (10-15 minutes):
   - Compiles `libobjc2` (the Objective-C runtime)
   - Builds `gnustep-make` (build system)
   - Builds `gnustep-base` (Foundation framework)
   
2. **Build ATProtoPDS** (5-10 minutes):
   - Runs CMake to configure the build
   - Compiles all PDS source files
   - Links against GNUstep, SQLite, OpenSSL, secp256k1
   - Copies lexicon files and resources
   
3. **Create runtime image** (1-2 minutes):
   - Starts from a minimal base image
   - Copies only the compiled binaries and runtime libraries
   - Results in a ~200 MB image (vs ~2 GB if we kept build tools)

**Why multi-stage builds?**

The final image doesn't need compilers, headers, or build tools—only the runtime dependencies. Multi-stage builds let us compile in a full development environment, then copy just the artifacts to a minimal runtime image. This reduces image size, attack surface, and deployment time.

**Verify the build:**

```bash
docker run --rm nspds:local --version
# Expected output: kaszlak version X.Y.Z
```objc

This runs the `kaszlak` binary inside a temporary container (`--rm` removes it after exit). If you see the version number, the build succeeded.

**Troubleshooting build failures:**

- **Out of memory:** Docker builds can consume significant RAM. If the build fails with "killed" or "signal 9," increase Docker's memory limit in Docker Desktop settings, or add swap space on Linux.
- **Network timeouts:** The build downloads packages from Ubuntu mirrors. If you see timeout errors, retry the build—Docker will resume from the last successful layer.
- **Submodule errors:** If you see "fatal: not a git repository" errors, ensure you ran `git submodule update --init --recursive`.

---

## Step 3: Configure the PDS

Configuration is where security meets functionality. Every setting in this file has security implications—get it wrong, and you might expose your server to abuse or compromise user data.

### 3.1 Create Production Configuration

Create `docker/pds/config.json` with secure defaults. This configuration follows production best practices and implements defense-in-depth security:

**Why JSON for configuration?**

JSON is human-readable, widely supported, and easy to validate. The PDS validates the configuration on startup, catching errors before they cause runtime issues. You can also version control your config (minus secrets) to track changes over time.

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
```objc

### Understanding the Configuration

Let's break down each section and understand why these values matter:

**Server Configuration:**
```json
"server": {
  "host": "0.0.0.0",           // Listen on all interfaces (Docker networking)
  "port": 2583,                // Standard AT Protocol PDS port
  "data_dir": "/var/lib/atprotopds",  // Persistent data location
  "issuer": "https://pds.yourdomain.com",  // Your PDS's DID
  "available_user_domains": ["yourdomain.com"]  // Allowed handle domains
}
```objc

- **`host: "0.0.0.0"`**: Inside the Docker container, this means "listen on all network interfaces." The container's network is isolated, so this is safe. The Docker Compose port binding (`127.0.0.1:2583:2583`) restricts external access.
- **`issuer`**: This is your PDS's identity in the AT Protocol network. It must match your domain exactly. Clients use this to verify they're talking to the right server.
- **`available_user_domains`**: Users can create handles like `alice.yourdomain.com`. This prevents users from claiming handles on domains you don't control.

**App View Configuration:**
```json
"appViewURL": "https://api.bsky.app",
"appViewDID": "did:web:api.bsky.app",
"localAppViewEnabled": false
```objc

The App View aggregates data from multiple PDSs to provide feeds, search, and discovery. Most PDSs use Bluesky's public App View. Setting `localAppViewEnabled: false` means your PDS won't try to run its own App View (which requires significant resources).

**Database Configuration:**
```json
"database": {
  "service_pool_max_size": 20,    // Connections for shared service DB
  "user_pool_max_size": 200       // Connections for user repositories
}
```objc

SQLite connection pools improve concurrency. The service pool handles authentication and metadata, while the user pool handles repository operations. These limits prevent resource exhaustion under load.

**Session Configuration:**
```json
"session": {
  "access_token_ttl_seconds": 1800,      // 30 minutes
  "refresh_token_ttl_seconds": 2592000,  // 30 days
  "invite_code_required": true           // CRITICAL: Prevents open registration
}
```objc

- **Access tokens** are short-lived (30 minutes) to limit the damage if stolen. Clients must refresh them regularly.
- **Refresh tokens** are long-lived (30 days) so users don't have to log in constantly.
- **`invite_code_required: true`**: **NEVER set this to `false` in production** without explicit approval. Open registration invites spam, abuse, and legal liability.

**PLC Configuration:**
```json
"plc": {
  "url": "https://plc.directory",  // CRITICAL: Use real PLC directory
  "retry_count": 5,
  "retry_delay_ms": 2000
}
```objc

The PLC (Public Ledger of Credentials) directory stores DID documents. **NEVER use `"mock"` in production**—it's only for testing. The real PLC directory is required for interoperability with other AT Protocol services.

**Rate Limiting Configuration:**
```json
"rate_limit": {
  "enabled": true,              // CRITICAL: Must be true in production
  "requests_per_minute": 10000,
  "burst_size": 1000,
  "did_limit": 10000,
  "did_window": 60,
  "ip_limit": 10000,
  "ip_window": 60,
  "blob_limit": 1000,
  "blob_window": 3600
}
```objc

Rate limiting prevents abuse and DoS attacks. These limits are generous for legitimate use but prevent a single client from overwhelming your server. The PDS tracks limits by both DID (authenticated users) and IP (unauthenticated requests).

**Debug Configuration:**
```json
"debug": {
  "skip_plc_operations": false  // CRITICAL: Must be false in production
}
```objc

Debug flags are for development only. **Never enable debug flags in production**—they bypass security checks and can expose sensitive data.

### 3.2 CRITICAL SECURITY DEFAULTS

⚠️ **These settings are MANDATORY for production. Never change them without explicit approval:**

| Setting | Required Value | Why |
|---------|---------------|-----|
| `session.invite_code_required` | `true` | Prevents open registration, spam, and abuse |
| `plc.url` | `"https://plc.directory"` | Required for AT Protocol interoperability |
| `debug.skip_plc_operations` | `false` | Debug mode bypasses critical security checks |
| `rate_limit.enabled` | `true` | Prevents DoS attacks and resource exhaustion |
| `server.issuer` | Your actual domain | Must match your domain for DID verification |

**Why these defaults matter:**

Open registration (`invite_code_required: false`) makes you responsible for all content created on your server. You become a target for spammers, scammers, and bad actors. Unless you're prepared to moderate content 24/7 and handle legal requests, keep registration closed.

Using mock PLC (`plc.url: "mock"`) breaks interoperability. Other AT Protocol services won't be able to resolve your users' DIDs, effectively isolating your server from the network.

Disabling rate limiting (`rate_limit.enabled: false`) is like leaving your front door open. A single misbehaving client can consume all your server's resources, causing downtime for everyone.

### 3.3 Create Docker Compose File

Docker Compose orchestrates your container deployment. This file defines how the container runs, what resources it has access to, and how it restarts on failure.

Create `docker/pds/docker-compose.yml`:

```yaml
services:
  pds:
    image: nspds:local
    container_name: nspds
    ports:
      - "127.0.0.1:2583:2583"  # Bind to localhost only - nginx handles external access
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
      - PDS_TRUST_PROXY_HEADERS=1  # CRITICAL: Trust X-Forwarded-For from nginx
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
```objc

### Understanding Docker Compose Configuration

**Port Binding:**
```yaml
ports:
  - "127.0.0.1:2583:2583"
```objc

This binds the container's port 2583 to `127.0.0.1:2583` on the host—**localhost only**. External traffic cannot reach this port directly; it must go through nginx. This is a critical security layer: even if nginx is misconfigured, the PDS isn't directly exposed to the internet.

**Volume Mounts:**
```yaml
volumes:
  - pds_data:/var/lib/atprotopds                          # Persistent data
  - ./config.json:/var/lib/atprotopds/config.json:ro      # Read-only config
```objc

- **`pds_data` volume**: Docker-managed persistent storage. Survives container deletion, updates, and restarts. This is where your SQLite databases and user blobs live.
- **Config mount with `:ro`**: The `:ro` flag makes the config read-only inside the container. This prevents the PDS from accidentally modifying its own configuration.

**Environment Variables:**
```yaml
environment:
  - PDS_TRUST_PROXY_HEADERS=1  # CRITICAL for rate limiting
```objc

**`PDS_TRUST_PROXY_HEADERS=1`** is essential when running behind a reverse proxy. Without it, the PDS sees all requests coming from `127.0.0.1` (nginx's IP), making IP-based rate limiting useless. With this flag, the PDS trusts the `X-Forwarded-For` header that nginx adds, allowing it to rate limit by actual client IP.

**Restart Policy:**
```yaml
restart: unless-stopped
```objc

The container automatically restarts if it crashes, unless you explicitly stop it with `docker compose stop`. This ensures your PDS stays running even after server reboots or unexpected failures.

**Log Rotation:**
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```objc

Without log rotation, Docker logs grow unbounded and can fill your disk. This configuration keeps the last 3 log files, each up to 10 MB, for a maximum of 30 MB of logs. Adjust these values based on your monitoring needs and disk space.

**Key configuration notes:**
- **Port binding to `127.0.0.1`** prevents direct external access—nginx is the only entry point
- **`PDS_TRUST_PROXY_HEADERS=1`** enables rate limiting by client IP (not nginx's IP)
- **Read-only config mount** prevents accidental modification
- **Log rotation** prevents disk space issues from unbounded log growth
- **Named volume** (`pds_pds_data`) makes backups easier to identify

---

## Step 4: Set Up Reverse Proxy

### 4.1 Obtain TLS Certificate

```bash
# Request Let's Encrypt certificate
sudo certbot certonly --nginx -d pds.yourdomain.com

# Certificate will be saved to:
# /etc/letsencrypt/live/pds.yourdomain.com/fullchain.pem
# /etc/letsencrypt/live/pds.yourdomain.com/privkey.pem
```objc

## 4.2 Configure nginx

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
```objc

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
```objc

## 4.3 Enable and Test nginx

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/pds /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Enable nginx on boot
sudo systemctl enable nginx
```objc

---

## Step 5: Start the PDS

### 5.1 Create Docker Volume

```bash
# Create persistent volume
docker volume create pds_pds_data

# Verify
docker volume inspect pds_pds_data
```objc

## 5.2 Start the Container

```bash
cd /opt/atprotopds/src/docker/pds

# Start in foreground (for initial testing)
docker compose up

# Watch logs for errors
# Expected output:
#   [INFO] Starting ATProto PDS on 0.0.0.0:2583
#   [INFO] Issuer: https://pds.yourdomain.com
#   [INFO] HTTP server listening on port 2583
```objc

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
```objc

## 5.3 Start in Background

```bash
# Stop foreground process (Ctrl+C)

# Start detached
docker compose up -d

# View logs
docker compose logs -f pds

# Check status
docker compose ps
```objc

---

## Step 6: Create First Account

### 6.1 Generate Invite Code

```bash
# Generate invite code
docker exec nspds kaszlak invite create

# Output: inv-abc123xyz456
```objc

## 6.2 Create Account via API

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
```objc

## 6.3 Verify Account

```bash
# Create session
curl -X POST https://pds.yourdomain.com/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "admin.yourdomain.com",
    "password": "secure-password-here"
  }'

# Save the accessJwt from response for authenticated requests
```objc

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
```objc

## 7.2 Test Manual Backup

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
```objc

## 7.3 Schedule Automated Backups

```bash
# Edit crontab
crontab -e

# Add daily backup at 3 AM
0 3 * * * /usr/local/bin/backup_pds.sh \
  --data-dir /var/lib/docker/volumes/pds_pds_data/_data \
  --backup-dir /var/backups/atprotopds \
  --retention 14 \
  >> /var/log/atprotopds/backup.log 2>&1
```objc

## 7.4 Restore from Backup

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
```objc

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
```objc

## 8.2 Monitor Resource Usage

```bash
# Container stats
docker stats nspds

# Disk usage
docker system df
du -sh /var/lib/docker/volumes/pds_pds_data/_data

# Database sizes
docker exec nspds sh -c 'du -sh /var/lib/atprotopds/data/*'
```objc

## 8.3 Health Checks

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
```objc

Schedule health checks:

```bash
# Add to crontab (every 5 minutes)
*/5 * * * * /usr/local/bin/check_pds_health.sh || \
  echo "PDS health check failed at $(date)" >> /var/log/atprotopds/health.log
```objc

## 8.4 Update the PDS

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
```objc

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
```objc

## 9.2 Fail2ban for Rate Limiting

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
```objc

## 9.3 Automatic Security Updates

```bash
# Install unattended-upgrades
sudo apt-get install -y unattended-upgrades

# Enable automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades
```objc

---

## Summary

Congratulations! You've successfully deployed a production-ready ATProto Personal Data Server. Let's review what you've accomplished and what you've learned.

### What You Built

You deployed a complete production system with multiple layers of security and reliability:

1. **Containerized Application**: Docker provides isolation, reproducibility, and easy updates
2. **TLS Encryption**: Let's Encrypt certificates ensure all traffic is encrypted
3. **Reverse Proxy**: nginx handles TLS termination, rate limiting, and security headers
4. **Automated Backups**: Scheduled backups with retention policies protect against data loss
5. **Health Monitoring**: Automated checks detect issues before users notice
6. **Security Hardening**: Firewall rules, fail2ban, and secure defaults protect your server

### Key Concepts Learned

**Defense in Depth**: Multiple security layers protect your system. Even if one layer fails, others provide protection. This is the foundation of production security.

**Configuration as Code**: Your `config.json` and `docker-compose.yml` files are the source of truth for your deployment. Version control them (minus secrets) to track changes and enable disaster recovery.

**Operational Excellence**: Production systems require ongoing maintenance—backups, monitoring, updates, and incident response. The tools you set up in this tutorial form the foundation of operational excellence.

**Security by Default**: The configuration you deployed follows security best practices: invite-only registration, rate limiting, TLS everywhere, and minimal attack surface. Never weaken these defaults without understanding the implications.

### Production Readiness Checklist

Before considering your deployment production-ready, verify:

- [x] TLS certificate is valid and auto-renewing (certbot handles this)
- [x] `invite_code_required` is `true` (prevents open registration)
- [x] `plc.url` is `"https://plc.directory"` (not `"mock"`)
- [x] All `debug.*` flags are `false` (no debug mode in production)
- [x] Rate limiting is enabled and tested
- [x] Firewall rules are configured (ufw)
- [x] Automated backups are scheduled and tested
- [x] Health checks are running (cron job)
- [x] Monitoring is in place (health check logs)
- [x] Privacy policy and ToS links are valid
- [x] nginx security headers are present (HSTS, X-Frame-Options, etc.)
- [x] Log rotation is configured (Docker logging driver)
- [x] Disk space monitoring is set up (manual checks or monitoring tool)

### Common Pitfalls to Avoid

**Don't skip backups**: "I'll set up backups later" is how you lose data. Set them up now, test them, and verify restores work.

**Don't disable security features**: Rate limiting, invite codes, and TLS aren't optional in production. They're the difference between a reliable service and a compromised server.

**Don't ignore monitoring**: If you don't know your server is down, your users will tell you—usually after they've already left. Set up monitoring before you need it.

**Don't run `docker compose` from the repo root**: Always run it from `docker/pds/`. This ensures the correct config file is mounted and volumes are created in the right location.

**Don't expose port 2583 directly**: nginx should be the only entry point. Direct exposure bypasses rate limiting, TLS, and security headers.

### Operational Best Practices

**Regular Updates**: Check for PDS updates monthly. Security vulnerabilities are discovered regularly, and updates patch them.

**Backup Testing**: Test your backup restore procedure quarterly. Backups you can't restore are useless.

**Capacity Planning**: Monitor disk usage, memory consumption, and CPU load. Plan upgrades before you run out of resources.

**Incident Response**: Document your incident response procedures. When something breaks at 3 AM, you don't want to be figuring out how to restore from backup.

**Security Audits**: Review your configuration quarterly. Are your security defaults still appropriate? Have new vulnerabilities been discovered?

---

## Next Steps

Your PDS is running, but there's always more to learn and improve.

**Further Reading:**
- [Configuration Reference](../11-reference/config-reference.md) — Complete documentation of all config options
- [Troubleshooting Guide](../11-reference/troubleshooting.md) — Solutions to common production issues
- [API Reference](../11-reference/api-reference.md) — XRPC endpoint documentation
- [Security Best Practices](../06-authentication/security-best-practices.md) — Advanced security hardening

**Advanced Production Topics:**

1. **External Monitoring**: Set up external monitoring with UptimeRobot, Pingdom, or similar services. They alert you when your server is unreachable from the internet.

2. **Log Aggregation**: Centralize logs with ELK Stack (Elasticsearch, Logstash, Kibana) or Grafana Loki. This makes debugging issues across multiple services much easier.

3. **Metrics Collection**: Implement Prometheus metrics collection and Grafana dashboards. Track request rates, error rates, database sizes, and resource usage over time.

4. **Horizontal Scaling**: As your user base grows, consider running multiple PDS instances behind a load balancer. This requires shared storage or database replication.

5. **Disaster Recovery**: Document your disaster recovery procedures. What do you do if the server's disk fails? If the entire server is lost? Having a plan before disaster strikes is critical.

6. **Compliance**: If you're serving users in the EU, understand GDPR requirements. If you're in California, understand CCPA. Data protection laws have real consequences.

**Community Resources:**

- **AT Protocol Discord**: Join the community to ask questions, share experiences, and learn from other PDS operators
- **GitHub Issues**: Report bugs, request features, and contribute improvements
- **Documentation Contributions**: Found something unclear? Submit a PR to improve the docs for the next person

**What's Next?**

Now that you have a running PDS, consider:
- Inviting friends and family to create accounts
- Integrating with Bluesky or other AT Protocol clients
- Contributing to the September PDS project
- Exploring the AT Protocol specifications
- Building custom tools and integrations

**Remember**: Running a PDS is a responsibility. You're hosting people's data and identity. Take security seriously, keep backups current, and monitor your system. Your users are trusting you with their digital presence.

---


## Summary

You've learned how to package, configure, and operate a September PDS instance for production, including setting up reverse proxies and TLS. You now have the complete skills needed to operate a node on the network!

## Further Reading
- [Reference Section](../11-reference/api-reference) — Detailed API and operational specs
