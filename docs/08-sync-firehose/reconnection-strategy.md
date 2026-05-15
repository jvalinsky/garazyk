---
title: Reconnection Strategy and State Recovery
---

# Reconnection Strategy and State Recovery

Subscribers must be able to recover from network interruptions, server restarts, and disconnections. The firehose uses sequence-based cursors to allow clients to resume exactly where they left off.

## Connection Lifecycle

When a client connects to the firehose via `com.atproto.sync.subscribeRepos`, the `SubscribeReposHandler` manages the lifecycle:

1. **Upgrade:** The HTTP connection upgrades to a WebSocket.
2. **Initialization:** The handler initializes a `WebSocketConnection` and attaches it to the active pool.
3. **State Sync:** The server sends either the current repository state or a replay of missed events based on the provided cursor.

## Cursor-Based Resumption

The primary mechanism for state recovery is the `cursor` query parameter.

```
ws://pds.example.com/xrpc/com.atproto.sync.subscribeRepos?cursor=12345
```

### Server-Side Validation

The server validates the cursor before starting the stream:

- **Malformed Cursor:** If the cursor is not a non-negative integer, the server sends an `InvalidCursor` error and closes the connection.
- **Future Cursor:** If the requested sequence is ahead of the server's current sequence, it sends a `FutureCursor` error.
- **Outdated Cursor:** If the cursor is older than the server's replay buffer, the server adjusts the cursor to the oldest available event and sends an `OutdatedCursor` info event to notify the client of potential gaps.

### Recovery Strategies

- **Fresh Connection (No Cursor):** The server replays the current state of all hosted repositories by sending a `commit` event for each. This ensures the client starts with a consistent view of the world.
- **Resumption (Valid Cursor):** The server identifies the sequence gap and replays all events from the requested cursor up to the live head. Once caught up, the connection transitions to live updates.

## Replay Window Management

The PDS maintains a limited buffer of recent events for replay.

- **Maximum Replay:** By default, the server allows replaying up to 10,000 events per connection.
- **Persistence:** Events are read from the service database. If an event has been pruned or is older than the max replay limit, the cursor is considered outdated.

## Error and Info Events

The stream uses the XRPC streaming protocol to communicate metadata:

- **Error Frames:** Used for terminal conditions like `InvalidCursor` or `FutureCursor`.
- **Info Frames:** Used for non-terminal state changes, such as `OutdatedCursor` when a client resumes from a point that has been partially pruned.

## Client Responsibilities

A robust firehose client should implement these patterns:

1. **Track the Last Sequence:** Save the `seq` field from every received event.
2. **Persistent Storage:** Store the last sequence in non-volatile memory to survive client restarts.
3. **Exponential Backoff:** When disconnected, retry with increasing delays to avoid overwhelming the server during outages.
4. **Resume with Cursor:** Always include the last known sequence number as the `cursor` parameter on reconnection.
5. **Handle Gaps:** Be prepared to handle `OutdatedCursor` events by either accepting the gap or performing a full re-sync if the application requires total continuity.

## See Also

- [Event Ordering](event-ordering) — Sequence number guarantees.
- [Event Replay](event-replay) — The internal mechanics of event retrieval.
- [Reliability Guarantees](reliability-guarantees) — Delivery semantics and expectations.
- [Backpressure](backpressure) — How the server handles slow consumers.
