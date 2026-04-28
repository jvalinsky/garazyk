---
title: Sans-I/O Architecture
---

# Sans-I/O Architecture

Garazyk uses a **Sans-I/O architecture** for protocol handling in the PDS and associated servers (Syrena, Zuk). This pattern decouples protocol logic from network side effects, supporting portability and deterministic testing.

## Principles

Traditional network implementations often combine frame parsing with socket ownership and buffer management. Sans-I/O separates these concerns:

1.  **Pure State Machines:** Protocol engines like `HttpProtocolSession` do not perform I/O. They are unaware of sockets, file handles, or system timers.
2.  **Explicit Data Feeding:** Raw bytes are pushed into the state machine via `feedData:`.
3.  **Action/Event Queues:** The state machine returns an array of structured events or actions that the caller (the Driver) executes.

## Architectural Layers

### 1. Protocol State Machines (`Sources/Network/`, `Sources/Sync/WebSocket/`)

These objects manage protocol logic:

*   **`HttpProtocolSession`**: Manages the HTTP/1.1 lifecycle. It uses `Http1Parser` for segmenting bytes and `Http1PipelinePolicy` for request/response sequencing.
*   **`WebSocketProtocolSession`**: Manages WebSocket framing, masking, and control frames, including heartbeats.

### 2. I/O Drivers (`Sources/Network/HttpServer.m`)

The Driver handles platform-specific implementation:

*   **`HttpServer`**: Owns the listening socket and creates an `HttpProtocolSession` for each connection. It feeds data to the session and executes the returned events.
*   **`WebSocketHandler`**: Drives a `WebSocketProtocolSession` after an HTTP upgrade.

### 3. Abstract Transport (`Sources/Network/PDSNetworkTransport.h`)

This layer provides a consistent interface for the Driver:

*   **`PDSNetworkConnection`**: Defines `sendData:`, `close`, and data arrival callbacks.
*   **`PDSNetworkTransportMac`**: Uses Apple's `Network.framework`.
*   **`PDSNetworkTransportLinux`**: Uses BSD sockets and `dispatch_source_t`.

## Deterministic Testing

Sans-I/O enables deterministic testing without opening network ports.

### Protocol Testing
The HTTP parser can be tested by feeding it fragmented data or malformed headers directly:

```objc
// Pseudo-code example of a characterization test
NSData *rawRequest = [@"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
NSArray *events = [session feedData:rawRequest];
XCTAssertEqual(events.count, 1);
XCTAssertTrue([events[0] isKindOfClass:[HttpSessionEventRequestReady class]]);
```

### Heartbeat Consistency
Tests verify WebSocket heartbeats by calling `tick:now` and "fast-forwarding" time to check pings and timeouts.

## Data Flow

### Inbound Path (Read)
1.  **Kernel** receives packets.
2.  **Platform Transport** reads bytes into an `NSData` buffer.
3.  **Driver** (`HttpServer`) calls `[session feedData:buffer]`.
4.  **Session** returns `HttpSessionEvent` objects.
5.  **Driver** executes business logic based on events.

### Outbound Path (Write)
1.  **XRPC Handler** returns a result.
2.  **Driver** serializes the result and calls `[session queueResponse:...]`.
3.  **Session** returns an action when bytes are ready.
4.  **Driver** calls `[connection sendData:...]` on the platform transport.

## Implementations

### HTTP Pipelining
`Http1PipelinePolicy` tracks requests read versus responses sent, enforcing a reading budget to prevent memory exhaustion.

### WebSocket Backpressure
`WebSocketProtocolSession` calculates a fill percentage for the outbound buffer. It generates `BackpressureWarning` events when the buffer exceeds a threshold, allowing the PDS to slow down the firehose for that client.

---

## Related
- [HTTP Server Guide](./http-server)
- [Firehose Reliability](../08-sync-firehose/reliability-guarantees)
- [macOS vs Linux Compatibility](../09-platform-compatibility/macos-linux)
