---
title: Firehose Overview
---

# Firehose Overview

## Overview

The firehose is September's `com.atproto.sync.subscribeRepos` stream. It is how
the server turns repository and identity changes into an ordered stream that
other consumers can follow.

The high-level responsibilities are:

- accept WebSocket subscribers
- assign and persist stream sequence numbers
- replay recent history from a cursor when possible
- deliver live DAG-CBOR frames for commit and related events

This is a streaming system, not just a socket endpoint. The ordering, replay,
and queueing rules are the interesting part.

## How The Main Runtime Exposes It

In the normal server path, the firehose is exposed on the main HTTP port.

- `PDSApplication` creates `SubscribeReposHandler` during service setup
- `PDSHttpServerBuilder` registers the WebSocket route at
  `/xrpc/com.atproto.sync.subscribeRepos`
- upgraded connections are handed directly to `SubscribeReposHandler`

That is why firehose behavior is tied to the main runtime and metrics surface,
not to a separate sidecar process.

## What The Stream Carries

The handler emits more than one kind of event. The important families are:

- commit events for repository mutations
- identity events for DID and handle changes
- account events for status changes such as takedowns
- info and error events for cursor and delivery conditions

New contributors often think only in terms of commit events, but the stream is
broader than that.

## Replay Versus Live Mode

The most important behavioral split is cursor handling:

- no cursor means the server replays current repository state, then switches to
  live delivery
- a valid cursor means the server replays persisted events after that sequence,
  then joins live delivery
- an invalid or future cursor is rejected with an error frame and connection
  close
- an outdated cursor may be adjusted forward and accompanied by an info event

That replay logic is what makes the stream operationally useful instead of
being a best-effort live feed only.

## Ordering And Persistence

`SubscribeReposHandler` serializes event production through its event queue and
persists emitted frames through `PDSServiceDatabases`.

That gives the firehose two important properties:

- a monotonically increasing sequence number within the server
- a persisted replay source for reconnecting consumers

This does not make the stream infinite-history storage. It does make it a real
sequenced service instead of a transient broadcast loop.

## Delivery Limits Matter

The firehose is not allowed to buffer unbounded output for slow consumers.

If a connection exceeds the configured pending-send thresholds, the server:

- emits a consumer-too-slow error frame
- detaches the connection
- closes it rather than letting memory grow without limit

That tradeoff is why backpressure is part of the correctness story, not just an
optimization detail.

## Format Matters Too

The server emits DAG-CBOR frames, and the client-side `Firehose` implementation
decodes those frames back into structured event objects.

That means debugging stream issues often crosses three layers:

- WebSocket connection behavior
- event sequencing and replay
- DAG-CBOR event encoding and decoding

## Related Reading

- [Deep Dive: Firehose Flow](./firehose-flow-walkthrough)
- [WebSocket Server](./websocket-server)
- [Commit Broadcasting](./commit-broadcasting)
- [Backpressure](./backpressure)
- [Event Replay](./event-replay)
