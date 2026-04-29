---
title: Service Management Quick Reference
description: Quick lookup for common service operations
---

# Service Quick Reference

Quick reference for starting, stopping, and monitoring ATProto services.

## One-Command Start

```bash
# Start all services (PLC + PDS)
./scripts/start-all-services.sh

# With verbose output for debugging
VERBOSE=true ./scripts/start-all-services.sh
```

## Access URLs

| Service | URL | Purpose |
|---------|-----|---------|
| PDS API | `http://localhost:2583` | Main XRPC server |
| Admin UI | `http://127.0.0.1:2590/admin` | Standalone operator interface (`garazyk-ui`) |
| Explorer API | `http://localhost:2583/api/pds/*` | Runtime inspection endpoints |
| API Docs | `http://localhost:2583/api/pds/docs` | OpenAPI docs |
| PLC Server | `http://127.0.0.1:2582` | Identity resolver (internal) |

## Common Commands

### Status & Monitoring

```bash
# Show all service status
./scripts/services-control.sh status

# Follow all logs in real-time
./scripts/services-control.sh follow all

# View last 50 lines of logs
./scripts/services-control.sh logs all

# Run health tests
./scripts/services-control.sh test
```

### Starting & Stopping

```bash
# Start all services
./scripts/start-all-services.sh

# Start only PDS (if PLC already running)
./scripts/start-all-services.sh --skip-plc

# Stop all services
./scripts/services-control.sh stop all

# Stop only PDS
./scripts/services-control.sh stop pds

# Restart all services
./scripts/services-control.sh restart all

# Stop everything and clean up
./scripts/services-control.sh clean
```

### Logging

```bash
# View PDS logs (last 50 lines)
./scripts/services-control.sh logs pds

# View PDS logs (last 100 lines)
./scripts/services-control.sh logs pds 100

# Follow PDS logs in real-time
./scripts/services-control.sh follow pds

# Search logs for errors
grep -i error logs/*.log
```

## Development Workflow

```bash
# Terminal 1: Start services
./scripts/start-all-services.sh

# Terminal 2: Follow logs
./scripts/services-control.sh follow all

# Terminal 3: Run tests, etc.
./scripts/test/run-tests.sh

# When done
./scripts/services-control.sh stop all
```

## Troubleshooting

### Port Already in Use

```bash
# Find what's using the port
lsof -i :2583

# Kill it
kill -9 <PID>

# Or use the script to start on different ports
./scripts/start-all-services.sh --pds-port 3001 --plc-port 3000
```

### Services Won't Start

```bash
# Check binaries exist
ls -la build/bin/

# Rebuild if needed
xcodebuild -scheme kaszlak build
xcodebuild -scheme campagnola build
xcodebuild -scheme garazyk-ui build

# Check logs for errors
tail -f logs/pds.log
```

### Health Checks Failing

```bash
# Test connectivity manually
curl -s http://127.0.0.1:2582/_health
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer

# View service status
./scripts/services-control.sh status

# Try with longer timeout
HEALTH_CHECK_TIMEOUT=60 ./scripts/start-all-services.sh
```

### Clear Everything and Start Fresh

```bash
# Stop all services
./scripts/services-control.sh stop all

# Remove data
rm -rf /tmp/atproto-services

# Start fresh
./scripts/start-all-services.sh
```

## Environment Variables

```bash
# Ports
export PLC_PORT=3000
export PDS_PORT=3001

# Data directory
export DATA_DIR=/tmp/my-atproto

# Log level
export PDS_LOG_LEVEL=debug
export PLC_LOG_LEVEL=debug

# Verbose output
export VERBOSE=true

# Then start
./scripts/start-all-services.sh
```

## Manual Testing

```bash
# Check if PDS is running
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .

# Check if PLC is running
curl -s http://127.0.0.1:2582/_health | jq .

# Test health
./scripts/services-control.sh test
```

## Useful Commands

```bash
# Kill all ATProto processes
pkill -f "campagnola|kaszlak"

# See which processes are using ports
netstat -an | grep -E "2582|2583"

# Monitor CPU/memory usage
watch -n 1 'ps aux | grep -E "campagnola|kaszlak"'

# Get service PIDs
pgrep -f campagnola
pgrep -f kaszlak

# Check if port is accessible
telnet localhost 2583
curl -v http://localhost:2583
```

## Error Messages & Solutions

| Error | Solution |
|-------|----------|
| `Binary not found` | Build with `xcodebuild -scheme <scheme> build` |
| `Port already in use` | Kill process with `kill -9 <PID>` or use different port |
| `Health check timeout` | Increase timeout: `HEALTH_CHECK_TIMEOUT=60` |
| `PDS can't reach PLC` | Check PLC is running: `./scripts/services-control.sh status` |
| `Database locked` | Stop services and restart: `./scripts/services-control.sh clean` |
| `Out of memory` | Check memory usage: `ps aux \| grep -E campagnola\|kaszlak` |

## Tips

- **Keep logs terminal open** - Use `./scripts/services-control.sh follow all` while developing
- **Use verbose mode** - `VERBOSE=true` helps debug issues
- **Check status first** - Always run `./scripts/services-control.sh status` if something seems wrong
- **Look at logs early** - Problems are usually logged before they become obvious
- **Start simple** - Use default ports unless you have a specific reason not to
- **Test health** - Run `./scripts/services-control.sh test` to verify everything is wired correctly

## Script Documentation

- Full guide: [SERVICE_ORCHESTRATION_GUIDE.md](./SERVICE_ORCHESTRATION_GUIDE.md)
- Setup guide: [SETUP_GUIDE.md](./SETUP_GUIDE.md)
- Deployment: [../10-tutorials/tutorial-6-deployment.md](../10-tutorials/tutorial-6-deployment.md)
