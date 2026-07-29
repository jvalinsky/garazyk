---
title: Sans-IO HTTP Architecture
description: Incremental protocol state machines separated from socket ownership
---

Garazyk's HTTP and WebSocket parsers consume byte buffers supplied by the
transport layer. They do not call `recv`, own sockets, or execute route
handlers. This separation is commonly called a Sans-IO design.

## Parser contract

`Http1Parser` represents one HTTP request with these states:

- reading the request line and headers
- reading a fixed-length body
- reading a chunked body
- complete
- error

The transport calls `feedData:` whenever bytes arrive. The method advances until
it completes a request, reaches an error, or needs more data. On completion,
`unconsumedData` preserves bytes that belong to the next pipelined request.

```objc
BOOL finished = [parser feedData:bytes];
if (finished) {
    Http1ParserError *parseError = parser.parseError;
    HttpRequest *request = parser.completedRequest;
    // Send the parser error or dispatch the completed request.
}
```

The caller owns connection timeouts, TLS, read scheduling, and socket closure.
The parser owns HTTP framing state and size checks.

## Why the boundary helps

Tests can split a request at every byte boundary and feed the fragments without
opening a socket. The same parser can also consume bytes produced by different
Darwin and Linux transport adapters.

Sans-IO does not by itself prevent a slow-client attack. The transport must
enforce header and body deadlines, limit concurrent connections, and stop
reading when downstream work applies backpressure.

## Size limits

The default `Http1Parser` limits are:

- 16 KiB for the request line and header block
- 50 MiB for the decoded request body

An oversized header produces a parser error suitable for HTTP 431. An oversized
body produces HTTP 413. Both fixed-length and chunked bodies use the body limit.

These are accepted-message limits, not proof of constant memory use. The current
chunked parser reassembles the decoded body in memory. Large streaming routes
should use `HttpStreamingBody` or another bounded sink rather than assume
incremental framing means disk-backed storage.

## State reset

After the caller has consumed a completed request and saved `unconsumedData`, it
may reset the parser for the next request on the connection. Error state should
not be reset and reused until the transport has applied the connection policy
for that error.

Keep route and authentication state outside the parser. Protocol parsers should
return structured results and stable error categories, not invoke application
services.
