---
title: Event Replay and Catch-Up Mechanisms
---

# Event Replay and Catch-Up Mechanisms

Event replay allows firehose subscribers to catch up on missed history after a disconnection or when bootstrapping a new view of the network.

## Replay Flow

When a client connects with a `cursor` parameter, the `SubscribeReposHandler` validates the requested sequence number and begins replaying events from that point.

1. **Validation**: The server checks if the cursor is within the available history window.
2. **Adjustment**: If the cursor is too old (outdated) or ahead of the server (future), the server sends an `info` event and adjusts the starting point.
3. **Backfill**: The server fetches historical events in batches from `PDSServiceDatabases`.
4. **Transition**: Once the backlog is cleared, the connection seamlessly joins the live broadcast stream.

## Implementation Details

### Replay Window Limits

The PDS limits how many events can be replayed to prevent resource exhaustion.

- **Default Limit**: 10,000 events (`kSubscribeReposMaxReplayEventsDefault`).
- **Outdated Cursors**: If a client requests a sequence older than the current window, the server adjusts it to the oldest available sequence and sends an `OutdatedCursor` info event.

### Batch Fetching

Events are retrieved from the database in batches (default size: 100) to minimize query overhead.

```objc
// In SubscribeReposHandler.m
NSArray<NSDictionary *> *events =
    [self.serviceDatabases getEventsSince:(int64_t)cursor
                                    limit:(NSInteger)limit
                                    error:&error];
```

### Concurrent Replay Management

To prevent multiple replaying clients from overwhelming the database, the server uses a semaphore to limit concurrent backfills (default: 3).

```objc
// In SubscribeReposHandler.m
_backfillSemaphore = dispatch_semaphore_create(3); 
```

## Cursor Positioning

### Starting from the Beginning

A client can request `cursor=0` to replay all available events in the PDS sequencer.

### Resuming after Disconnection

Clients should persist the `seq` field from the last processed event and provide it as the `cursor` on reconnection.

## Backpressure during Replay

Replay is subject to the same backpressure limits as live delivery. If the subscriber's outbound queue (16MB or 512 frames) fills during replay, the connection is terminated. This ensures that a slow client attempting to catch up does not consume excessive server memory.

## Related

- [Backpressure and Flow Control](./backpressure)
- [Firehose Rate Limiting](./firehose-rate-limiting)
- [Event Ordering](./event-ordering)
