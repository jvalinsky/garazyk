---
title: Service Orchestration and Management Guide
description: Comprehensive guide to running and managing ATProto PDS and supporting services
---

# Service Orchestration Guide

This guide covers best practices for running the complete ATProto stack locally and in production, including the PLC (identity resolver), PDS (personal data server), and Admin UI.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Quick Start](#quick-start)
3. [Service Scripts](#service-scripts)
4. [Configuration](#configuration)
5. [Health Checks and Verification](#health-checks-and-verification)
6. [Troubleshooting](#troubleshooting)
7. [Best Practices](#best-practices)
8. [Production Deployment](#production-deployment)

## Architecture Overview

The ATProto stack consists of multiple services working together:

```
┌─────────────────────────────────────────────────────┐
│                   Clients / UI                        │
│  (Web, CLI, Mobile, etc.)                           │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│         ATProto PDS (kaszlak) - Port 2583          │
├─────────────────────────────────────────────────────┤
│ • XRPC Server                                        │
│ • Admin UI (/admin)                                  │
│ • Explorer UI (/explore)                            │
│ • OpenAPI Docs (/explore/api/docs)                  │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼ (trusts PLC for identity)
┌─────────────────────────────────────────────────────┐
│  PLC Directory (campagnola) - Port 2582            │
├─────────────────────────────────────────────────────┤
│ • DID resolution                                     │
│ • Identity verification                             │
│ • Service discovery                                 │
└─────────────────────────────────────────────────────┘
```

### Service Dependencies

- **PLC (campagnola)**: Identity service - must start first
- **PDS (kaszlak)**: Main server - depends on PLC for identity operations
- **Admin UI**: Integrated into PDS - available at `/admin`

## Quick Start

### Prerequisites

1. **Build the services first:**

```bash
# Generate Xcode project
xcodegen generate

# Build both services
xcodebuild -scheme campagnola build
xcodebuild -scheme kaszlak build
```

2. **Verify binaries exist:**

```bash
ls -la build/bin/campagnola build/bin/kaszlak
```

### Starting All Services

The easiest way to start everything:

```bash
# Start all services with default configuration
./scripts/start-all-services.sh

# With verbose logging
VERBOSE=true ./scripts/start-all-services.sh

# On custom ports
./scripts/start-all-services.sh --plc-port 3000 --pds-port 3001

# With custom data directory
./scripts/start-all-services.sh --data-dir /tmp/my-atproto-data
```

Services will:
1. Perform pre-flight checks (binaries, dependencies, directories)
2. Clean up any stray processes
3. Start PLC on port 2582
4. Wait for PLC to be healthy
5. Start PDS on port 2583
6. Verify service-to-service connectivity

## Service Scripts

### start-all-services.sh

Main orchestration script that manages the complete service stack.

**Usage:**

```bash
./scripts/start-all-services.sh [OPTIONS]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--skip-plc` | Skip PLC startup | off |
| `--skip-pds` | Skip PDS startup | off |
| `--skip-health-checks` | Skip health verification | off |
| `--skip-cleanup` | Don't clean stray processes | off |
| `--plc-port PORT` | PLC service port | 2582 |
| `--pds-port PORT` | PDS service port | 2583 |
| `--data-dir PATH` | Base data directory | `/tmp/atproto-services` |
| `--pds-issuer URL` | PDS issuer URL | `http://localhost:2583` |
| `--pds-log-level LEVEL` | PDS log level | `info` |
| `--plc-log-level LEVEL` | PLC log level | `info` |
| `--health-timeout SECS` | Health check timeout | 30 |
| `--health-retries N` | Health check max retries | 60 |
| `--verbose` | Enable verbose logging | off |
| `--quiet` | Suppress output | off |

**Examples:**

```bash
# Start with verbose debugging
VERBOSE=true ./scripts/start-all-services.sh

# Start only PDS (if PLC is already running)
./scripts/start-all-services.sh --skip-plc

# Start with custom configuration
./scripts/start-all-services.sh \
  --plc-port 3000 \
  --pds-port 3001 \
  --pds-issuer https://pds.example.com \
  --pds-log-level debug

# Start with persistent data
./scripts/start-all-services.sh --data-dir /var/lib/atproto
```

**What it does:**

1. **Pre-flight checks:**
   - Verifies required dependencies (pgrep, pkill, curl)
   - Checks that service binaries exist
   - Verifies ports are available
   - Creates required directories

2. **Service startup:**
   - Cleans up any stray processes on configured ports
   - Starts PLC service with proper configuration
   - Waits for PLC to become healthy
   - Starts PDS service with PLC configuration
   - Waits for PDS to become healthy

3. **Verification:**
   - Checks service-to-service connectivity
   - Verifies PDS can reach PLC
   - Prints service URLs and access information

4. **Cleanup:**
   - Handles SIGINT and SIGTERM for graceful shutdown
   - Cleans up PID files on exit
   - Ensures child processes are terminated

### services-control.sh

Utility script for managing running services.

**Usage:**

```bash
./scripts/services-control.sh <command> [options]
```

**Commands:**

| Command | Description |
|---------|-------------|
| `status` | Show status of all services |
| `stop [service]` | Stop services (plc, pds, or all) |
| `restart [service]` | Restart services |
| `logs [service] [lines]` | View service logs (last N lines) |
| `follow [service]` | Follow service logs in real-time |
| `test` | Run connectivity and health tests |
| `clean` | Stop services and clean up |
| `help` | Show help message |

**Examples:**

```bash
# Check service status
./scripts/services-control.sh status

# View PDS logs in real-time
./scripts/services-control.sh follow pds

# Restart only PDS
./scripts/services-control.sh restart pds

# Run connectivity tests
./scripts/services-control.sh test

# View last 100 lines of PLC logs
./scripts/services-control.sh logs plc 100

# Stop all services
./scripts/services-control.sh stop all

# Clean up everything
./scripts/services-control.sh clean
```

## Configuration

### Environment Variables

The scripts use these environment variables for configuration. All are optional and have sensible defaults:

**Service Binaries:**
- `PLC_BINARY` - Path to campagnola binary (default: `$BUILD_DIR/campagnola`)
- `PDS_BINARY` - Path to kaszlak binary (default: `$BUILD_DIR/kaszlak`)

**Ports:**
- `PLC_PORT` - PLC service port (default: 2582)
- `PDS_PORT` - PDS service port (default: 2583)

**Directories:**
- `DATA_DIR` - Base data directory (default: `/tmp/atproto-services`)
- `PLC_DATA_DIR` - PLC data directory (derived from DATA_DIR)
- `PDS_DATA_DIR` - PDS data directory (derived from DATA_DIR)
- `LOG_DIR` - Log directory (default: `$PROJECT_ROOT/logs`)

**Service Configuration:**
- `PDS_ISSUER` - PDS issuer URL (default: `http://localhost:2583`)
- `PDS_LOG_LEVEL` - PDS log level (default: `info`)
- `PLC_LOG_LEVEL` - PLC log level (default: `info`)

**Health Checks:**
- `HEALTH_CHECK_TIMEOUT` - Timeout in seconds (default: 30)
- `HEALTH_CHECK_RETRIES` - Max retries (default: 60)
- `HEALTH_CHECK_INTERVAL` - Check interval in seconds (default: 0.5)

**Behavior:**
- `SKIP_PLC` - Skip PLC startup (default: false)
- `SKIP_PDS` - Skip PDS startup (default: false)
- `SKIP_HEALTH_CHECKS` - Skip health verification (default: false)
- `SKIP_CLEANUP_ON_START` - Don't clean stray processes (default: false)
- `VERBOSE` - Enable verbose logging (default: false)
- `QUIET` - Suppress output (default: false)
- `NO_COLOR` - Disable colored output (default: false)

### Example Configuration

Set environment variables before running:

```bash
# Development setup
export VERBOSE=true
export PDS_LOG_LEVEL=debug
export DATA_DIR=/tmp/atproto-dev

./scripts/start-all-services.sh

# Testing setup
export DATA_DIR=/tmp/atproto-test
export SKIP_CLEANUP_ON_START=true

./scripts/start-all-services.sh

# Production setup (with persistent data)
export DATA_DIR=/var/lib/atproto
export PDS_ISSUER=https://pds.example.com
export PDS_LOG_LEVEL=warn
export HEALTH_CHECK_TIMEOUT=60

./scripts/start-all-services.sh
```

## Health Checks and Verification

### Automatic Health Checks

The `start-all-services.sh` script automatically performs:

1. **Process health checks** - Verifies services are running
2. **HTTP health endpoints** - Checks service responsiveness
3. **Connectivity verification** - Ensures services can communicate

### Manual Health Checks

Check service status:

```bash
# All services
./scripts/services-control.sh status

# Run connectivity tests
./scripts/services-control.sh test
```

### Manual Verification

```bash
# Check PLC health
curl -s http://127.0.0.1:2582/_health | jq .

# Check PDS health
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .

# Check Admin UI
curl -s -I http://localhost:2583/admin

# Check Explorer UI
curl -s -I http://localhost:2583/explore

# Check OpenAPI documentation
curl -s http://localhost:2583/explore/api/openapi.yaml | head -20
```

### Monitoring Services

View logs in real-time:

```bash
# Follow PLC logs
tail -f logs/plc.log

# Follow PDS logs
tail -f logs/pds.log

# Follow both
tail -f logs/*.log

# Or use the control script
./scripts/services-control.sh follow all
```

Search for errors:

```bash
# Find errors in logs
grep -i error logs/*.log

# Follow for new errors
tail -f logs/*.log | grep -i error

# Count errors
grep -i error logs/*.log | wc -l
```

## Troubleshooting

### Services Won't Start

**Check binaries exist:**

```bash
ls -la build/bin/campagnola build/bin/kaszlak
```

**Rebuild if needed:**

```bash
xcodebuild -scheme campagnola build
xcodebuild -scheme kaszlak build
```

### Port Already in Use

**Find which process is using the port:**

```bash
lsof -i :2582  # PLC
lsof -i :2583  # PDS
```

**Kill the process:**

```bash
kill -9 <PID>
# or
pkill -f "campagnola.*2582"
pkill -f "kaszlak.*2583"
```

**Use different ports:**

```bash
./scripts/start-all-services.sh --plc-port 3000 --pds-port 3001
```

### Services Start But Health Checks Fail

**Check logs:**

```bash
tail -f logs/plc.log
tail -f logs/pds.log
```

**Verify PLC started first:**

```bash
./scripts/services-control.sh status
```

**Increase health check timeout:**

```bash
HEALTH_CHECK_TIMEOUT=60 ./scripts/start-all-services.sh
```

### Connectivity Issues

**Test connectivity:**

```bash
./scripts/services-control.sh test
```

**Verify PDS can reach PLC:**

```bash
curl -s http://127.0.0.1:2582/_health
```

**Check PDS configuration:**

```bash
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .
```

### Database Issues

**Check database state:**

```bash
ls -la /tmp/atproto-services/pds/
sqlite3 /tmp/atproto-services/pds/pds.db ".schema"
```

**Reset database (WARNING - deletes all data):**

```bash
./scripts/services-control.sh stop all
rm -rf /tmp/atproto-services
./scripts/start-all-services.sh
```

### Memory Issues

**Check memory usage:**

```bash
ps aux | grep -E "campagnola|kaszlak"
```

**Monitor in real-time:**

```bash
watch -n 1 'ps aux | grep -E "campagnola|kaszlak"'
```

## Best Practices

### 1. Use Version Control for Data

Never commit the data directory to version control:

```bash
# Add to .gitignore
echo "logs/" >> .gitignore
echo "/tmp/atproto-services/" >> .gitignore
```

### 2. Log Rotation

For long-running services, implement log rotation:

```bash
# Using logrotate (macOS/Linux)
cat > /etc/logrotate.d/atproto << EOF
/path/to/project/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 user group
}
EOF
```

### 3. Process Management

Use supervisor or similar for production:

```bash
# Using systemd (Linux)
sudo cp scripts/start-all-services.sh /usr/local/bin/

# Create systemd service
sudo tee /etc/systemd/system/atproto.service > /dev/null << 'EOF'
[Unit]
Description=ATProto Services
After=network.target

[Service]
Type=simple
User=atproto
WorkingDirectory=/opt/atproto
ExecStart=/opt/atproto/scripts/start-all-services.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable atproto
sudo systemctl start atproto
```

### 4. Monitoring and Alerting

Set up monitoring for key metrics:

```bash
# CPU usage alert
while true; do
  cpu=$(ps aux | grep -E "campagnola|kaszlak" | awk '{sum+=$3} END {print sum}')
  if (( $(echo "$cpu > 80" | bc -l) )); then
    echo "WARNING: High CPU usage: $cpu%"
    ./scripts/services-control.sh status
  fi
  sleep 60
done
```

### 5. Backup Strategy

For persistent data:

```bash
#!/bin/bash
BACKUP_DIR="/backups/atproto"
DATA_DIR="/var/lib/atproto"

mkdir -p "$BACKUP_DIR"

# Daily backup
tar -czf "$BACKUP_DIR/atproto-$(date +%Y%m%d).tar.gz" "$DATA_DIR"

# Keep last 7 days
find "$BACKUP_DIR" -name "atproto-*.tar.gz" -mtime +7 -delete
```

### 6. Security Considerations

For production deployments:

- Run services as non-root user
- Use TLS/HTTPS in front (nginx, HAProxy)
- Restrict network access with firewall rules
- Use strong authentication for admin endpoints
- Regularly update dependencies

### 7. Development Workflow

For development:

```bash
# Start services
./scripts/start-all-services.sh

# In another terminal, watch logs
./scripts/services-control.sh follow all

# Run tests while services are running
./scripts/run-tests.sh

# Stop when done
./scripts/services-control.sh stop all
```

### 8. Performance Tuning

```bash
# Increase file descriptor limits
ulimit -n 4096

# Enable faster database operations
sqlite3 /tmp/atproto-services/pds/pds.db "PRAGMA journal_mode=WAL;"
sqlite3 /tmp/atproto-services/pds/pds.db "PRAGMA synchronous=NORMAL;"

# Monitor performance
watch -n 1 'lsof -p $(pgrep kaszlak) | wc -l'
```

## Production Deployment

### Pre-Deployment Checklist

- [ ] Services build successfully
- [ ] All tests pass
- [ ] Health checks configured appropriately
- [ ] Data directory mounted on persistent storage
- [ ] Log rotation configured
- [ ] Monitoring and alerting set up
- [ ] Backup strategy in place
- [ ] HTTPS/TLS reverse proxy configured
- [ ] Firewall rules configured
- [ ] Database backups verified

### Deployment Steps

1. **Build release binaries:**

```bash
xcodebuild -scheme campagnola -configuration Release build
xcodebuild -scheme kaszlak -configuration Release build
```

2. **Create persistent data directory:**

```bash
sudo mkdir -p /var/lib/atproto
sudo chown atproto:atproto /var/lib/atproto
sudo chmod 755 /var/lib/atproto
```

3. **Start services:**

```bash
export DATA_DIR=/var/lib/atproto
export PDS_ISSUER=https://pds.example.com
export PDS_LOG_LEVEL=info

./scripts/start-all-services.sh
```

4. **Verify deployment:**

```bash
./scripts/services-control.sh test
./scripts/services-control.sh status
```

5. **Set up monitoring:**

```bash
# Configure log aggregation, metrics, alerts
```

### Reverse Proxy Configuration (nginx)

```nginx
upstream pds {
    server localhost:2583;
}

server {
    listen 443 ssl http2;
    server_name pds.example.com;

    ssl_certificate /etc/letsencrypt/live/pds.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pds.example.com/privkey.pem;

    location / {
        proxy_pass http://pds;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name pds.example.com;
    return 301 https://$server_name$request_uri;
}
```

## Related Documentation

- [Setup and Installation Guide](./SETUP_GUIDE.md)
- [Deployment Tutorial](../10-tutorials/tutorial-6-deployment.md)
- [Configuration Reference](../11-reference/config-reference.md)
- [Testing Guide](../tests/TESTING.md)
- [Troubleshooting Guide](../guides/TROUBLESHOOTING.md)
