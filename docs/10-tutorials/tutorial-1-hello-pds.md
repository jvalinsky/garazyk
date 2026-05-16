---
title: "Tutorial 1: Hello PDS"
---

# Tutorial 1: Hello PDS

This tutorial traces the Garazyk startup sequence and the `describeServer` discovery response. This path demonstrates how the codebase loads configuration, registers routes, and exposes protocol discovery metadata.

## Learning Objectives
- Trace the PDS boot path from the CLI command to the active HTTP listener.
- Locate where `com.atproto.server.describeServer` is registered and handled.
- Verify that discovery metadata correctly reflects local configuration.

## Prerequisites
- Build `kaszlak` from the repository root.
- Install `jq` for inspecting JSON responses.
- Access to a terminal to run the server in the foreground.

## The Startup Sequence

The PDS bootstraps through the CLI. The sequence involves loading configuration, initializing the application state, and registering network routes.

### Key Implementation Files

- **`Garazyk/Sources/CLI/main.m`**: Parses CLI flags and dispatches commands.
- **`Garazyk/Sources/CLI/PDSCLIServeCommand.m`**: Initializes the server when you run `kaszlak serve`.
- **`Garazyk/Sources/App/ATProtoServiceConfiguration.m`**: Merges configuration files with environment variable overrides.
- **`Garazyk/Sources/App/PDSApplication.m`**: Acts as the composition root, managing the lifecycle of all major services.
- **`Garazyk/Sources/Network/ATProtoHttpServerBuilder.m`**: Maps XRPC methods to their respective handlers.
- **`Garazyk/Sources/Network/HttpServer.m`**: Manages the underlying TCP listener and HTTP state machine.

## Protocol Discovery: `describeServer`

The `com.atproto.server.describeServer` endpoint is usually the first request a client makes to discover a PDS's capabilities. It returns the server's DID, available handle domains, and registration policies.

### Tracing the Implementation

1. **Registration**: Open `ATProtoHttpServerBuilder.m` and find where the `describeServer` handler is attached to the XRPC dispatcher.
2. **Handling**: Trace the dispatcher to `PDSDescribeServerHandler.m`.
3. **Configuration**: Observe how the handler pulls the `issuerDid` and `availableUserDomains` from the `ATProtoServiceConfiguration` object.

## Verification

Build the server and query the discovery endpoint to confirm it reflects your local settings.

```bash
# Build and start the server
./build/bin/kaszlak serve --config ./config/examples/local.json --foreground &
PID=$!
sleep 2

# Query the discovery endpoint
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .

# Cleanup
kill $PID
```

### Success Criteria
- The request returns a `200 OK` status.
- The `did` field matches the `issuerDid` in your configuration.
- The `availableUserDomains` array contains the expected domains.

## Troubleshooting

- **Server fails to bind**: Ensure no other process is using port 2583. Use `lsof -i :2583` to check.
- **Empty discovery response**: Verify that your configuration file includes the `service` and `identity` blocks.
- **Route not found (404)**: Confirm that the server started successfully and the XRPC dispatcher isn't reporting registration errors in the logs.

## Relevant Tests
- `Garazyk/Tests/App/ATProtoServiceConfigurationTests.m`
- `Garazyk/Tests/Network/XrpcMethodRegistryTests.m`
- `Garazyk/Tests/XRPC/XrpcHandlerTests.m`

## Next Steps

1. Continue to [Tutorial 2: Accounts](./tutorial-2-accounts) to learn how users are created.
2. Read the [Request Lifecycle](../01-getting-started/request-lifecycle) for a deep dive into the network stack.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
