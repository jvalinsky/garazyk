---
title: Sans-I/O Architecture
---

# Sans-I/O Architecture

The PDS and its associated servers (Syrena AppView, Zuk Relay) utilize a **Sans-I/O architecture** for core protocol handling. This design pattern decouples protocol state logic from actual network side effects, enabling high portability, deterministic testing, and extreme resilience.

## Core Principle

In a traditional network implementation, the code that parses HTTP or WebSocket frames often owns the socket, manages buffers, and handles threading. In a Sans-I/O model:

1.  **State Machines are "Pure":** Protocol engines (like `HttpProtocolSession`) do not perform any I/O. They are completely unaware of sockets, file handles, or system timers.
2.  **Explicit Data Feeding:** Raw bytes are explicitly pushed into the state machine via a `feedData:` method.
3.  **Action/Event Queues:** Instead of executing side effects, the state machine returns an array of structured "Events" or "Actions" that the caller (the Driver) must execute.

## Architectural Layers

### 1. Protocol State Machines (`Sources/Network/`, `Sources/Sync/WebSocket/`)

These objects represent the "Brains" of the protocol.

*   **`HttpProtocolSession`**: Manages the HTTP/1.1 lifecycle. It uses `Http1Parser` for segmenting bytes and `Http1PipelinePolicy` for managing request/response sequencing.
*   **`WebSocketProtocolSession`**: Manages WebSocket framing, masking, and control frames. It handles heartbeats deterministically.

### 2. I/O Drivers (`Sources/Network/HttpServer.m`)

The Driver represents the "Muscles" of the system. It handles the platform-specific heavy lifting.

*   **`HttpServer`**: Owns the listening socket. When a connection is accepted, it creates an `HttpProtocolSession`. As data arrives from the network, it feeds the session and executes the returned events (e.g., calling an XRPC handler).
*   **`WebSocketHandler`**: Acts as a bridge, driving a `WebSocketProtocolSession` after an HTTP upgrade has been completed.

### 3. Abstract Transport (`Sources/Network/PDSNetworkTransport.h`)

This layer provides a consistent interface for the Driver to interact with the underlying network, regardless of the platform.

*   **`PDSNetworkConnection`**: A protocol defining `sendData:`, `close`, and callbacks for data arrival.
*   **`PDSNetworkTransportMac`**: Implements transport using Apple's `Network.framework`.
*   **`PDSNetworkTransportLinux`**: Implements transport using BSD sockets and `dispatch_source_t`.

## Deterministic Testing

The primary benefit of Sans-I/O is **100% deterministic testing**.

### Testing the Protocol
We can test the HTTP parser by feeding it fragmented data, malformed headers, or interleaved pipelined requests without ever opening a real port:

```objc
// Pseudo-code example of a characterization test
NSData *rawRequest = [@"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
NSArray *events = [session feedData:rawRequest];
XCTAssertEqual(events.count, 1);
XCTAssertTrue([events[0] isKindOfClass:[HttpSessionEventRequestReady class]]);
```

### Heartbeat Consistency
WebSocket heartbeats are often flaky in tests due to timing. In our Sans-I/O implementation, the session accepts a `tick:now` call. The test can "fast-forward" time manually to verify that pings are sent and timeouts are triggered exactly when expected.

## Data Flow Pattern

### Inbound Path (Read)
1.  **Kernel** receives packets.
2.  **Platform Transport** (Mac/Linux) reads bytes into an `NSData` buffer.
3.  **Driver** (`HttpServer`) receives the data and calls `[session feedData:buffer]`.
4.  **Session** transitions its state and returns `HttpSessionEvent` objects.
5.  **Driver** iterates through events and dispatches business logic.

### Outbound Path (Write)
1.  **XRPC Handler** returns a result.
2.  **Driver** serializes the result and calls `[session queueResponse:...]`.
3.  **Session** returns an action indicating bytes are ready to send.
4.  **Driver** calls `[connection sendData:...]` on the platform transport.

## Specific Implementations

### HTTP Pipelining
The `Http1PipelinePolicy` tracks how many requests have been read vs. how many responses have been sent. It enforces a maximum reading budget to prevent memory exhaustion from an aggressive client.

### WebSocket Backpressure
The `WebSocketProtocolSession` calculates a "Fill Percentage" based on the outbound buffer. It generates `BackpressureWarning` events when the buffer exceeds a threshold, allowing the PDS to slow down the Firehose for that specific client.

---

## Related
- [HTTP Server Guide](./http-server)
- [Firehose Reliability](../08-sync-firehose/reliability-guarantees)
- [macOS vs Linux Compatibility](../09-platform-compatibility/macos-linux)
