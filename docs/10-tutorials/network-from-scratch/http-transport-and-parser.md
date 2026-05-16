---
title: "Part 1: HTTP Transport and Parser"
description: How Garazyk accepts connections, tracks per-connection state, and parses HTTP/1.1 request bytes
outline: deep
---

# Part 1: HTTP transport and parser

**Learning Objectives:**
- Understand the platform-specific transport abstractions for macOS and Linux.
- Trace the lifecycle of an incremental HTTP/1.1 parse.
- Identify the limits and timeouts enforced at the server layer.
- Master the relationship between `HttpServer`, `HttpConnectionState`, and `Http1Parser`.

**Estimated Time:** 40-50 minutes

## Why this exists

Before routing, auth, or XRPC semantics can matter, the runtime needs a clean
answer to three lower-level questions:

1. How do bytes arrive from the operating system?
2. How do those bytes become one `HttpRequest` instead of "some buffer"?
3. How does the server avoid stalling or overcommitting memory while waiting?

Garazyk answers those questions in three layers:

- a platform transport abstraction,
- a per-connection HTTP state object,
- and incremental parsers for headers and bodies.

## Minimal mental model

If you strip the design down to the bare idea, it looks like this:

```objc
@interface ConnectionState : NSObject
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, strong) Http1Parser *parser;
@end

- (void)onBytes:(NSData *)chunk connection:(id<ATProtoNetworkConnection>)conn {
  ConnectionState *state = [self stateForConnection:conn];
  BOOL completeOrError = [state.parser feedData:chunk];
  if (!completeOrError) {
    return;
  }

  Http1ParserError *parseError = [state.parser parseError];
  if (parseError) {
    [self sendParseError:parseError connection:conn];
    return;
  }

  HttpRequest *request = [state.parser completedRequest];
  [self dispatchRequest:request onConnection:conn];
}
```

That toy sketch captures the shape that matters:

- transport callbacks push bytes in,
- parser state stays attached to the connection,
- parsing is incremental,
- and dispatch only happens after a complete request or a terminal parse error.

## How Garazyk implements it

### 1. Platform transport stays below HTTP semantics

`ATProtoNetworkTransport` defines the byte-stream contract that `HttpServer` uses:

- listeners announce accepted connections,
- connections send and receive `NSData`,
- and state change callbacks expose readiness, failure, and cancellation.

On macOS, Garazyk uses the Network framework through
[`nw_listener_start`](https://developer.apple.com/documentation/network/nw_listener_start),
[`nw_connection_receive`](https://developer.apple.com/documentation/network/nw_connection_receive),
and
[`nw_parameters_create_secure_tcp`](https://developer.apple.com/documentation/network/nw_parameters_create_secure_tcp).
That code lives in `ATProtoNetworkTransportMac.m`.

On Linux, Garazyk uses non-blocking BSD sockets plus dispatch sources. The
implementation in `ATProtoNetworkTransportLinux.m` resolves addresses with
[`getaddrinfo(3)`](https://man7.org/linux/man-pages/man3/getaddrinfo.3.html),
creates sockets with [`socket(2)`](https://man7.org/linux/man-pages/man2/socket.2.html),
marks them non-blocking with [`fcntl(2)`](https://man7.org/linux/man-pages/man2/fcntl.2.html),
and drives readiness through `DispatchSource`.

This split is why `HttpServer` can stay ignorant of `nw_connection_t` and raw
file descriptors. It only cares about a unified connection protocol.

### 2. `HttpServer` creates a durable state object per connection

When `HttpServer` accepts a new connection, it does not parse directly out of
local variables. It attaches a `HttpConnectionState` object to the connection
inside an `NSMapTable`.

That state object owns:

- the `Http1Parser`,
- the `Http1PipelinePolicy`,
- `pendingRequests`,
- `outputQueue`,
- queue byte accounting,
- the header-start timestamp used for timeout enforcement,
- and a dedicated `transportQueue`.

This matters because Garazyk needs connection-local memory for:

- partial headers,
- partially read request bodies,
- pipelined requests that arrived before earlier responses finished,
- and response work that is still flushing back to the client.

### 3. Remote address propagation happens early

The transport layer reports `remoteAddress` for logging and rate limiting. When
`HttpServer` handles received data, it copies that address into
`Http1Parser.remoteAddress` before the request completes.

By the time `Http1Parser` builds a `HttpRequest`, the request already carries
the peer address that later layers use for:

- correlation and request logs,
- OAuth rate limiting,
- and firehose connection logging after an upgrade.

### 4. `Http1Parser` is an incremental HTTP/1.1 state machine

`Http1Parser` implements a small state enum:

- `Http1ParserStateReadingHeaders`
- `Http1ParserStateReadingBody`
- `Http1ParserStateReadingChunkedBody`
- `Http1ParserStateComplete`
- `Http1ParserStateError`

The parser accumulates incoming bytes in a `NSMutableData` buffer. It then:

1. searches for `\r\n\r\n` to find the end of the header block,
2. appends header bytes into
   [`CFHTTPMessage`](https://developer.apple.com/documentation/cfnetwork/cfhttpmessage-rg0),
3. validates framing rules from [RFC 9112](https://datatracker.ietf.org/doc/html/rfc9112),
4. and only then moves into body parsing.

The design is incremental because the socket may deliver:

- a partial start line,
- a full header block with only part of the body,
- or multiple requests back-to-back on a keep-alive connection.

### 5. Header and body limits are enforced before dispatch

The server-level constants in `HttpServer.m` define the hard limits:

- headers: `16 KB`
- bodies: `50 MB`
- header timeout: `5 seconds`

The parser and server cooperate here:

- `Http1Parser` rejects oversized headers and bodies,
- `HttpServer` tracks `headerStartTime` per connection,
- and a request that takes too long to finish its header block is cancelled
  before it reaches any handler code.

That is the repository's first line of defense against slow or malformed
clients. It also keeps higher layers from having to reason about half-formed
requests.

### 6. Chunked transfer coding gets its own parser

If `Http1Parser` sees `Transfer-Encoding: chunked`, it delegates body parsing to
`HttpChunkedBodyParser` rather than open-coding chunk handling inline.

That parser follows the chunk framing model from
[RFC 9112 Section 7.1](https://datatracker.ietf.org/doc/html/rfc9112#section-7.1):

```text
chunk-size CRLF
chunk-data CRLF
...
0 CRLF
CRLF
```

It parses incrementally because a single chunk can arrive across multiple read
callbacks. It also rejects ambiguous framing, such as a request that sends both
`Content-Length` and `Transfer-Encoding`.

### 7. Pipelining starts at parse time, not at route time

`Http1Parser` exposes `unconsumedData` after a complete request. `HttpServer`
uses that to keep parsing extra bytes already sitting in the socket buffer.

That matters for HTTP/1.1 pipelining:

- request A can already be complete,
- request B can already be partially or fully present,
- and the server can queue B without losing byte boundaries.

The routing and response consequences of that design land in Part 2, but the
foundation is here: the parser must retain and surface unconsumed bytes cleanly.

## Relevant data structures

| Structure | Location | What it holds |
| --- | --- | --- |
| `HttpConnectionState` | `HttpServer.m` | Parser, pipeline policy, pending requests, queued responses, timing data, and per-connection transport queue |
| `Http1ParserState` | `Http1Parser.h` | Header, fixed-length body, chunked body, complete, and error states |
| `NSMutableData *buffer` | `Http1Parser.m` | Raw bytes not yet fully consumed into one request |
| `CFHTTPMessageRef message` | `Http1Parser.m` | Apple parser object used to interpret the request line and headers |
| `HttpChunkedBodyParser.outputData` | `HttpChunkedBodyParser.m` | Reassembled entity body after chunk decoding |
| `HttpChunkedBodyParser.workingBuffer` | `HttpChunkedBodyParser.m` | Bytes still being interpreted as chunk-size lines, chunk data, or final CRLF |

## Concurrency and failure modes

### Serial transport queues protect connection-local ordering

Each accepted connection gets a dedicated serial `transportQueue`. That means
reads, parser advancement, and follow-up receive scheduling stay ordered per
connection even while the server as a whole handles many clients concurrently.

### The parser fails fast on framing errors

If parsing fails, `HttpServer` turns the parser error into an HTTP response and
does not dispatch to any route handler. Important cases include:

- oversized header block,
- oversized body,
- `Content-Length` plus `Transfer-Encoding` together,
- unsupported transfer encoding,
- missing length information for methods that require a body,
- malformed chunk sizes or missing CRLF terminators.

### Timeouts are enforced before handler code runs

`HttpServer` cancels a connection whose header parse exceeds the server timeout.
That is separate from application-level timeouts. It protects the connection
slot itself, not just a route handler.

### The transport split creates platform-specific debugging paths

If a connection never reaches `HttpServer`, start in the transport layer:

- macOS: Network framework listener/connection state callbacks
- Linux: address resolution, non-blocking connect setup, dispatch-source read
  and write handlers

If the connection reaches `HttpServer` but the request never materializes, start
in `Http1Parser` and `HttpChunkedBodyParser`.

## Tests that prove it

Start with these test classes:

- `ATProtoNetworkTransportTests`
- `ATProtoNetworkTransportLinuxTests`
- `Http1ParserTests`
- `HttpChunkedBodyParserTests`

These prove the exact mechanics this part described:

- listener and connection readiness,
- incremental request parsing,
- oversized header and body rejection,
- pipelined-data retention,
- and chunked-body reassembly and error handling.

## Sources and further reading

### Specs and platform APIs

- [RFC 9112: HTTP/1.1](https://datatracker.ietf.org/doc/html/rfc9112)
- [CFHTTPMessage](https://developer.apple.com/documentation/cfnetwork/cfhttpmessage-rg0)
- [Network framework `nw_connection_receive`](https://developer.apple.com/documentation/network/nw_connection_receive)
- [Network framework `nw_listener_start`](https://developer.apple.com/documentation/network/nw_listener_start)
- [Network framework `nw_parameters_create_secure_tcp`](https://developer.apple.com/documentation/network/nw_parameters_create_secure_tcp)
- [DispatchSource](https://developer.apple.com/documentation/dispatch/dispatchsource)
- [dispatch_semaphore_create](https://developer.apple.com/documentation/dispatch/dispatch_semaphore_create)
- [getaddrinfo(3)](https://man7.org/linux/man-pages/man3/getaddrinfo.3.html)
- [socket(2)](https://man7.org/linux/man-pages/man2/socket.2.html)
- [fcntl(2)](https://man7.org/linux/man-pages/man2/fcntl.2.html)

### Garazyk reference pages

- [HTTP Server](../../04-network-layer/http-server)
- [Platform-Specific Network Transport](../../09-platform-compatibility/network-transport)
- [HTTP Request and Route Pipeline](../../04-network-layer/http-request-and-route-pipeline)

## Next step

Continue to [Part 2: Routing, pipelining, and responses](./http-routing-pipelining-and-responses).

## Related

- [Documentation Map](../../11-reference/documentation-map.md)
- [Contributor Guide](../../index.md)
- [Repository Documentation Index](../../repo-index/index.md)

