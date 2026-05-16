# Sans-I/O Architecture

Garazyk uses a Sans-I/O pattern to decouple protocol state from network side effects. This separation allows the core protocol logic to remain portable across different networking stacks (Apple's Network.framework vs. Linux BSD sockets) and simplifies deterministic testing by removing timing and I/O dependencies from state transitions.

## Core Principles

- **Pure State Machines**: Engines like `HttpProtocolSession` and `WebSocketProtocolSession` do not own sockets or timers. They are strictly reactive.
- **Data Feeding**: The driver pushes raw byte buffers into the state machine via `feedData:`.
- **Event-Driven Output**: The state machine returns structured events (e.g., `HttpRequestReceived`) or required actions (e.g., `SendBuffer`) rather than performing the I/O itself.

## Implementation Layers

### 1. Protocol State Machines
Located in `Garazyk/Sources/Network/` and `Garazyk/Sources/Sync/WebSocket/`:
- **`HttpProtocolSession`**: Manages HTTP/1.1 lifecycles using `Http1Parser`.
- **`WebSocketProtocolSession`**: Handles framing, masking, and control frames.

### 2. I/O Drivers
Located in `Garazyk/Sources/Network/HttpServer.m` and related handlers:
- **`HttpServer`**: Owns the listening socket and instantiates a `HttpProtocolSession` per connection.
- **`HttpConnectionIOCoordinator`**: Coordinates the read/write loop between the transport and the session.

### 3. Platform Transport
The `ATProtoNetworkTransport.h` interface abstracts the underlying OS networking:
- **`ATProtoNetworkTransportMac`**: Uses Apple's `Network.framework`.
- **`ATProtoNetworkTransportLinux`**: Uses BSD sockets and `dispatch_source_t`.

## Data Flow

### Inbound (Read)
1. **Platform Transport** reads bytes from the socket.
2. **Driver** passes the buffer to `[session feedData:]`.
3. **Session** emits events like `RequestReady`.
4. **Driver** dispatches the request to the XRPC layer or static handlers.

### Outbound (Write)
1. **Handler** generates a response.
2. **Driver** queues the response via the session.
3. **Session** indicates when bytes are serialized and ready.
4. **Driver** calls `[connection sendData:]` on the platform transport.

## Protocol Mechanics

### HTTP Pipelining
`Http1PipelinePolicy` tracks requests and responses to ensure the PDS respects the client's reading budget and prevents resource exhaustion from too many concurrent pipelined requests.

### WebSocket Backpressure
`WebSocketProtocolSession` monitors outbound buffer utilization. If the firehose stream exceeds thresholds, it generates backpressure events to slow down the data source.

## Related
- [HTTP Server Guide](./http-server)
- [Firehose Reliability](../08-sync-firehose/reliability-guarantees)
- [Platform Compatibility](../09-platform-compatibility/macos-vs-gnustep-boundary)
