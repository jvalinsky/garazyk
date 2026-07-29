---
title: Building the HTTP Server
description: POSIX sockets, trie-based routing, and bounded HTTP body parsing
---

Garazyk implements its HTTP server in Objective-C over POSIX sockets and
`libdispatch`. The same server code runs on macOS and Linux; platform transport
adapters provide the kernel-specific event integration.

## Socket lifecycle

The listener follows the normal TCP server sequence:

1. `socket()` creates the listener file descriptor.
2. `setsockopt()` applies options such as `SO_REUSEADDR`, which allows the
   process to rebind the listening address after a restart.
3. `bind()` assigns the local address and port.
4. `listen()` creates the kernel accept queue.
5. `accept()` returns a separate file descriptor for each client connection.

The server keeps accept and request processing off the caller's main thread.
Dispatch queues coordinate connection reads, parsing, route execution, and
writes.

## Trie-Based Routing (`HttpRouter`)

`HttpRouter` indexes handlers in a prefix tree. It splits an incoming path into
`/`-delimited components and walks one node per component. Lookup cost therefore
follows the path length rather than requiring a scan of every registered route.

```objc
[server addRoute:@"GET" path:@"/xrpc/app.bsky.actor.getProfile" handler:^(HttpRequest *req, HttpResponse *resp) {
    // The router invokes this block after matching the method and path.
    resp.statusCode = 200;
    [resp setBody:@"Profile fetched"];
}];
```

## Chunked request bodies

`HttpChunkedBodyParser` parses HTTP/1.1 `Transfer-Encoding: chunked` framing
incrementally. The parser enforces the request-body limit configured by
`Http1Parser`; malformed sizes, delimiters, or trailers fail the request.

A chunked body omits `Content-Length` and carries a hexadecimal size before each
payload segment:

```http
7\r\n
Mozilla\r\n
9\r\n
Developer\r\n
0\r\n
\r\n
```

`HttpStreamingBody` handles large-body storage separately. It starts in memory
and can spill data to a temporary file, which prevents the full upload from
occupying memory. The configured size limit still applies, so the server rejects
oversized bodies instead of accepting unbounded uploads.
