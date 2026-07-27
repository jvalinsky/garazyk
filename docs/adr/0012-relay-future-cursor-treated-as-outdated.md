# ADR 0012 — Relay FutureCursor treated as OutdatedCursor

**Status:** Accepted
**Date:** 2026-07-26

## Context

The AT Protocol event-stream spec (`com.atproto.sync.subscribeRepos`) states that when a
client connects with a cursor higher than the server's current sequence number ("future
cursor"), the server should send an error message and close the connection.

In practice, relay clients (including indigo-based relays) cache cursors across
reconnections. When a relay restarts and its sequence resets, downstream clients reconnect
with stale cursors that are now "in the future." The spec-prescribed behavior causes these
clients to receive an error, close, reconnect with the same stale cursor, receive another
error, and loop indefinitely (indigo #1231).

## Decision

The Zuk relay treats future cursors as outdated cursors instead of closing the connection:

1. Send an `#info` frame with `name: "OutdatedCursor"` and a descriptive message.
2. Adjust the replay cursor to 0 (replay from the beginning of retained events).
3. Keep the connection open for live events.

This deviation is implemented in `SubscribeReposHandler.m` at the cursor validation step,
documented inline with a reference to this ADR.

## Consequences

- Relay-to-relay reconnection loops caused by stale cursors are eliminated.
- Clients receive a superset of events (replay from 0) rather than a connection error,
  which is safe because events are idempotent by sequence number.
- The deviation is observable: clients receive an `OutdatedCursor` info frame before
  replay, so well-behaved clients can detect and adjust.
- Strict spec compliance is sacrificed for operational stability. If the spec changes to
  recommend a graceful degradation path, this code should be updated to match.
