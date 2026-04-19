---
title: WebSocket Server
description: Reference page for Garazyk's production WebSocket upgrade path and the firehose connection runtime
outline: deep
---

# WebSocket Server

## Overview

Garazyk's firehose does **not** primarily run through a standalone listener in
the normal server path. The production path is:

```text
HttpServer -> WebSocketUpgradeHandler -> WebSocketConnection -> SubscribeReposHandler
```

That means the firehose begins life as an ordinary HTTP request on the main port
and only becomes a WebSocket after the upgrade succeeds.

## Current production path

In the current runtime:

- `PDSHttpServerBuilder` registers
  `/xrpc/com.atproto.sync.subscribeRepos` as a WebSocket route on the main HTTP
  server
- `HttpServer` detects the route and validates the upgrade request
- `WebSocketUpgradeHandler` computes `Sec-WebSocket-Accept` and prepares the
  `101 Switching Protocols` response
- `SubscribeReposHandler` accepts the upgraded connection and sends initial
  replay or current-state data

```mermaid
flowchart TD
  Request["GET /xrpc/com.atproto.sync.subscribeRepos"] --> HTTP["HttpServer"]
  HTTP --> Upgrade["WebSocketUpgradeHandler"]
  Upgrade --> Switch["101 Switching Protocols"]
  Switch --> Conn["WebSocketConnection"]
  Conn --> Handler["SubscribeReposHandler"]
  Handler --> Replay["Replay or current-state send"]
  Replay --> Live["Live firehose stream"]
```

If you are debugging today's implementation, start in this path first.

## Legacy standalone server

The repository still contains `Garazyk/Sources/Sync/WebSocketServer.{h,m}`.
That class owns a separate listener based on Network.framework and still exists
for compatibility and older test seams.

That is **not** the primary production architecture anymore. The current
`SubscribeReposHandler` header marks the standalone listener path as deprecated.

Use the legacy class only when:

- a compatibility test explicitly exercises it,
- you are auditing historical behavior,
- or you are comparing old and new connection-acceptance paths.

## What this layer owns

Treat the WebSocket layer as the answer to these questions:

- did the upgrade request satisfy RFC 6455 handshake requirements,
- how are frames encoded and decoded on the socket,
- how are ping/pong and close frames handled,
- when is a connection considered too slow or dead,
- and how does an upgraded socket become a firehose subscriber.

These are transport and framing concerns. They are not the same as event replay
or commit sequencing semantics.

## Main runtime seams

Start with these files:

- `Garazyk/Sources/Network/WebSocketUpgradeHandler.m`
- `Garazyk/Sources/Sync/WebSocketConnection.m`
- `Garazyk/Sources/Sync/WebSocketCodec.m`
- `Garazyk/Sources/Sync/WebSocketHeartbeatPolicy.m`
- `Garazyk/Sources/Sync/SubscribeReposHandler.m`

Read `WebSocketServer.m` only after that if you need the deprecated standalone
listener path.

## Advanced internals track

If you want the full implementation walkthrough, use the tutorial subguide:

- [Subguide: HTTP + WebSocket from Scratch](../10-tutorials/network-from-scratch/)
- [Part 3: WebSocket Upgrade, Codec, and Firehose](../10-tutorials/network-from-scratch/websocket-upgrade-codec-and-firehose)

For the HTTP setup that precedes the upgrade, read:

- [Part 1: HTTP Transport and Parser](../10-tutorials/network-from-scratch/http-transport-and-parser)
- [Part 2: Routing, Pipelining, and Responses](../10-tutorials/network-from-scratch/http-routing-pipelining-and-responses)

## Related reading

- [Firehose Overview](./firehose-overview)
- [Backpressure](./backpressure)
- [Event Replay](./event-replay)
- [HTTP Server](../04-network-layer/http-server)
- [HTTP Request and Route Pipeline](../04-network-layer/http-request-and-route-pipeline)

## Sources

- [RFC 6455: The WebSocket Protocol](https://datatracker.ietf.org/doc/html/rfc6455)
- [Network framework `nw_connection_receive`](https://developer.apple.com/documentation/network/nw_connection_receive)
- [Network framework `nw_listener_start`](https://developer.apple.com/documentation/network/nw_listener_start)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n