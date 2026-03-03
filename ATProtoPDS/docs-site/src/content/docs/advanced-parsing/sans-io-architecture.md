---
title: Sans-IO HTTP Architecture
description: Decoupling socket reads from protocol state machines for ultimate performance and safety
---

When building a high-performance network service from scratch in C or Objective-C, a notoriously common and fatal architectural mistake is tightly coupling the protocol parsing logic with the raw POSIX socket I/O logic. 

If a parser function attempts to block and read directly from a TCP socket (`recv()`), the thread executing that function blocks until bytes arrive. In a high-concurrency environment, this means you need one thread per active connection. This synchronous design is not only memory-intensive but also deeply prone to malicious **Slow-Loris attacks** (where an attacker sends just 1 byte every 10 seconds to deliberately freeze a thread, quickly exhausting the server's thread pool).

To solve this concurrency nightmare and build a truly resilient system, `ATProtoPDS` utilizes a strict **Sans-IO Architecture** for its core network parsers, including `Http1Parser` and `WebSocketParser`. 

This architectural pattern totally abstracts network reads away from protocol semantics. The underlying protocol state machines remain purely synchronous, deterministic, easily testable without mocking sockets, and strictly bounded in memory.

## Pure State Machines (Zero Sockets)

`Http1Parser` operates purely as an isolated state machine. It has absolutely no knowledge of what a socket is, what a port is, or how to execute a network read across the OS kernel.

Instead, the low-level Grand Central Dispatch (GCD) network layer asynchronously reads bytes from the BSD socket using non-blocking `dispatch_source_t` read events (which internally wrap highly efficient kernel polling mechanisms like `kqueue`). When raw bytes arrive on a socket, the network layer merely "feeds" this raw `NSData` chunk into the parser. The parser never pulls data out; data is always pushed in.

```objc
// The network layer pushes data in synchronously on the socket's dedicated serial queue.
- (BOOL)feedData:(NSData *)data {

    // The parser appends the incoming chunk to its internal buffer
    [self.buffer appendData:data];
    
    // Attempt progressing the HTTP state machine based on the new bytes
    // This loop guarantees we parse as much data as we have available immediately.
    while (self.state != Http1ParserStateComplete && self.state != Http1ParserStateError) {
        if (self.state == Http1ParserStateReadingHeaders) {
            [self consumeHeaders];
        } else if (self.state == Http1ParserStateReadingBody) {
            [self consumeBody];
        } else if (self.state == Http1ParserStateReadingChunkedBody) {
            // Forward bytes strictly down the chain to the HttpChunkedBodyParser
            [self.chunkedBodyParser feedData:self.buffer];
        } else if (self.state == Http1ParserStateAwaitingData) {
            // Not enough data arrived to parse a full line or frame. 
            // Yield the thread gracefully until more data arrives.
            break;
        }
    }
    
    return self.state == Http1ParserStateComplete;
}
```

The parser maintains deterministic internal states (`Http1ParserStateReadingHeaders`, `Http1ParserStateReadingBody`) and explicitly yields execution immediately if there is not enough data to progress. It only returns `YES` back to the Socket Layer when a complete, semantically valid HTTP request has finally formed, which subsequently triggers the `HttpRouter` to handle the endpoint.

## Benefits of Sans-IO

1. **Extreme Testability:** You can easily write unit tests for the parser by feeding it fragmented strings of HTTP traffic (`"GET / HTTP/1.1\r\n"`, followed by `"Host: a.com\r\n\r\n"`) and asserting the parser transitions through the correct states without needing to spin up a local TCP server in your test runner.
2. **Reusability:** The identical parser can be used for TCP sockets, Unix Domain Sockets, TLS deciphered buffers, or even reading from disk, simply because it doesn't care where the bytes came from.
3. **Concurrency:** A single thread can parse data synchronously across thousands of connections in a run-loop without ever blocking on an I/O wait.

## Defending Against Memory Exhaustion (OOM)

Because `ATProtoPDS` processes potentially unbounded user payloads (such as massively chunked video blob uploads via `com.atproto.repo.uploadBlob`), the parser MUST rigidly defend against memory exhaustion attacks (`OOM` Out-Of-Memory exceptions) *before* the request reaches the routing layer or touches the SQLite database.

The `Http1Parser` instance exposes internal configuration properties initialized to brutal, unforgiving limits:
- `maxHeaderBytes = 16 * 1024` (16KB)
- `maxBodyBytes = 50 * 1024 * 1024` (50MB)

Because the parser meticulously tracks how many bytes it has accumulated in its fast buffer during the state machine execution loop:
- If a malicious client streams a 2GB, never-ending HTTP Header payload block over TCP attempting to prevent the request loop from yielding, `Http1Parser` instantly throws a fatal `413 Payload Too Large` or `431 Request Header Fields Too Large` error the *exact byte* the accumulated buffer exceeds `maxHeaderBytes`.
- The socket is aggressively and immediately terminated by the GCD network layer, brutally closing the descriptor, and gracefully saving the server's memory capacity.

By completely separating the *understanding* of the data from the *retrieval* of the data, `ATProtoPDS` builds an incredibly defensive perimeter right at the edge of the network interface.
