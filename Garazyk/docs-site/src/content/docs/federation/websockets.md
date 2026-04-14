---
title: Upgrading to WebSockets
description: HTTP 101 Handshake, Framing, and the Real-time Backbone
---

Realtime updates are the beating heart of decentralized social networks. When you like a post, reply to a thread, or follow a new user on Bluesky, your Personal Data Server (PDS) must immediately broadcast that event to Relays (BGS) and AppViews. This allows your actions to appear on your followers' timelines almost instantly, no matter which PDS they reside on.

Since traditional HTTP operates on a strictly request-response paradigm—which introduces massive latency and bandwidth overhead when continuously polling for updates—achieving this realtime sync at a planetary scale requires opening a persistent, bi-directional protocol: **WebSockets** (RFC 6455). In the AT Protocol, WebSockets serve as the high-throughput backbone of the "firehose," continuously streaming cryptographic repository updates across the federated network.

## The HTTP Upgrade Handshake

Every WebSocket connection on the internet surprisingly starts its life as a standard HTTP/1.1 `GET` request. It relies on the HTTP `Upgrade` mechanism to seamlessly transition an existing TCP connection from text-based HTTP to the binary WebSocket protocol.

In `ATProtoPDS`, when the `HttpRouter` detects an incoming request to `/xrpc/com.atproto.sync.subscribeRepos` (the primary firehose endpoint), it forwards the underlying socket to the `SubscribeReposHandler`. Here, the server rigorously inspects the HTTP headers. If it sees `Connection: Upgrade` and `Upgrade: websocket`, it initiates the cryptographic handshake required by the specification:

1. **Extraction:** It extracts the client's `Sec-WebSocket-Key` header, which contains a base64-encoded, randomly generated 16-byte nonce.
2. **Concatenation:** It concatenates this string with a globally standardized "magic" UUID defined in RFC 6455: `258EAFA5-E914-47DA-95CA-C5AB0DC85B11`.
3. **Hashing:** It calculates the SHA-1 hash of the newly concatenated string and encodes the binary result in `base64`.
4. **Acceptance:** It responds with an `HTTP/1.1 101 Switching Protocols` status code and passes the hash back as the `Sec-WebSocket-Accept` header.

> [!NOTE]
> The handshake does not provide security or encryption (that is handled exclusively by TLS/HTTPS). It simply proves to the server that the client genuinely understands the WebSocket protocol and isn't a confused HTTP proxy or an older browser accidentally sending malformed data.

```objc
// The moment these headers are written to the socket, the HttpRouter 
// permanently relinquishes control of the file descriptor. 
// It is handed over to the dedicated WebSocket implementation.
[response setStatusCode:101];
[response addHeader:@"Upgrade" value:@"websocket"];
[response addHeader:@"Connection" value:@"Upgrade"];
[response addHeader:@"Sec-WebSocket-Accept" value:acceptHash];
```

## Binary and Text Framing

Once the `101 Protocol Switch` handshake is complete, the client and server no longer exchange HTTP requests, response lines, or headers. Instead, they exchange raw **Frames**. Unlike Server-Sent Events (SSE) which rely on newline-delimited text, WebSockets stream discrete chunks of binary or text data, strictly prefixed by a minimal bit-header.

This lightweight framing ensures minimal overhead, making it ideal for high-throughput firehose connections. The bit-header encodes critical metadata for parser state machines:

- **The Opcode (4 bits):** Determines the frame type. A value of `%x1` indicates Text, `%x2` indicates Binary. Control frames like Ping (`%x9`), Pong (`%xA`), or Close (`%x8`) manage connection health.
- **The Payload Length:** Indicates the size of the data payload. It uses a variable-length encoding (7 bits, 16 bits, or 64 bits) to remain perfectly compact for small messages while supporting massive payloads up to exabytes.
- **The Masking Key:** Browsers mandate a 4-byte mask for all *client-to-server* frames to prevent intermediaries (like transparent proxy servers) from cache-poisoning the payload by tricking them into reading the payload as if it were a new HTTP request.

Because `ATProtoPDS` implements WebSockets natively in Objective-C without heavy external networking libraries, the internal WebSocket implementation must manually unmask incoming client frames. This is done using an `XOR` operation byte-by-byte against the provided Masking Key.

```objc
// A simplified visualization of the unmasking loop inside the WebSocket implementation
for (NSUInteger i = 0; i < payloadLength; i++) {
    unmaskedData[i] = maskedData[i] ^ maskingKey[i % 4];
}
```

## Connection Health (Ping/Pong)

Long-lived TCP connections are notoriously fragile. Firewalls, NAT routers, or mobile carriers aggressively drop idle connections silently. 

To combat this, the WebSocket specification includes built-in `Ping` and `Pong` control frames. `ATProtoPDS` periodically dispatches `Ping` frames downstream. If a Relay or client fails to reply with a matching `Pong` frame within a configured timeout window, the server safely assumes the connection is dead (a "half-open" connection) and tears down the socket, recovering critical file descriptors and memory resources.

## Broadcasting the Firehose (CAR Files)

In the context of the AT Protocol's `subscribeRepos` endpoint, the server exclusively sends **Binary Frames** (`%x2`).

Whenever a user mutates their repository (e.g., creates a post), the PDS packages the commit and its associated blocks into a standard CAR (Content Addressable aRchives) file. Instead of encoding this binary data into inefficient formats like `base64` strings inside JSON arrays, the PDS aggressively formats the raw CAR bytes as a single WebSocket binary frame and streams it directly into the remote Relay's TCP socket.

This approach minimizes serialization overhead and zero-copy buffers allow Relays to ingest massive amounts of data efficiently. However, it also means the server must carefully manage backpressure.

### Managing Backpressure

If a Relay consumes data slower than the PDS produces it, the operating system's kernel socket buffers will fill up. `ATProtoPDS` tightly monitors these buffer limits. If the pending outbound bytes exceed a configured threshold (e.g., waiting on TCP ACKs from a slow Relay), it gracefully yields a `ConsumerTooSlow` Close frame and violently drops the subscriber. 

This protective mechanism ensures that a few misconfigured or slow Relays cannot cause memory exhaustion (`OOM`) across the entire PDS, preserving the integrity of the broader network.

## Summary

WebSockets provide the essential realtime plumbing for the AT Protocol federation. By starting as a standard HTTP connection, they seamlessly traverse most corporate firewalls and reverse proxies. Once upgraded via the RFC 6455 handshake, the protocol strips away HTTP bloat, relying on highly efficient binary framing to blast raw cryptographic CAR files across the globe. Understanding this transition—from the `101 Switching Protocols` handshake to raw binary XOR unmasking—is crucial for scaling up a performant and standards-compliant Personal Data Server.