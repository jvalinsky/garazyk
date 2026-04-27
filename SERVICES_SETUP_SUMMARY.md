# ATProto Services Setup

This repository provides scripts and documentation for running ATProto services (PLC and PDS).

## Tooling

### start-all-services.sh
Managed by `scripts/start-all-services.sh`, this script coordinates the PLC identity resolver and PDS main server. It handles:
- Service dependencies and startup order.
- Health checks and connectivity verification.
- Process management via PID files and signal handling.
- Structured logging.

### services-control.sh
Managed by `scripts/services-control.sh`, this utility provides commands to manage running services:
- `status`: Show service state and health.
- `stop [service]`: Terminate services.
- `restart [service]`: Restart services.
- `logs [service]`: View or follow logs.
- `test`: Run connectivity verification.

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

### 3. Monitor

```bash
./scripts/services-control.sh status
./scripts/services-control.sh follow all
```

## Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| PDS API | http://localhost:2583 | Main XRPC server |
| Admin UI | http://localhost:2583/admin | Administration interface |
| Explorer | http://localhost:2583/explore | Web explorer |
| PLC | http://127.0.0.1:2582 | Identity resolver |

## Environment Configuration

Configure services using these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| PLC_PORT | 2582 | PLC service port |
| PDS_PORT | 2583 | PDS service port |
| PDS_ISSUER | http://localhost:2583 | PDS issuer URL |
| DATA_DIR | /tmp/atproto-services | Base data directory |
| LOG_DIR | $PROJECT_ROOT/logs | Log directory |
| VERBOSE | false | Enable detailed logging |

## Troubleshooting

1. **Port Conflicts**: Check for processes using ports 2582 or 2583 with `lsof -i :PORT`.
2. **Startup Failures**: Verify binaries exist in `build/bin/` and check logs in the `logs/` directory.
3. **Health Check Failures**: Use `./scripts/services-control.sh test` to verify service connectivity.

For detailed guidance, refer to `docs/guides/SERVICE_ORCHESTRATION_GUIDE.md`.
