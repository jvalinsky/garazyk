---
title: Building the HTTP Server
description: Metal-level POSIX socket programming, Trie-based $O(L)$ routing, and high-performance chunked encoding
---

A federated Personal Data Server (PDS) in the AT Protocol network must securely ingest gigabytes of unpredictable external data and reliably host tens of thousands of decentralized user repositories simultaneously. 

Instead of relying on a massively complex, high-level third-party web framework (like Node's Express or Swift's Vapor) that might critically obscure internal performance metrics, bloat binary sizes, or dangerously inflate memory footprints, the `ATProtoPDS` HTTP logic is powered identically by a custom, highly-optimized, completely non-blocking HTTP server written directly in Objective-C.

## Socket Programming on the Metal

The foundation of the entire HTTP engine is built directly on standard deeply-tested POSIX sockets, specifically optimized for high-throughput scaling natively across both macOS (`kqueue`) and Linux (`epoll`) kernels via `libdispatch`.

1. **`socket()`**: The system instructs the kernel to physically allocate a network file descriptor representing an endpoint for communication.
2. **`setsockopt()`**: We rigidly enforce configurations like `SO_REUSEADDR` to ensure incredibly rapid server reboots without the OS artificially holding on to port bindings in a `TIME_WAIT` zombie state.
3. **`bind()`**: The kernel maps the abstract socket strictly to a specific local port (e.g., 80 or 443) and memory address.
4. **`listen()`**: The system prepares the kernel's network buffer to actively queue and accept inbound TCP network connections from the wider internet.
5. **`accept()`**: The kernel permanently yields a brand new, discrete client file descriptor representing the physical connection between the PDS and the remote Relay or user App.

For each newly accepted client connection, we critically **do not** block the main server runloop thread. Instead, we instantly hand the raw socket file descriptor off to a global concurrent Grand Central Dispatch (GCD) queue for fully asynchronous, high-parallelism parsing and response handling. 

## Trie-Based Routing (`HttpRouter`)

When a complex network request like `GET /xrpc/com.atproto.sync.getBlob` arrives over the wire, the internal server needs to determine the corresponding Objective-C business logic block handler as fast as physically possible. 

In many popular web frameworks (like Ruby on Rails or older Express), routing engines linearly iterate through a massive, flat array of complex Regular Expressions to find a route match. This evaluates mathematically to $O(N)$ time complexity, meaning the routing engine heavily degrades and slows down proportionally as the API inevitably grows over months of development.

Instead of Regex, `ATProtoPDS` structurally utilizes a highly-optimized **Trie (Prefix Tree)** data structure. The incoming URL path string is physically split by `/` components. Every single discrete string segment becomes a physical node mapped inside the Trie memory map. 

This advanced structural approach grants phenomenal $O(L)$ physical routing complexity, where $L$ is merely the number of path segments (typically 2 to 4 in ATProto XRPC requests). This mathematical guarantee dictates that the HTTP routing speed is completely unaffected by the total number of thousands of endpoints optionally registered on the massive server.

```objc
// The HttpRouter natively allows registering dynamic path parameters (e.g., extracting the :did)
[server addRoute:@"GET" path:@"/xrpc/app.bsky.actor.getProfile" handler:^(HttpRequest *req, HttpResponse *resp) {
    // 1. Controller business logic safely executes immediately after the lightning-fast O(L) trie-traversal
    // 2. We can freely fetch the extracted URL parameters from `req.params[@"did"]`
    resp.statusCode = 200;
    [resp setBody:@"Profile Fetched Successfully"];
}];
```

## Handling Chunked Encoding without Memory Bloat

Architecturally, a PDS must regularly handle massive blob ingestion. Uploading a massive 50MB 4K video using the standard `com.atproto.repo.uploadBlob` lexicon cannot physically block a thread synchronously over a 30-minute slow mobile connection, nor can the PDS architecture physically afford to allow the server kernel to cache massive 50MB payloads arbitrarily in RAM waiting for the upload to gracefully finish. 

To solve this fatal memory leak vector, `ATProtoPDS` rigorously, natively parses HTTP/1.1 `Transfer-Encoding: chunked` streams via the custom `HttpChunkedBodyParser`.

A chunked HTTP payload legally streams data blindly in pieces, completely omitting a `Content-Length` header, looking vaguely like this on the wire:
```http
// Hexadecimal chunk length
7\r\n
// Payload fragment
Mozilla\r\n
// Next length
9\r\n
// Next payload fragment
Developer\r\n
// The mathematical ZERO terminator
0\r\n
\r\n
```

We parse the tiny hexadecimal length integer of each arriving chunk completely out of the socket stream byte-by-byte (averting massive, incredibly slow buffer string-splits). We strictly extract the precisely-sized payload asynchronously exactly as it arrives off the `NSData` buffer, blindly write those raw binary bytes safely and incrementally directly to a temporary `tmp` file on the SSD disk, and instantly yield execution control right back to the GCD runloop. 

Once the final, definitive `0\r\n\r\n` terminator socket bytes legally arrive, the fully-assembled, entirely on-disk filepath string is eagerly forwarded to the application routing handler. This allows `ATProtoPDS` to natively support infinite $O(\infty)$ sized blob uploads while utilizing strictly $O(1)$ constant, unmoving RAM overhead.
