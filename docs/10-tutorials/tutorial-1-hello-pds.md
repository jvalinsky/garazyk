---
title: "Tutorial 1: Hello PDS"
---

# Tutorial 1: Hello PDS

## Overview

This tutorial traces the Garazyk startup sequence and the `describeServer` discovery response. That path shows how the codebase loads configuration, registers routes, and exposes protocol discovery.

**Learning Objectives:**
- Trace the PDS boot path from CLI command to HTTP listener.
- Find where `com.atproto.server.describeServer` is registered and handled.
- Verify that discovery metadata matches local configuration.

**Estimated Time:** 25-35 minutes

## Prerequisites

- XcodeGen and Xcode installed on macOS.
- `kaszlak` buildable from the repository root.
- `jq` installed for JSON inspection.

## Startup Path

The PDS bootstraps through the CLI. The sequence involves configuration loading, application initialization, and route registration.

### Core Components

| File | Responsibility |
| --- | --- |
| `Garazyk/Sources/CLI/main.m` | Parses CLI flags and dispatches commands. |
| `Garazyk/Sources/CLI/PDSCLIServeCommand.m` | Initializes the server from the `serve` command. |
| `Garazyk/Sources/App/PDSConfiguration.m` | Loads configuration and environment overrides. |
| `Garazyk/Sources/App/PDSApplication.m` | Composition root for the PDS runtime. |
| `Garazyk/Sources/Network/PDSHttpServerBuilder.m` | Registers server routes and handlers. |
| `Garazyk/Sources/Network/HttpServer.m` | Manages the HTTP listener. |

## Discovery: `describeServer`

The `com.atproto.server.describeServer` endpoint is typically the first protocol response a client requests. It reflects the PDS configuration, including the issuer DID, available domains, and registration policy.

### Trace the Endpoint
1. **Registration**: See how the route is added in `PDSHttpServerBuilder.m`.
2. **Dispatch**: Observe how the XRPC dispatcher routes the request to the handler.
3. **Configuration**: Inspect how values like the issuer and invite policy are derived from `PDSConfiguration`.

## Verification

After building and starting the server, verify the discovery route.

```bash
xcodegen generate
xcodebuild -scheme kaszlak build
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground &
PID=$!
sleep 2
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .
kill $PID
```

Check that:
- The route returns a 200 OK.
- The `did` matches your configured issuer.
- The `availableUserDomains` match your configuration.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `xcodebuild` cannot find the scheme | Run `xcodegen generate` again from the repository root. |
| `curl` cannot connect | Confirm `kaszlak serve` is still running and listening on port `2583`. |
| Discovery fields look wrong | Check `config.json`, CLI overrides, and `PDSConfiguration.m`. |

## Testing Invariants

Refer to these tests to understand the expected behavior of the boot and discovery paths:
- `Garazyk/Tests/Network/XrpcMethodRegistryTests.m`
- `Garazyk/Tests/XRPC/XrpcHandlerTests.m`
- `Garazyk/Tests/App/PDSConfigurationTests.m`

## Decision Tracking

Use `deciduous` to record your progress and findings as you explore the codebase.

```bash
deciduous add goal "Trace PDS boot path" -c 95
deciduous add action "Verified describeServer handler registration" -c 90
deciduous link <goal_id> <action_id>
```

## Next Steps

1. Continue to [Tutorial 2: Accounts](./tutorial-2-accounts).
2. Read [Request Lifecycle](../01-getting-started/request-lifecycle) for the HTTP path.

## Summary

The discovery endpoint is the smallest useful slice of the PDS runtime. If you can trace it from CLI startup to XRPC response, the rest of the server is easier to debug.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
