---
title: Event Ordering and Sequence Numbers
---

# Event Ordering and Sequence Numbers

The firehose maintains a strict, total ordering of all events across all repositories managed by the PDS. This ordering is enforced through monotonically increasing sequence numbers assigned to every event.

## Sequence Number Assignment

Every event (commit, identity change, or account status update) receives a unique sequence number (`seq`).

- **Initialization**: On startup, `SubscribeReposHandler` queries the database for the highest existing sequence number.
- **Assignment**: When a new event is generated, the handler increments the sequence number within a serial `syncQueue`.
- **Persistence**: The event is persisted to the `sequencer` table with its assigned number before being broadcast.

```objc
// In SubscribeReposHandler.m
- (void)ensureSequenceInitialized {
  dispatch_sync(_stateQueue, ^{
    if (self.sequenceInitialized) return;

    int64_t maxSequence = [self.serviceDatabases getMaxEventSequence:nil];
    self.session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:(NSUInteger)MAX(0, maxSequence)];
    self.sequenceInitialized = YES;
  });
}
```

## Ordering Guarantees

### Strictly Increasing
Sequence numbers always increase. If a subscriber receives an event with `seq=100`, the next event will have `seq=101` or higher. 

### No Gaps (Except During Pruning)
In a healthy stream, sequence numbers are contiguous. A gap in sequence numbers (e.g., jumping from `100` to `105`) indicates that the subscriber has missed events and should attempt to fill the gap via replay.

### Consistency Across Event Types
All event types share the same sequence space. This ensures that the interleaving of identity changes and repository commits is consistent for all subscribers.

```text
seq: 100 -> #commit (did:plc:alice)
seq: 101 -> #identity (did:plc:bob)
seq: 102 -> #commit (did:plc:alice)
```

## Cursors and Resumption

Subscribers use sequence numbers as **cursors** to resume the stream. 

- Providing `cursor=100` tells the server to replay all events starting from `seq=101`.
- If the requested cursor is higher than the server's current sequence number, the server treats it as an outdated or invalid cursor and may adjust it to the beginning of the available history.

## Performance Considerations

The use of a serial queue for sequence assignment ensures correctness but serializes event production. The PDS optimizes this by:
1. Performing heavy work (like CAR file building) before entering the serial persistence step.
2. Using a concurrent queue (`broadcastFanoutQueue`) for the final fanout to WebSocket connections.

## Related

- [Reliability Guarantees](./reliability-guarantees)
- [Event Replay](./event-replay)
- [Commit Broadcasting](./commit-broadcasting)
