# ATProto Services Setup - Complete Package

This document summarizes the comprehensive bash scripts and guides created for running ATProto services with best practices.

## What Was Delivered

### 1. Core Service Orchestration Script
**File:** `scripts/start-all-services.sh` (21 KB)

A production-ready bash script that:
- Manages multiple services (PLC identity resolver, PDS main server)
- Handles service dependencies and startup order
- Performs comprehensive health checks
- Verifies service-to-service connectivity
- Graceful shutdown with signal handling
- Structured logging with verbosity levels
- Environment variable configuration
- Process management with PID files
- Error handling and validation

**Key Features:**
- Pre-flight checks (binaries, dependencies, ports, directories)
- Automatic cleanup of stray processes
- Health check with configurable timeouts and retries
- Service connectivity verification
- Detailed startup summary with URLs and logs
- Color-coded output for easy reading

### 2. Service Management Utility Script
**File:** `scripts/services-control.sh` (14 KB)

A helper script for managing running services:

**Commands:**
- `status` - Show service status and health
- `stop [service]` - Stop services
- `restart [service]` - Restart services
- `logs [service] [lines]` - View logs
- `follow [service]` - Follow logs in real-time
- `test` - Run connectivity tests
- `clean` - Stop all and clean up
- `help` - Show help

### 3. Comprehensive Documentation

**Service Orchestration Guide** (`docs/guides/SERVICE_ORCHESTRATION_GUIDE.md`)
- 500+ lines of detailed guidance
- Architecture overview with diagrams
- Complete configuration reference
- Health checks and verification procedures
- Troubleshooting guide with solutions
- Best practices for development and production
- Deployment strategies and examples
- Process management recommendations
- Monitoring and backup strategies

**Quick Reference Guide** (`docs/guides/SERVICE_QUICK_REFERENCE.md`)
- One-page quick lookup
- Common commands with examples
- URLs and access points
- Troubleshooting quick fixes
- Environment variables
- Tips and tricks

## Quick Start

### 1. Build Services First

```bash
# Generate Xcode project
xcodegen generate

# Build both services
xcodebuild -scheme campagnola build
xcodebuild -scheme kaszlak build

# Verify binaries exist
ls -la build/bin/campagnola build/bin/kaszlak
```

### 2. Start All Services

```bash
# Simple start
./scripts/start-all-services.sh

# With verbose logging for debugging
VERBOSE=true ./scripts/start-all-services.sh

# Custom configuration
./scripts/start-all-services.sh \
  --data-dir /tmp/my-atproto \
  --pds-log-level debug \
  --pds-issuer https://pds.example.com
```

### 3. Monitor and Manage

```bash
# Check status
./scripts/services-control.sh status

# Follow logs in real-time
./scripts/services-control.sh follow all

# Run health tests
./scripts/services-control.sh test

# Stop when done
./scripts/services-control.sh stop all
```

## Service URLs

Once running:

| Service | URL | Purpose |
|---------|-----|---------|
| **PDS API** | http://localhost:2583 | Main XRPC server |
| **Admin UI** | http://localhost:2583/admin | Administration interface |
| **Explorer** | http://localhost:2583/explore | Web explorer |
| **API Docs** | http://localhost:2583/explore/api/docs | OpenAPI documentation |
| **PLC** | http://127.0.0.1:2582 | Identity resolver (internal) |

## Architecture

```
┌─────────────────────────────────────────┐
│        Clients / Web UI                  │
└────────────────┬────────────────────────┘
                 │
                 ▼
     ┌───────────────────────────┐
     │  PDS (kaszlak) :2583      │
     │  • XRPC Server            │
     │  • Admin UI               │
     │  • Explorer UI            │
     │  • API Docs               │
     └────────────┬──────────────┘
                  │
                  ▼ (trusts)
     ┌───────────────────────────┐
     │  PLC (campagnola) :2582   │
     │  • DID Resolution         │
     │  • Identity Verification  │
     │  • Service Discovery      │
     └───────────────────────────┘
```

## Script Features

### start-all-services.sh

**Pre-flight Checks:**
- Verifies required dependencies exist
- Checks that service binaries are built
- Validates port availability
- Creates required directories

**Service Startup:**
- Cleans up any stray processes
- Starts PLC first (dependency)
- Waits for PLC to become healthy
- Starts PDS with proper configuration
- Waits for PDS to become healthy
- Verifies service-to-service connectivity

**Configuration:**
- Environment variable support
- Command-line argument parsing
- Defaults suitable for development
- Production-ready settings available

**Monitoring:**
- Real-time log capture with tee
- Health check polling with retry logic
- Process lifecycle management
- Graceful shutdown on signals

**Error Handling:**
- Pre-flight validation
- Process start verification
- Health check validation
- Comprehensive error messages

### services-control.sh

**Service Discovery:**
- Finds running services by port or PID file
- Verifies process is actually alive
- Reports current status and PIDs

**Service Management:**
- Graceful shutdown
- Process restart with proper ordering
- State persistence via PID files

**Monitoring:**
- Log file viewing with line count
- Real-time log following
- Multi-service log aggregation
- Log file size reporting

**Health Verification:**
- HTTP health endpoint testing
- Configuration validation
- Connectivity testing
- Result reporting

## Environment Variables

All are optional with sensible defaults:

**Service Control:**
```bash
SKIP_PLC=false              # Skip PLC startup
SKIP_PDS=false              # Skip PDS startup
SKIP_HEALTH_CHECKS=false    # Skip health verification
SKIP_CLEANUP_ON_START=false # Don't clean stray processes
```

**Service Configuration:**
```bash
PLC_PORT=2582               # PLC service port
PDS_PORT=2583               # PDS service port
PDS_ISSUER=http://localhost:2583  # PDS issuer URL
PDS_LOG_LEVEL=info          # PDS log level
PLC_LOG_LEVEL=info          # PLC log level
```

**Data & Logging:**
```bash
DATA_DIR=/tmp/atproto-services  # Base data directory
LOG_DIR=$PROJECT_ROOT/logs      # Log directory
```

**Health Checks:**
```bash
HEALTH_CHECK_TIMEOUT=30     # Timeout in seconds
HEALTH_CHECK_RETRIES=60     # Max retries
HEALTH_CHECK_INTERVAL=0.5   # Check interval in seconds
```

**Output Control:**
```bash
VERBOSE=false               # Enable verbose logging
QUIET=false                 # Suppress output
NO_COLOR=false              # Disable colored output
```

## Usage Examples

### Development Setup

```bash
# Terminal 1: Start services with verbose logging
VERBOSE=true ./scripts/start-all-services.sh

# Terminal 2: Follow logs
./scripts/services-control.sh follow all

# Terminal 3: Run tests, queries, etc.
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .

# When done: Stop services
./scripts/services-control.sh stop all
```

### Debugging

```bash
# Start with debug logging
./scripts/start-all-services.sh --pds-log-level debug --plc-log-level debug

# View logs
./scripts/services-control.sh logs all 200

# Test connectivity
./scripts/services-control.sh test

# Check detailed status
./scripts/services-control.sh status
```

### Custom Ports

```bash
./scripts/start-all-services.sh \
  --plc-port 3000 \
  --pds-port 3001 \
  --pds-issuer http://localhost:3001
```

### Persistent Data

```bash
export DATA_DIR=/var/lib/atproto
./scripts/start-all-services.sh
```

### Production Deployment

```bash
# Build release binaries
xcodebuild -scheme campagnola -configuration Release build
xcodebuild -scheme kaszlak -configuration Release build

# Start with production settings
export DATA_DIR=/var/lib/atproto
export PDS_ISSUER=https://pds.example.com
export PDS_LOG_LEVEL=warn

./scripts/start-all-services.sh

# Verify
./scripts/services-control.sh test
./scripts/services-control.sh status
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port
lsof -i :2583

# Kill it
kill -9 <PID>

# Or use different ports
./scripts/start-all-services.sh --pds-port 3001 --plc-port 3000
```

### Services Won't Start

```bash
# Check binaries exist
ls -la build/bin/

# Rebuild if needed
xcodebuild -scheme kaszlak build
xcodebuild -scheme campagnola build

# Check logs
tail -f logs/pds.log
./scripts/services-control.sh logs all 100
```

### Health Checks Failing

```bash
# View service status
./scripts/services-control.sh status

# Run tests
./scripts/services-control.sh test

# Try with longer timeout
HEALTH_CHECK_TIMEOUT=60 ./scripts/start-all-services.sh
```

### Clear Everything and Start Fresh

```bash
./scripts/services-control.sh stop all
rm -rf /tmp/atproto-services
./scripts/start-all-services.sh
```

## Best Practices

1. **Always check status first** - Use `./scripts/services-control.sh status` when debugging
2. **Follow logs early** - Open `./scripts/services-control.sh follow all` before starting
3. **Use verbose mode** - Add `VERBOSE=true` to see detailed startup information
4. **Test connectivity** - Run `./scripts/services-control.sh test` to verify wiring
5. **Keep logs available** - Log directory is at `logs/` for analysis
6. **Use version control appropriately** - Don't commit data or logs directories

## Integration with Your Workflow

### With xcodebuild

```bash
# Build services
xcodebuild -scheme campagnola build
xcodebuild -scheme kaszlak build

# Start orchestration
./scripts/start-all-services.sh

# Run tests while services run
./scripts/run-tests.sh
```

### With Docker

For containerized deployment, the orchestration still applies:

```bash
# Build images
docker build -f docker/Dockerfile -t atproto-pds .

# Run services with docker-compose from docker/pds/
cd docker/pds
docker compose up -d
```

### With systemd

For production Linux deployments:

```bash
# Install as systemd service
sudo cp scripts/start-all-services.sh /usr/local/bin/
sudo systemctl enable atproto
sudo systemctl start atproto
```

## Documentation References

- **Full Guide:** `docs/guides/SERVICE_ORCHESTRATION_GUIDE.md` - Comprehensive 500+ line guide
- **Quick Reference:** `docs/guides/SERVICE_QUICK_REFERENCE.md` - One-page reference
- **Setup Guide:** `docs/guides/SETUP_GUIDE.md` - Installation and configuration
- **Deployment Tutorial:** `docs/10-tutorials/tutorial-6-deployment.md` - Production deployment

## Log Locations

- **PLC Logs:** `logs/plc.log`
- **PDS Logs:** `logs/pds.log`
- **PID Files:** `.plc.pid` and `.pds.pid` (project root)

## Key Script Characteristics

### Error Handling

- Validates all prerequisites before starting
- Checks process health after startup
- Graceful cleanup on errors
- Informative error messages

### Logging

- Color-coded output for readability
- Timestamps on all log messages
- Separate error stream for errors
- Log file capture for debugging

### Process Management

- PID file tracking for easy management
- Signal handling for graceful shutdown
- Stray process cleanup
- Child process lifecycle management

### Verification

- Pre-flight dependency checks
- Binary existence validation
- Port availability checking
- Directory creation and validation
- Health endpoint verification
- Connectivity testing

## Files Created

```
scripts/
  ├── start-all-services.sh      (21 KB) - Main orchestration script
  └── services-control.sh         (14 KB) - Service management utility

docs/
  └── guides/
      ├── SERVICE_ORCHESTRATION_GUIDE.md   (500+ lines) - Comprehensive guide
      └── SERVICE_QUICK_REFERENCE.md       (200+ lines) - Quick reference

SERVICES_SETUP_SUMMARY.md          (This file) - Summary and quick start
```

## Support and Troubleshooting

If services don't start:

1. **Check prerequisites:** `ls -la build/bin/`
2. **Check logs:** `tail -f logs/*.log`
3. **Check ports:** `lsof -i :2582 && lsof -i :2583`
4. **Check status:** `./scripts/services-control.sh status`
5. **Run tests:** `./scripts/services-control.sh test`

For detailed help:
- See `SERVICE_ORCHESTRATION_GUIDE.md` for comprehensive guidance
- See `SERVICE_QUICK_REFERENCE.md` for quick lookup
- Run `./scripts/start-all-services.sh --help`
- Run `./scripts/services-control.sh help`

## Summary

This package provides:

✅ **Production-ready orchestration script** with health checks and verification  
✅ **Service management utility** for monitoring and control  
✅ **Comprehensive documentation** covering all aspects  
✅ **Best practices guidance** for development and production  
✅ **Error handling and validation** throughout  
✅ **Easy configuration** via environment variables or command-line args  
✅ **Real-time monitoring** with log following and status checks  
✅ **Graceful shutdown** with signal handling  
✅ **Modular design** allowing skip of individual services  

Everything is ready to use immediately. Simply build the services and run:

```bash
./scripts/start-all-services.sh
```
