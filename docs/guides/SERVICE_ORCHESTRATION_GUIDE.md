---
title: Service Orchestration and Management
description: Guide to running and managing ATProto PDS and supporting services
---

# Service Orchestration Guide

This guide describes how to run and manage the ATProto stack, including the PLC identity resolver, PDS (personal data server), and Admin UI.

## Architecture

The ATProto stack consists of several interconnected services:

```
┌───────────────────────────┐
│       Clients / UI        │
└─────────────┬─────────────┘
              │
              ▼
┌───────────────────────────┐
│    ATProto PDS (kaszlak)  │
├───────────────────────────┤
│ • Port 2583               │
│ • XRPC Server             │
│ • Admin UI (/admin)       │
└─────────────┬─────────────┘
              │
              ▼ (DID resolution)
┌───────────────────────────┐
│  PLC Directory (campagnola)│
├───────────────────────────┤
│ • Port 2582               │
│ • Identity verification   │
│ • Service discovery       │
└───────────────────────────┘
```

### Dependencies
- **PLC (campagnola)**: Must start before the PDS to handle identity resolution.
- **PDS (kaszlak)**: Depends on the PLC for identity operations.

## Quick Start

### 1. Build Services
```bash
xcodegen generate
xcodebuild -scheme campagnola build
xcodebuild -scheme kaszlak build
```

### 2. Start Services
```bash
./scripts/start-all-services.sh
```

The startup script performs the following:
1. Verifies binaries and required directories.
2. Terminates any existing processes on ports 2582 and 2583.
3. Starts the PLC service and waits for health checks to pass.
4. Starts the PDS service and verifies connectivity to the PLC.

## Orchestration Tools

### start-all-services.sh
Coordinates the complete service stack.

**Common Options:**
| Option | Description |
|--------|-------------|
| `--skip-plc` | Skip PLC startup (if already running). |
| `--skip-pds` | Skip PDS startup. |
| `--plc-port PORT` | PLC port (default: 2582). |
| `--pds-port PORT` | PDS port (default: 2583). |
| `--data-dir PATH` | Base data directory (default: `/tmp/atproto-services`). |
| `--pds-issuer URL` | PDS issuer URL (default: `http://localhost:2583`). |
| `--verbose` | Enable detailed logging. |

### services-control.sh
Provides lifecycle management for running services.

| Command | Description |
|---------|-------------|
| `status` | Show service health and PIDs. |
| `stop [service]` | Stop PDS, PLC, or both. |
| `restart [service]` | Restart services. |
| `logs [service]` | View or follow service logs. |
| `test` | Run connectivity verification. |
| `clean` | Stop all services and remove PID files. |

## Configuration

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| PLC_PORT | 2582 | PLC service port. |
| PDS_PORT | 2583 | PDS service port. |
| DATA_DIR | /tmp/atproto-services | Base data directory. |
| LOG_DIR | $PROJECT_ROOT/logs | Log directory. |
| PDS_LOG_LEVEL | info | PDS log verbosity. |
| HEALTH_CHECK_TIMEOUT | 30 | Startup timeout in seconds. |

## Verification and Monitoring

### Manual Health Checks
- **PLC**: `curl -s http://127.0.0.1:2582/_health`
- **PDS**: `curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer`
- **Admin UI**: `curl -I http://localhost:2583/admin`

### Logging
Logs are stored in the `logs/` directory. Use `./scripts/services-control.sh follow all` to monitor both services in real-time.

## Troubleshooting

- **Binaries missing**: Ensure `xcodebuild` completed successfully and check `build/bin/`.
- **Port conflicts**: Use `lsof -i :2582` or `lsof -i :2583` to find processes blocking ports.
- **Connectivity**: Verify the PDS can reach the PLC at `http://127.0.0.1:2582`.
- **Database errors**: Reset the local environment by running `./scripts/services-control.sh clean` and removing the data directory.

## Production Guidelines

1. **Systemd (Linux)**: Configure a service unit to manage `start-all-services.sh`.
2. **Log Rotation**: Use `logrotate` to manage files in the `logs/` directory.
3. **Backup**: Periodically back up the data directory (SQLite databases and blobs).
4. **Reverse Proxy**: Use Nginx or a similar proxy for TLS termination and header management.
