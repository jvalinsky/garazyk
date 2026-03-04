---
title: PLC Server Operations
---

# PLC Server Operations

## Overview

`campagnola` is September's standalone PLC (Public Ledger of Credentials) directory server. It provides a self-hosted alternative to the public `plc.directory` service, enabling you to run your own DID registry for development, testing, or private AT Protocol networks.

**When to run your own PLC server:**
- **Development & Testing** — Local DID operations without external dependencies
- **Private Networks** — Isolated AT Protocol deployments
- **High Availability** — Redundant PLC infrastructure for production
- **Compliance** — Data sovereignty requirements
- **Research** — Experimentation with DID operations

**When to use plc.directory:**
- **Production PDS** — Public AT Protocol network participation
- **Simplicity** — No infrastructure management required
- **Interoperability** — Seamless integration with existing network

## Quick Start

### Development (In-Memory)

For local development and testing, use the in-memory mock store:

```bash
# Build campagnola
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build

# Start server with mock store
./build/bin/campagnola --port 2582
```

**Output:**
```

Using in-memory mock store
PLC server listening on port 2582
```

The mock store keeps all data in memory and is lost when the server stops.

## Production (Persistent Database)

For production deployments, use SQLite persistent storage:

```bash
# Create data directory
mkdir -p /var/lib/plc

# Start server with persistent database
./build/bin/campagnola --port 2582 --database /var/lib/plc/plc.db
```

**Output:**
```

Using persistent store at /var/lib/plc/plc.db
PLC server listening on port 2582
```

## Building Campagnola

### macOS

```bash
# Generate Xcode project
xcodegen generate

# Build campagnola
xcodebuild -scheme ATProtoPDS-CLI build

# Binary location
./build/bin/campagnola
```

## Linux (GNUstep)

```bash
# Out-of-source build
mkdir -p build-linux && cd build-linux

# Configure with CMake
cmake .. -DCMAKE_BUILD_TYPE=Release

# Build
make -j$(nproc)

# Binary location
./build-linux/bin/campagnola
```

## Verify Build

```bash
# Check binary exists
ls -lh ./build/bin/campagnola

# Test help output
./build/bin/campagnola --help
```

## Command-Line Options

### --port

Specify the TCP port to listen on.

```bash
./build/bin/campagnola --port 2582
```

**Default:** 2582

**Range:** 1024-65535 (use unprivileged ports)

### --database

Path to SQLite database file for persistent storage.

```bash
./build/bin/campagnola --database /var/lib/plc/plc.db
```

**Default:** None (uses in-memory mock store)

**Notes:**
- Database file is created automatically if it doesn't exist
- Parent directory must exist and be writable
- Database uses WAL mode for concurrent access

### --help, -h

Display help information and exit.

```bash
./build/bin/campagnola --help
```

## Configuration

### Storage Backend

Campagnola supports two storage backends:

#### Mock Store (In-Memory)

**Use for:**
- Local development
- Integration tests
- Temporary testing

**Characteristics:**
- No disk I/O
- Fast operations
- Data lost on restart
- No persistence

**Start command:**
```bash
./build/bin/campagnola --port 2582
```

#### Persistent Store (SQLite)

**Use for:**
- Production deployments
- Long-running development
- Data preservation

**Characteristics:**
- Persistent storage
- WAL mode enabled
- Concurrent read access
- ACID transactions

**Start command:**
```bash
./build/bin/campagnola --port 2582 --database /var/lib/plc/plc.db
```

### Database Schema

The persistent store uses a simple schema optimized for DID operations:

```sql
CREATE TABLE operations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    cid TEXT NOT NULL,
    operation TEXT NOT NULL,  -- JSON-encoded operation
    nullified INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_operations_did ON operations(did);
CREATE INDEX idx_operations_cid ON operations(cid);
CREATE INDEX idx_operations_created_at ON operations(created_at);
CREATE INDEX idx_operations_nullified ON operations(nullified);
```

**Key features:**
- `did` — DID identifier for quick lookups
- `cid` — Content identifier for operation chaining
- `operation` — Full operation data as JSON
- `nullified` — Flag for invalidated operations
- `created_at` — Timestamp for export/audit


## API Endpoints

Campagnola implements the standard PLC directory API:

### GET /:did

Resolve a DID to its current document.

```bash
curl http://localhost:2582/did:plc:z72i7hdynmk6r22z27h6tvur
```

**Response (200 OK):**
```json
{
  "@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/multikey/v1"
  ],
  "id": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "alsoKnownAs": ["at://alice.bsky.social"],
  "verificationMethod": [
    {
      "id": "did:plc:z72i7hdynmk6r22z27h6tvur#atproto",
      "type": "Multikey",
      "controller": "did:plc:z72i7hdynmk6r22z27h6tvur",
      "publicKeyMultibase": "zQ3sh..."
    }
  ],
  "service": [
    {
      "id": "#atproto_pds",
      "type": "AtprotoPersonalDataServer",
      "serviceEndpoint": "https://pds.example.com"
    }
  ]
}
```

**Response (404 Not Found):**
```json
{
  "error": "DID not found"
}
```

**Response (410 Gone):**
```json
{
  "message": "DID not available: did:plc:..."
}
```

Returned when DID has been tombstoned.

### GET /:did/log

Retrieve the complete audit log for a DID.

```bash
curl http://localhost:2582/did:plc:z72i7hdynmk6r22z27h6tvur/log
```

**Response (200 OK):**
```json
[
  {
    "type": "plc_operation",
    "rotationKeys": ["did:key:zQ3sh..."],
    "verificationMethods": {
      "atproto": "did:key:zQ3sh..."
    },
    "alsoKnownAs": ["at://alice.bsky.social"],
    "services": {
      "atproto_pds": {
        "type": "AtprotoPersonalDataServer",
        "endpoint": "https://pds.example.com"
      }
    },
    "prev": null,
    "sig": "..."
  }
]
```

### GET /:did/log/audit

Retrieve the audit log with metadata (includes nullified operations).

```bash
curl http://localhost:2582/did:plc:z72i7hdynmk6r22z27h6tvur/log/audit
```

**Response (200 OK):**
```json
[
  {
    "did": "did:plc:z72i7hdynmk6r22z27h6tvur",
    "cid": "bafyreiabc...",
    "operation": {
      "type": "plc_operation",
      "rotationKeys": ["did:key:zQ3sh..."],
      "prev": null,
      "sig": "..."
    },
    "nullified": false,
    "createdAt": "2024-01-15T10:30:00Z"
  }
]
```

### GET /:did/log/last

Get the most recent operation for a DID.

```bash
curl http://localhost:2582/did:plc:z72i7hdynmk6r22z27h6tvur/log/last
```

**Response (200 OK):**
```json
{
  "type": "plc_operation",
  "rotationKeys": ["did:key:zQ3sh..."],
  "prev": "bafyreiabc...",
  "sig": "..."
}
```

### POST /:did

Submit a new operation for a DID.

```bash
curl -X POST http://localhost:2582/did:plc:z72i7hdynmk6r22z27h6tvur \
  -H "Content-Type: application/json" \
  -d '{
    "type": "plc_operation",
    "rotationKeys": ["did:key:zQ3sh..."],
    "verificationMethods": {
      "atproto": "did:key:zQ3sh..."
    },
    "alsoKnownAs": ["at://alice.bsky.social"],
    "services": {
      "atproto_pds": {
        "type": "AtprotoPersonalDataServer",
        "endpoint": "https://pds.example.com"
      }
    },
    "prev": null,
    "sig": "..."
  }'
```

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

**Response (400 Bad Request):**
```json
{
  "error": "Invalid operation format: ..."
}
```

### GET /export

Export operations for replication or backup.

```bash
# Export first 100 operations
curl http://localhost:2582/export?count=100

# Export operations after timestamp
curl http://localhost:2582/export?after=2024-01-15T10:30:00.000Z&count=100
```

**Query Parameters:**
- `count` — Number of operations to return (default: 10, max: 1000)
- `after` — ISO 8601 timestamp (exclusive lower bound)

**Response (200 OK):**
```

{"did":"did:plc:abc...","operation":{...},"cid":"bafyrei...","nullified":false,"createdAt":"2024-01-15T10:30:00.000Z"}
{"did":"did:plc:def...","operation":{...},"cid":"bafyrei...","nullified":false,"createdAt":"2024-01-15T10:31:00.000Z"}
```

**Format:** JSON Lines (one JSON object per line)

## GET /_health

Health check endpoint.

```bash
curl http://localhost:2582/_health
```

**Response (200 OK):**
```json
{
  "status": "ok"
}
```

### GET /_list

List all DIDs in the directory.

```bash
curl http://localhost:2582/_list
```

**Response (200 OK):**
```json
[
  "did:plc:z72i7hdynmk6r22z27h6tvur",
  "did:plc:ewvi7nxzyoun6zhxrhs64oiz"
]
```

### GET /_metrics

Prometheus-compatible metrics endpoint.

```bash
curl http://localhost:2582/_metrics
```

**Response (200 OK):**
```

# HELP plc_requests_total Total number of requests
# TYPE plc_requests_total counter
plc_requests_total 1234

# HELP plc_errors_total Total number of errors
# TYPE plc_errors_total counter
plc_errors_total 5
```

## Production Deployment

### Systemd Service

Create a systemd service for automatic startup and management:

```ini
# /etc/systemd/system/campagnola.service
[Unit]
Description=Campagnola PLC Directory Server
After=network.target

[Service]
Type=simple
User=plc
Group=plc
WorkingDirectory=/opt/campagnola
ExecStart=/opt/campagnola/bin/campagnola --port 2582 --database /var/lib/plc/plc.db
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/plc

# Resource limits
LimitNOFILE=65536
MemoryMax=1G

[Install]
WantedBy=multi-user.target
```

**Enable and start:**
```bash
# Create user and directories
sudo useradd -r -s /bin/false plc
sudo mkdir -p /var/lib/plc /opt/campagnola/bin
sudo chown plc:plc /var/lib/plc

# Copy binary
sudo cp ./build/bin/campagnola /opt/campagnola/bin/

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable campagnola
sudo systemctl start campagnola

# Check status
sudo systemctl status campagnola
```

## Docker Deployment

Create a Dockerfile for containerized deployment:

```dockerfile
# Dockerfile
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    gnustep-base-runtime \
    libsqlite3-0 \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create user
RUN useradd -r -s /bin/false plc

# Copy binary
COPY build/bin/campagnola /usr/local/bin/campagnola
RUN chmod +x /usr/local/bin/campagnola

# Create data directory
RUN mkdir -p /var/lib/plc && chown plc:plc /var/lib/plc

USER plc
WORKDIR /var/lib/plc

EXPOSE 2582

CMD ["/usr/local/bin/campagnola", "--port", "2582", "--database", "/var/lib/plc/plc.db"]
```

**Build and run:**
```bash
# Build image
docker build -t campagnola:latest .

# Run container
docker run -d \
  --name campagnola \
  -p 2582:2582 \
  -v plc_data:/var/lib/plc \
  --restart unless-stopped \
  campagnola:latest

# Check logs
docker logs -f campagnola
```

## Reverse Proxy (Nginx)

Configure Nginx as a reverse proxy with TLS:

```nginx
# /etc/nginx/sites-available/plc.example.com
server {
    listen 443 ssl http2;
    server_name plc.example.com;

    ssl_certificate /etc/letsencrypt/live/plc.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/plc.example.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=plc_limit:10m rate=10r/s;
    limit_req zone=plc_limit burst=20 nodelay;

    location / {
        proxy_pass http://127.0.0.1:2582;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }

    # Health check endpoint (no rate limit)
    location /_health {
        proxy_pass http://127.0.0.1:2582;
        access_log off;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name plc.example.com;
    return 301 https://$server_name$request_uri;
}
```

**Enable configuration:**
```bash
sudo ln -s /etc/nginx/sites-available/plc.example.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Database Maintenance

### Backup

Regular backups are essential for production deployments.

#### SQLite Backup (Online)

Use SQLite's online backup API for safe backups while the server is running:

```bash
# Backup script
#!/bin/bash
BACKUP_DIR="/var/backups/plc"
DB_PATH="/var/lib/plc/plc.db"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# SQLite online backup
sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/plc-$TIMESTAMP.db'"

# Compress backup
gzip "$BACKUP_DIR/plc-$TIMESTAMP.db"

# Keep last 30 days
find "$BACKUP_DIR" -name "plc-*.db.gz" -mtime +30 -delete

echo "Backup completed: plc-$TIMESTAMP.db.gz"
```

## File Copy (Offline)

For offline backups, stop the server first:

```bash
# Stop server
sudo systemctl stop campagnola

# Copy database
cp /var/lib/plc/plc.db /var/backups/plc/plc-$(date +%Y%m%d).db

# Copy WAL files if they exist
cp /var/lib/plc/plc.db-wal /var/backups/plc/ 2>/dev/null || true
cp /var/lib/plc/plc.db-shm /var/backups/plc/ 2>/dev/null || true

# Start server
sudo systemctl start campagnola
```

## Restore

To restore from backup:

```bash
# Stop server
sudo systemctl stop campagnola

# Restore database
gunzip -c /var/backups/plc/plc-20240115-120000.db.gz > /var/lib/plc/plc.db

# Fix permissions
sudo chown plc:plc /var/lib/plc/plc.db

# Start server
sudo systemctl start campagnola
```

## Database Optimization

Periodically optimize the database for performance:

```bash
# Vacuum database (reclaim space)
sqlite3 /var/lib/plc/plc.db "VACUUM;"

# Analyze database (update statistics)
sqlite3 /var/lib/plc/plc.db "ANALYZE;"

# Check integrity
sqlite3 /var/lib/plc/plc.db "PRAGMA integrity_check;"
```

**Schedule optimization:**
```bash
# Add to crontab
0 3 * * 0 sqlite3 /var/lib/plc/plc.db "VACUUM; ANALYZE;"
```

## Database Growth

Monitor database size and plan for growth:

```bash
# Check database size
du -h /var/lib/plc/plc.db

# Check operation count
sqlite3 /var/lib/plc/plc.db "SELECT COUNT(*) FROM operations;"

# Check per-DID statistics
sqlite3 /var/lib/plc/plc.db "
SELECT did, COUNT(*) as op_count 
FROM operations 
GROUP BY did 
ORDER BY op_count DESC 
LIMIT 10;
"
```

**Growth estimates:**
- Average operation size: ~500 bytes
- 1000 DIDs × 10 operations each = ~5 MB
- 10,000 DIDs × 10 operations each = ~50 MB
- 100,000 DIDs × 10 operations each = ~500 MB

## Migration

When upgrading campagnola versions, check for schema migrations:

```bash
# Check current schema version
sqlite3 /var/lib/plc/plc.db "PRAGMA user_version;"

# Backup before migration
sqlite3 /var/lib/plc/plc.db ".backup '/var/backups/plc/pre-migration.db'"

# Restart server (migrations run automatically)
sudo systemctl restart campagnola

# Verify migration
sudo journalctl -u campagnola -n 50
```

## Monitoring

### Health Checks

Configure health check monitoring:

```bash
# Simple health check script
#!/bin/bash
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:2582/_health)

if [ "$RESPONSE" = "200" ]; then
    echo "OK: PLC server is healthy"
    exit 0
else
    echo "CRITICAL: PLC server returned $RESPONSE"
    exit 2
fi
```

**Nagios/Icinga configuration:**
```ini
define service {
    service_description     PLC Health Check
    host_name               plc.example.com
    check_command           check_http!-p 2582 -u /_health
    check_interval          1
    retry_interval          1
    max_check_attempts      3
}
```

## Metrics Collection

Scrape Prometheus metrics:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'campagnola'
    static_configs:
      - targets: ['localhost:2582']
    metrics_path: '/_metrics'
    scrape_interval: 15s
```

**Key metrics:**
- `plc_requests_total` — Total request count
- `plc_errors_total` — Total error count


## Log Monitoring

Monitor server logs for issues:

```bash
# Follow logs (systemd)
sudo journalctl -u campagnola -f

# Search for errors
sudo journalctl -u campagnola | grep ERROR

# Show logs from last hour
sudo journalctl -u campagnola --since "1 hour ago"
```

**Log patterns to monitor:**
- `Failed to open persistent store` — Database access issues
- `Failed to start PLC server` — Startup failures
- `Audit failed` — Invalid operation submissions
- `Failed to append` — Database write failures

## Performance Monitoring

Track key performance indicators:

```bash
# Request rate
curl -s http://localhost:2582/_metrics | grep plc_requests_total

# Error rate
curl -s http://localhost:2582/_metrics | grep plc_errors_total

# Database size
du -h /var/lib/plc/plc.db

# Process memory usage
ps aux | grep campagnola | awk '{print $6/1024 " MB"}'
```

## Integration with PDS

### Configure PDS to Use Custom PLC

Update your PDS `config.json` to point to your campagnola instance:

```json
{
  "plc": {
    "url": "https://plc.example.com",
    "retry_count": 5,
    "retry_delay_ms": 2000
  }
}
```

**Important:** Never use `"mock"` in production. Always use a real PLC URL.

### Test Integration

Verify PDS can resolve DIDs from your PLC server:

```bash
# Create a test DID on your PLC
curl -X POST http://localhost:2582/did:plc:test123 \
  -H "Content-Type: application/json" \
  -d '{
    "type": "plc_operation",
    "rotationKeys": ["did:key:zQ3sh..."],
    "verificationMethods": {"atproto": "did:key:zQ3sh..."},
    "alsoKnownAs": ["at://test.example.com"],
    "services": {
      "atproto_pds": {
        "type": "AtprotoPersonalDataServer",
        "endpoint": "https://pds.example.com"
      }
    },
    "prev": null,
    "sig": "..."
  }'

# Verify PDS can resolve it
curl https://pds.example.com/xrpc/com.atproto.identity.resolveHandle?handle=test.example.com
```

## High Availability Setup

For production deployments, run multiple PLC servers:

```

┌─────────────┐
│ Load Balancer│
│  (HAProxy)   │
└──────┬───────┘
       │
   ┌───┴────┬────────┬────────┐
   │        │        │        │
┌──▼──┐  ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
│PLC 1│  │PLC 2│  │PLC 3│  │PLC 4│
└──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘
   │        │        │        │
   └────────┴────────┴────────┘
              │
      ┌───────▼────────┐
      │ Shared Database│
      │  (PostgreSQL)  │
      └────────────────┘
```

**Note:** Current implementation uses SQLite. For true HA, consider:
- Read replicas with SQLite replication
- Shared network filesystem (NFS, GlusterFS)
- Migration to PostgreSQL backend (requires code changes)

## Troubleshooting

### Server Won't Start

**Symptom:** Server exits immediately after starting.

**Diagnosis:**
```bash
# Check logs
sudo journalctl -u campagnola -n 50

# Run manually to see errors
./build/bin/campagnola --port 2582 --database /var/lib/plc/plc.db
```

**Common causes:**
1. **Port already in use**
   ```bash
   # Check what's using the port
   sudo lsof -i :2582
   
   # Kill the process or use a different port
   ./build/bin/campagnola --port 2583
   ```text

2. **Database permission denied**
   ```bash
   # Fix permissions
   sudo chown plc:plc /var/lib/plc/plc.db
   sudo chmod 644 /var/lib/plc/plc.db
   ```text

3. **Database corruption**
   ```bash
   # Check integrity
   sqlite3 /var/lib/plc/plc.db "PRAGMA integrity_check;"
   
   # Restore from backup if corrupted
   cp /var/backups/plc/plc-latest.db /var/lib/plc/plc.db
   ```text

## Operation Submission Fails

**Symptom:** POST requests return 400 Bad Request.

**Diagnosis:**
```bash
# Check error message
curl -X POST http://localhost:2582/did:plc:test \
  -H "Content-Type: application/json" \
  -d '{"type":"plc_operation",...}' \
  -v
```

**Common causes:**
1. **Invalid operation format**
   - Check all required fields are present
   - Verify signature is base64url (no padding)
   - Ensure `prev` matches previous operation CID

2. **Operation too large**
   - Maximum size: 4000 bytes (CBOR-encoded)
   - Reduce field sizes or split operations

3. **Invalid signature**
   - Verify signature is computed correctly
   - Check rotation key is authorized
   - Ensure `prev` link is correct


## DID Resolution Returns 404

**Symptom:** GET requests for DIDs return 404 Not Found.

**Diagnosis:**
```bash
# Check if DID exists
curl http://localhost:2582/_list | grep "did:plc:test"

# Check operation history
sqlite3 /var/lib/plc/plc.db "SELECT * FROM operations WHERE did='did:plc:test';"
```

**Common causes:**
1. **DID not created yet**
   - Submit genesis operation first
   - Verify operation was accepted (200 OK)

2. **Database not persisted**
   - Check if using mock store (data lost on restart)
   - Use `--database` flag for persistence

3. **Wrong PLC server**
   - Verify you're querying the correct server
   - Check PDS configuration points to right PLC URL

## High Memory Usage

**Symptom:** Server consumes excessive memory.

**Diagnosis:**
```bash
# Check memory usage
ps aux | grep campagnola

# Check database size
du -h /var/lib/plc/plc.db

# Check operation count
sqlite3 /var/lib/plc/plc.db "SELECT COUNT(*) FROM operations;"
```

**Solutions:**
1. **Vacuum database**
   ```bash
   sqlite3 /var/lib/plc/plc.db "VACUUM;"
   ```text

2. **Set memory limits**
   ```ini
   # In systemd service
   MemoryMax=512M
   MemoryHigh=384M
   ```text

3. **Archive old operations**
   ```bash
   # Export operations
   curl "http://localhost:2582/export?count=1000" > operations.jsonl
   
   # Consider implementing operation pruning
   # (requires code changes)
   ```text

## Slow Response Times

**Symptom:** API requests take longer than expected.

**Diagnosis:**
```bash
# Measure response time
time curl http://localhost:2582/did:plc:test

# Check database performance
sqlite3 /var/lib/plc/plc.db "EXPLAIN QUERY PLAN SELECT * FROM operations WHERE did='did:plc:test';"
```

**Solutions:**
1. **Optimize database**
   ```bash
   sqlite3 /var/lib/plc/plc.db "ANALYZE;"
   ```text

2. **Check indexes**
   ```bash
   sqlite3 /var/lib/plc/plc.db ".indexes operations"
   ```text

3. **Enable WAL mode** (should be automatic)
   ```bash
   sqlite3 /var/lib/plc/plc.db "PRAGMA journal_mode=WAL;"
   ```text

4. **Add caching layer** (nginx, Varnish)


## Security Considerations

### Network Security

1. **Always use HTTPS in production**
   - Never expose campagnola directly to the internet
   - Use reverse proxy (Nginx, Caddy) with TLS
   - Obtain certificates from Let's Encrypt

2. **Firewall configuration**
   ```bash
   # Allow only from reverse proxy
   sudo ufw allow from 127.0.0.1 to any port 2582
   sudo ufw deny 2582
   ```text

3. **Rate limiting**
   - Implement at reverse proxy level
   - Protect against DoS attacks
   - Limit POST requests more strictly than GET

### Access Control

1. **Read-only public access**
   - GET endpoints should be public
   - POST endpoints may need authentication
   - Consider API keys for write operations

2. **Admin endpoints**
   - Restrict `/_list` and `/_metrics` to internal networks
   - Use firewall rules or reverse proxy ACLs

### Data Integrity

1. **Operation validation**
   - Campagnola validates all operations before accepting
   - Signature verification ensures authenticity
   - Chain validation prevents tampering

2. **Backup verification**
   ```bash
   # Verify backup integrity
   sqlite3 /var/backups/plc/plc-backup.db "PRAGMA integrity_check;"
   
   # Compare operation counts
   sqlite3 /var/lib/plc/plc.db "SELECT COUNT(*) FROM operations;"
   sqlite3 /var/backups/plc/plc-backup.db "SELECT COUNT(*) FROM operations;"
   ```text

3. **Audit logging**
   - Enable detailed logging for security events
   - Monitor for suspicious operation patterns
   - Track failed authentication attempts

### Updates

Keep campagnola up to date:

```bash
# Check current version
./build/bin/campagnola --help | head -1

# Pull latest code
git pull origin main

# Rebuild
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build

# Backup database before upgrading
sqlite3 /var/lib/plc/plc.db ".backup '/var/backups/plc/pre-upgrade.db'"

# Restart with new binary
sudo systemctl restart campagnola
```

## Best Practices

### Development

1. **Use mock store for testing**
   ```bash
   ./build/bin/campagnola --port 2582
   ```text

2. **Separate test and production databases**
   ```bash
   # Test
   ./build/bin/campagnola --port 2582 --database ./test-plc.db
   
   # Production
   ./build/bin/campagnola --port 2582 --database /var/lib/plc/plc.db
   ```text

3. **Version control configuration**
   - Keep deployment scripts in version control
   - Document configuration changes
   - Use infrastructure as code (Terraform, Ansible)

### Production

1. **Always use persistent storage**
   - Never use mock store in production
   - Use `--database` flag with absolute path
   - Ensure database directory has adequate space

2. **Implement monitoring**
   - Health checks every 60 seconds
   - Alert on consecutive failures
   - Monitor disk space and memory usage
   - Track request/error rates

3. **Regular backups**
   - Automated daily backups
   - Test restore procedures
   - Keep backups for 30+ days
   - Store backups off-site

4. **Capacity planning**
   - Monitor database growth rate
   - Plan for 3-6 months of growth
   - Set up alerts for disk space
   - Consider archival strategies

5. **Documentation**
   - Document deployment procedures
   - Maintain runbooks for common issues
   - Keep contact information current
   - Document custom configurations

### Operations

1. **Change management**
   - Test changes in staging first
   - Schedule maintenance windows
   - Communicate downtime in advance
   - Have rollback plan ready

2. **Incident response**
   - Define severity levels
   - Establish escalation procedures
   - Document incident resolution
   - Conduct post-mortems

3. **Performance optimization**
   - Regular database maintenance
   - Monitor query performance
   - Optimize slow queries
   - Consider caching strategies


## Advanced Topics

### Replication

Export and import operations for replication:

```bash
# Export from source server
curl "http://source-plc:2582/export?count=1000" > operations.jsonl

# Import to destination server (requires custom script)
while IFS= read -r line; do
    did=$(echo "$line" | jq -r '.did')
    operation=$(echo "$line" | jq -c '.operation')
    
    curl -X POST "http://dest-plc:2582/$did" \
      -H "Content-Type: application/json" \
      -d "$operation"
done < operations.jsonl
```

## Custom Validation

Extend operation validation by modifying `PLCAuditor`:

```objc
// In PLCAuditor.m
- (BOOL)verifyOperation:(PLCOperation *)op
          proposedDate:(NSDate *)date
          nullifiedCIDs:(NSArray<NSString *> **)nullified
                 error:(NSError **)error {
    // Add custom validation logic
    if ([self shouldRejectOperation:op]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CustomValidation"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Custom validation failed"}];
        }
        return NO;
    }
    
    // Continue with standard validation
    return [super verifyOperation:op proposedDate:date nullifiedCIDs:nullified error:error];
}
```

### Metrics Extension

Add custom metrics to `PLCMetrics`:

```objc
// In PLCMetrics.h
@property (atomic, assign) NSUInteger customMetric;

// In PLCMetrics.m
- (NSString *)renderMetrics {
    NSMutableString *metrics = [NSMutableString string];
    
    // Standard metrics
    [metrics appendFormat:@"plc_requests_total %lu\n", (unsigned long)self.requestCount];
    [metrics appendFormat:@"plc_errors_total %lu\n", (unsigned long)self.errorCount];
    
    // Custom metrics
    [metrics appendFormat:@"plc_custom_metric %lu\n", (unsigned long)self.customMetric];
    
    return metrics;
}
```

### Web UI Customization

Campagnola includes a web UI in `ATProtoPDS/Sources/PLC/Assets/`. Customize it:

```bash
# Edit HTML
vim ATProtoPDS/Sources/PLC/Assets/index.html

# Edit CSS
vim ATProtoPDS/Sources/PLC/Assets/css/style.css

# Edit JavaScript
vim ATProtoPDS/Sources/PLC/Assets/js/app.js

# Rebuild
xcodebuild -scheme ATProtoPDS-CLI build
```

## Quick Reference

### Common Commands

```bash
# Start with mock store
./build/bin/campagnola --port 2582

# Start with persistent database
./build/bin/campagnola --port 2582 --database /var/lib/plc/plc.db

# Check health
curl http://localhost:2582/_health

# List all DIDs
curl http://localhost:2582/_list

# Resolve DID
curl http://localhost:2582/did:plc:abc123

# Get audit log
curl http://localhost:2582/did:plc:abc123/log/audit

# Export operations
curl "http://localhost:2582/export?count=100"

# Check metrics
curl http://localhost:2582/_metrics
```

## File Locations

| Item | Location |
|------|----------|
| Binary | `./build/bin/campagnola` |
| Database | `/var/lib/plc/plc.db` |
| Backups | `/var/backups/plc/` |
| Systemd service | `/etc/systemd/system/campagnola.service` |
| Nginx config | `/etc/nginx/sites-available/plc.example.com` |
| Logs | `journalctl -u campagnola` |

### Default Values

| Setting | Default |
|---------|---------|
| Port | 2582 |
| Storage | Mock (in-memory) |
| Max operation size | 4000 bytes |
| Max rotation keys | 10 |
| Max verification methods | 10 |
| Max services | 10 |
| Max alsoKnownAs | 10 |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Failed to open database or start server |

## Related Documentation

- **[PLC Directory Concepts](../02-core-concepts/plc-directory)** — PLC protocol and DID operations
- **[CLI Reference](cli-reference)** — kaszlak CLI commands
- **[Config Reference](config-reference)** — PDS configuration options
- **[Troubleshooting](troubleshooting)** — Common issues and solutions

## External Resources

- **AT Protocol DID Specification:** https://atproto.com/specs/did
- **PLC Directory:** https://plc.directory
- **W3C DID Core:** https://www.w3.org/TR/did-core/
- **SQLite Documentation:** https://www.sqlite.org/docs.html

