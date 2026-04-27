---
title: Setup and Installation
---

# Setup and Installation Guide

This guide describes how to build, install, and run the ATProto PDS and its dependencies.

## Prerequisites

- **macOS**: 12.0 or later.
- **Xcode**: 15.0 or later with Command Line Tools.
- **Disk Space**: Approximately 2GB for builds and dependencies.
- **Hardware**: 4GB RAM minimum (8GB recommended).

## Installation

### 1. Repository Setup
```bash
git clone https://github.com/jvalinsky/Garazyk.git
cd Garazyk
git submodule update --init --recursive
```

### 2. Build and Run
```bash
# Generate the Xcode project
xcodegen generate

# Build the PDS server
xcodebuild -scheme kaszlak build

# Start the server
./build/bin/kaszlak serve
```
The server is available by default at `http://localhost:2583`.

## Build Targets

- **kaszlak**: The primary PDS server.
- **campagnola**: The PLC identity resolver.
- **AllTests**: The integration and unit test suite.

### Configurations
- **Debug**: Includes logging, assertions, and debug symbols.
- **Release**: Enables compiler optimizations and strips symbols for deployment.

## Dependencies

The project includes or links to the following:
- **SQLite**: Embedded database engine.
- **OpenSSL**: System-provided cryptography.
- **libsecp256k1**: ECDSA operations (submodule).
- **Foundation**: Core system frameworks.

If automatic dependency resolution fails, ensure `sqlite` and `openssl` are installed via Homebrew.

## Configuration

### Environment Variables
| Variable | Description |
|----------|-------------|
| AT_PROTO_DATA_DIR | Directory for databases and blobs. |
| AT_PROTO_LOG_LEVEL | Verbosity (error, warn, info, debug). |
| AT_PROTO_PORT | Server listener port. |

### Startup Scripts
Production-ready startup is handled by:
```bash
./scripts/start_server.sh
```
Use `VERBOSE=true` for detailed startup logging.

## Database Management

The PDS uses SQLite. The server automatically initializes and migrates the schema on startup. To reset the database:
1. Terminate the server process.
2. Remove `data/pds.db`.
3. Restart the server.

## Verification

### Automated Tests
Run the following scripts to verify system health:
- `./scripts/run-tests.sh`: Executes the unit test suite.
- `./scripts/quality_gate.sh`: Runs linting and static analysis.
- `./scripts/test_endpoints.sh`: Verifies XRPC endpoint responsiveness.

### Manual Health Checks
- **Health Endpoint**: `curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer`
- **Admin UI**: `http://localhost:2583/admin`
- **Explorer**: `http://localhost:2583/explore`

## Troubleshooting

- **Xcode Errors**: Ensure `xcode-select -s` points to the correct Xcode installation.
- **Port Conflict**: Identify blocking processes with `lsof -i :2583`.
- **Missing Headers**: Run `git submodule update --init --recursive` to ensure all submodules are present.
- **Permissions**: Verify the `data/` directory is writable by the user running the server.

## Deployment Guidelines

For production environments:
1. Build in **Release** configuration.
2. Configure a reverse proxy (e.g., Nginx) for TLS termination.
3. Use a system supervisor (e.g., systemd or launchd) to manage the server process.
4. Set up periodic backups for the `data/` directory.
