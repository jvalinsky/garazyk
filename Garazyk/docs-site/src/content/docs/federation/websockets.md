---
title: Upgrading to WebSockets
description: HTTP upgrade, frame validation, and subscription backpressure
---

AT Protocol subscriptions use WebSocket to carry a sequence of XRPC messages
over one long-lived connection. Garazyk uses this transport for
`com.atproto.sync.subscribeRepos`.

## HTTP upgrade

A WebSocket connection starts as an HTTP/1.1 GET request. A valid client request
includes:

- `Connection: Upgrade`
- `Upgrade: websocket`
- `Sec-WebSocket-Version: 13`
- a base64-encoded 16-byte `Sec-WebSocket-Key`

The server appends the RFC 6455 GUID to the key, hashes the result with SHA-1,
and returns its base64 encoding in `Sec-WebSocket-Accept` with status
`101 Switching Protocols`.

```objc
[response setStatusCode:101];
[response addHeader:@"Upgrade" value:@"websocket"];
[response addHeader:@"Connection" value:@"Upgrade"];
[response addHeader:@"Sec-WebSocket-Accept" value:acceptHash];
```

The handshake prevents an ordinary HTTP request from being mistaken for
WebSocket traffic. It does not authenticate the peer or encrypt the connection.
Production deployments use TLS and apply the subscription endpoint's
authorization policy separately.

## Frame rules

After the upgrade, both peers exchange WebSocket frames. The frame header
contains the final-fragment bit, opcode, masking bit, and payload length.

Garazyk handles:

- text and binary data frames
- continuation frames for fragmented messages
- ping, pong, and close control frames
- 7-bit, 16-bit, and 64-bit payload lengths subject to configured limits

Clients must mask every frame sent to the server. Servers must not mask frames
sent to clients. Control frames cannot be fragmented and have a small fixed
maximum payload. The parser rejects invalid reserved bits, opcodes, masking
direction, lengths, and fragment sequences.

```objc
for (NSUInteger index = 0; index < payloadLength; index++) {
    unmasked[index] = masked[index] ^ maskingKey[index % 4];
}
```

Implementations must check the advertised length before allocating a payload
buffer. A 64-bit length field does not authorize an unbounded message.

## XRPC subscription messages

`subscribeRepos` sends binary WebSocket messages. Each message contains an XRPC
subscription header encoded as DAG-CBOR followed by the event body. The header
identifies a normal message or an error and, for normal messages, the event
schema such as `#commit` or `#identity`.

Repository blocks are carried inside the event body. The WebSocket frame is not
itself a CAR file, and consumers must parse the XRPC envelope before
interpreting commit blocks.

## Connection health

Ping and pong frames can detect a connection that remains open locally after the
peer or network path has disappeared. The server closes connections that violate
the heartbeat policy and releases their socket and subscription state.

Network devices may impose their own idle timeouts. Reverse proxies should be
configured for long-lived HTTP/1.1 upgrades and should pass control frames
without buffering the stream.

## Backpressure

Socket writes are asynchronous, so each subscriber can accumulate pending
messages. Garazyk tracks the pending send count and byte total per
`subscribeRepos` connection. When either limit is exceeded, the handler sends
`ConsumerTooSlow` when possible and closes the connection with policy code 1008.

This is a bounded-memory policy, not a delivery guarantee. A disconnected relay
reconnects with its last durable cursor and requests replay from the event log.
