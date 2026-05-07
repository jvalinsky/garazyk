# HTTP Server

`HttpServer` is the transport boundary for Garazyk. It utilizes a Sans-I/O architecture, decoupling protocol parsing from network socket management.

## Responsibilities
The HTTP server manages the following transport-level tasks:
- **Parsing**: `HttpProtocolSession` handles HTTP/1.1 parsing and state transitions.
- **Constraints**: Enforcing request-size limits, header limits, and timing thresholds.
- **Routing**: `PDSHttpServerBuilder` maps request paths to specific route families.
- **Upgrades**: Managing WebSocket upgrade handoffs for firehose streams.
- **Serialization**: Sending responses and managing connection keep-alive behavior.

The server does not handle XRPC NSID resolution, authentication verification, or domain service coordination. These tasks are delegated to the dispatch and service layers after route selection.

## Implementation Seams
- **`HttpServer`**: Manages the socket lifecycle and connection state.
- **`PDSHttpServerBuilder`**: Configures the route registry and installation order.
- **`HttpProtocolSession`**: The pure state machine for HTTP/1.1 parsing and response queuing.

If a request fails before reaching a handler, or if transport behavior differs between HTTP and WebSocket, investigate these components.

## Related
- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)
- [XRPC Dispatch](./xrpc-dispatch)
- [Method Registry](./method-registry)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Firehose Overview](../08-sync-firehose/firehose-overview)

