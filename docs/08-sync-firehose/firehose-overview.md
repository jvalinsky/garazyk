---
title: Firehose Overview
---

# Firehose Overview

The firehose (`com.atproto.sync.subscribeRepos`) provides an ordered stream of repository and identity changes. Consumers subscribe via WebSocket to receive live updates and, optionally, replay history from a specific sequence number.

## Core Responsibilities

The firehose implementation manages:
- WebSocket connection lifecycle for subscribers.
- Event sequence number assignment and persistence.
- Replay of historical events from a provided cursor.
- Live delivery of DAG-CBOR frames for commits, identity changes, and account events.

## Integration with PDS Runtime

The firehose is integrated directly into the main PDS HTTP server rather than running as a sidecar.

- `PDSApplication` initializes the `SubscribeReposHandler`.
- `PDSHttpServerBuilder` registers the route at `/xrpc/com.atproto.sync.subscribeRepos`.
- Connections are handled by `SubscribeReposHandler` and managed on dedicated dispatch queues to ensure the main server remains responsive.

## Event Types

The stream carries several families of events:
- **Commit**: Repository mutations (creations, updates, deletions).
- **Identity**: Changes to DIDs or handles.
- **Account**: Status changes like activations or takedowns.
- **Info/Error**: Metadata about the stream state, such as cursor invalidation.

## Replay and Resumption

Subscribers use the `cursor` query parameter to control where the stream starts:
- **No cursor**: The server optionally replays recent state before switching to live updates.
- **Valid cursor**: The server replays events starting after that sequence number.
- **Invalid/Future cursor**: The connection is rejected or adjusted with an `info` event.

See [Event Replay](./event-replay) for detailed logic.

## Backpressure and Reliability

The firehose enforces limits to prevent slow consumers from exhausting server memory. If a connection exceeds pending-send thresholds (default 512 frames or 16MB), the server emits a `ConsumerTooSlow` error and terminates the connection.

This makes [Backpressure](./backpressure) management a requirement for reliable consumers.

## Data Format

Events are encoded as DAG-CBOR frames. The stream consists of a header (identifying the message type) and a payload.

- [Firehose Flow Walkthrough](./firehose-flow-walkthrough)
- [WebSocket Server](./websocket-server)
- [Commit Broadcasting](./commit-broadcasting)
- [Rate Limiting](./firehose-rate-limiting)
- [Reliability Guarantees](./reliability-guarantees)

