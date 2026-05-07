# Sans-I/O Architecture

Garazyk implements protocol handling using a Sans-I/O pattern, decoupling protocol state from network side effects. This architecture ensures portability and facilitates deterministic testing.

## Core Principles
- **Pure State Machines**: Protocol engines (`HttpProtocolSession`, `WebSocketProtocolSession`) perform no I/O. They are unaware of sockets, file handles, or system timers.
- **Data Feeding**: Raw byte buffers are pushed into the state machine via `feedData:`.
- **Action/Event Queues**: The state machine returns structured events or actions for execution by a Driver.

## Implementation Layers

### 1. Protocol State Machines
Located in `Garazyk/Sources/Network/` and `Garazyk/Sources/Sync/WebSocket/`:
- **`HttpProtocolSession`**: Manages HTTP/1.1 lifecycles via `Http1Parser` and `Http1PipelinePolicy`.
- **`WebSocketProtocolSession`**: Handles WebSocket framing, masking, and control frames.

### 2. I/O Drivers
Located in `Garazyk/Sources/Network/HttpServer.m`:
- **`HttpServer`**: Owns the listening socket, instantiates `HttpProtocolSession` per connection, and executes events.
- **`WebSocketHandler`**: Drives `WebSocketProtocolSession` after an HTTP upgrade.

### 3. Platform Transport
The `PDSNetworkTransport.h` interface provides abstraction for:
- **`PDSNetworkTransportMac`**: Utilizes Apple's `Network.framework`.
- **`PDSNetworkTransportLinux`**: Utilizes BSD sockets and `dispatch_source_t`.

## Data Flow

### Inbound (Read)
1. **Platform Transport** reads bytes from the network.
2. **Driver** (`HttpServer`) passes the buffer to `[session feedData:]`.
3. **Session** emits `HttpSessionEvent` objects (e.g., `RequestReady`).
4. **Driver** invokes the corresponding logic.

### Outbound (Write)
1. **Handler** provides a response payload.
2. **Driver** passes the payload to `[session queueResponse:]`.
3. **Session** returns an action when bytes are ready for transmission.
4. **Driver** invokes `[connection sendData:]` on the platform transport.

## Protocol Mechanics

### HTTP Pipelining
`Http1PipelinePolicy` coordinates requests read against responses sent, enforcing a reading budget to prevent resource exhaustion.

### WebSocket Backpressure
`WebSocketProtocolSession` monitors outbound buffer utilization and generates `BackpressureWarning` events when thresholds are exceeded, triggering flow control for the firehose stream.

## Related
- [HTTP Server Guide](./http-server)
- [Firehose Reliability](../08-sync-firehose/reliability-guarantees)
- [macOS vs Linux Compatibility](../09-platform-compatibility/macos-vs-gnustep-boundary)
