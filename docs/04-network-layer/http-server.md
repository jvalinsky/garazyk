# HTTP Server

`HttpServer` is the primary transport boundary for Garazyk. It utilizes a [Sans-I/O Architecture](./sans-io) to decouple protocol parsing from network socket management.

## Core Responsibilities

The HTTP server manages several transport-level tasks:
- **Protocol Parsing**: `HttpProtocolSession` handles HTTP/1.1 state transitions and header parsing.
- **Resource Constraints**: Enforces request size limits, header limits, and timeouts to prevent resource exhaustion.
- **Route Dispatch**: `PDSHttpServerBuilder` maps incoming request paths to route families (e.g., XRPC, OAuth).
- **Protocol Upgrades**: Manages the handoff to the [WebSocket](./sans-io) layer for firehose streams.
- **Connection Lifecycle**: Manages socket polling, data transmission, and keep-alive behavior.

The server focus is strictly on transport. It does not handle authentication, NSID resolution, or domain logic; these are delegated to the [Dispatch](./xrpc-dispatch) and [Service](../03-application-layer/services-overview) layers.

## Implementation Seams

- **`HttpServer`**: The I/O driver that manages sockets and connection states.
- **`PDSHttpServerBuilder`**: Configures the route registry and installation order during boot.
- **`HttpProtocolSession`**: A pure state machine for HTTP/1.1 parsing, independent of I/O side effects.

If a request fails before reaching a handler (e.g., a 413 Payload Too Large), investigate these transport components.

## Related
- [Sans-I/O Architecture](./sans-io)
- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [XRPC Dispatch](./xrpc-dispatch)
- [Method Registry](./method-registry)
- [DoS Protection](./dos-protection)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Firehose Overview](../08-sync-firehose/firehose-overview)
- [Documentation Map](../11-reference/documentation-map.md)

