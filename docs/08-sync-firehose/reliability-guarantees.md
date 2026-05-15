---
title: Reliability Guarantees and Delivery Semantics
---

# Reliability Guarantees and Delivery Semantics

The firehose provides specific guarantees for event delivery to ensure that downstream consumers can reliably reconstruct the state of the network.

## Delivery Semantics: At-Least-Once

The firehose guarantees **at-least-once delivery** for all events. Every mutation persisted by the PDS is eventually emitted to the stream.

- **Idempotency**: Because network interruptions or server restarts can cause events to be retransmitted, subscribers must handle duplicate events (identified by their `seq` number) idempotently.
- **No Data Loss**: Events are persisted to `PDSServiceDatabases` before they are broadcast, ensuring they survive server crashes and can be replayed.

## Durability

All events are stored in the PDS sequencer using SQLite with Write-Ahead Logging (WAL) enabled. This ensures that:
- Sequence number assignment is atomic.
- Replay material is durable once the database transaction commits.
- Replaying from a cursor provides a consistent view of history.

## Ordering Guarantees

### Total Ordering

The firehose maintains a total order of all events via monotonically increasing sequence numbers. 

- **Sequence Numbers**: Every event (commit, identity, account) receives a unique `seq`.
- **Consistency**: All subscribers receive events in the same sequence order.
- **Serialization**: The `SubscribeReposHandler` uses a serial `syncQueue` to assign sequence numbers and persist events, preventing race conditions.

### Serial Delivery

While fanout to multiple subscribers happens on a concurrent queue (`broadcastFanoutQueue`), the order of events sent to each individual connection is strictly preserved by the underlying `WebSocketConnection` write queue.

## Duplicate and Gap Detection

### Handling Duplicates

Duplicates typically occur during reconnection when a client provides a cursor for an event it has already partially processed. Subscribers should use the `seq` field as a unique key for deduplication.

### Gap Detection

Subscribers can detect missing data by checking if the `seq` of a new event is exactly `last_seq + 1`. If a gap is detected, the subscriber should:
1. Terminate the current connection.
2. Reconnect with a `cursor` pointing to the last successfully processed sequence number.
3. Allow the server to replay the missing events.

## Recovery Scenarios

### Server Restart

On startup, the PDS recovers the last sequence number from the database. New events continue from `last_seq + 1`. Reconnecting clients resume from their last known cursor.

### Slow Consumer Protection

To maintain system reliability, the PDS will drop connections that fall too far behind. If a client's outbound queue exceeds 16MB or 512 frames, the server terminates the connection with a `ConsumerTooSlow` error. The client must then reconnect and use a cursor to catch up.

## Related

- [Event Ordering](./event-ordering)
- [Event Replay](./event-replay)
- [Backpressure and Flow Control](./backpressure)
