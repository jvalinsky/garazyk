---
title: Firehose Overview
---

# Firehose Overview

## Overview

The firehose (`com.atproto.sync.subscribeRepos`) turns repository and identity changes into an ordered stream for consumers.

The high-level responsibilities are:

- accept WebSocket subscribers
- assign and persist stream sequence numbers
- replay recent history from a cursor when possible
- deliver live DAG-CBOR frames for commit and related events

This is a streaming system; ordering, replay, and queueing rules are critical.

## How The Main Runtime Exposes It

In the normal server path, the firehose is exposed on the main HTTP port.

- `PDSApplication` creates `SubscribeReposHandler` during service setup
- `PDSHttpServerBuilder` registers the WebSocket route at
  `/xrpc/com.atproto.sync.subscribeRepos`
- upgraded connections are handed directly to `SubscribeReposHandler`

This ties firehose behavior to the main runtime and metrics surface, rather than a separate sidecar process.

## What The Stream Carries

The handler emits more than one kind of event. The important families are:

- commit events for repository mutations
- identity events for DID and handle changes
- account events for status changes such as takedowns
- info and error events for cursor and delivery conditions

The stream includes more than just commit events.

## Replay Versus Live Mode

Cursor handling defines replay behavior:

- no cursor means the server replays current repository state, then switches to
  live delivery
- a valid cursor means the server replays persisted events after that sequence,
  then joins live delivery
- an invalid or future cursor is rejected with an error frame and connection
  close
- an outdated cursor may be adjusted forward and accompanied by an info event

This replay logic makes the stream operationally useful.

## Ordering And Persistence

`SubscribeReposHandler` serializes event production through its event queue and
persists emitted frames through `PDSServiceDatabases`.

That gives the firehose two important properties:

- a monotonically increasing sequence number within the server
- a persisted replay source for reconnecting consumers

This makes it a sequenced service, though not infinite-history storage.

## Delivery Limits Matter

The firehose is not allowed to buffer unbounded output for slow consumers.

If a connection exceeds the configured pending-send thresholds, the server:

- emits a consumer-too-slow error frame
- detaches the connection
- closes it rather than letting memory grow without limit

This tradeoff makes backpressure a correctness requirement, not just an optimization.

## Format Matters Too

The server emits DAG-CBOR frames, and the client-side `Firehose` implementation
decodes those frames back into structured event objects.

Debugging stream issues often involves three layers:

- WebSocket connection behavior
- event sequencing and replay
- DAG-CBOR event encoding and decoding

## Related Reading

- [Deep Dive: Firehose Flow](./firehose-flow-walkthrough)
- [WebSocket Server](./websocket-server)
- [Commit Broadcasting](./commit-broadcasting)
- [Backpressure](./backpressure)
- [Event Replay](./event-replay)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

