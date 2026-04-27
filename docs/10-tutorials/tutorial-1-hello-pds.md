---
title: "Tutorial 1: Hello PDS"
---

# Tutorial 1: Hello PDS

This tutorial traces the Garazyk startup sequence and the `describeServer` discovery response. Understanding this path identifies how the codebase registers routes and handles protocol discovery.

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

---

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
