---
title: Commit Broadcasting
---

# Commit Broadcasting

Commit broadcasting is the process of delivering repository mutations to firehose subscribers in real-time. This ensures that downstream services (relays, AppViews, and indexers) stay synchronized with the PDS.

## The Broadcasting Pipeline

When a record is modified, the PDS initiates a broadcast through the `SubscribeReposHandler`.

1. **Notification**: The PDS triggers a `PDSRecordDidChangeNotification`.
2. **Event Creation**: `SubscribeReposHandler` captures the notification and queues a worker on its `syncQueue`.
3. **Sequencing**: A new, monotonically increasing sequence number is assigned.
4. **Encoding**: The event is formatted according to the `com.atproto.sync.subscribeRepos` lexicon and encoded into DAG-CBOR.
5. **Persistence**: The encoded frame is saved to the `sequencer` table in `PDSServiceDatabases` for future replay.
6. **Fanout**: The encoded frame is broadcast to all active WebSocket connections.

## Event Structure

A `#commit` event contains the following key fields:

| Field | Description |
|-------|-------------|
| `seq` | Monotonically increasing sequence number. |
| `repo` | DID of the repository being updated. |
| `commit` | CID of the new commit. |
| `rev` | Revision string for the commit. |
| `since` | Revision of the previous commit (null for first commit). |
| `blocks` | CAR-encoded blocks containing the commit and any new MST nodes. |
| `ops` | List of operations performed (create, update, delete) and their paths. |
| `time` | RFC3339 timestamp of the event. |

## Fanout Implementation

Broadcasting is performed asynchronously to prevent slow clients from blocking the main event loop.

```objc
// In SubscribeReposHandler.m - broadcastEventData:
dispatch_async(self.broadcastFanoutQueue, ^{
    for (WebSocketConnection *connection in snapshot) {
        [self sendEventData:eventData
            toConnectionWithBackpressureCheck:connection];
    }
});
```

The `broadcastFanoutQueue` is a concurrent queue that allows the PDS to push events to many subscribers in parallel.

## Fallback to #sync

If a commit event fails to encode (e.g., due to missing blocks), the system attempts to broadcast a `#sync` event instead. This contains the repository's current state and allows the subscriber to resynchronize without failing the entire stream.

## Related

- [Firehose Flow Walkthrough](./firehose-flow-walkthrough)
- [Backpressure and Flow Control](./backpressure)
- [Event Replay](./event-replay)
- [Firehose Overview](./firehose-overview)
