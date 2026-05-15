---
title: Firehose Rate Limiting and Backpressure
---

# Firehose Rate Limiting and Backpressure

The firehose protects server resources by enforcing limits on WebSocket subscribers. These limits prevent memory exhaustion from slow consumers and ensure fair resource distribution across all clients.

## Connection Limits

The PDS limits the total number of concurrent WebSocket connections and the number of connections allowed from a single IP address.

- **Global Limit**: Default is 500 connections.
- **Per-IP Limit**: Default is 5 connections per IP.

These limits are enforced by the `WebSocketServer` during the handshake phase.

## Event Rate Limits

The firehose uses a token-bucket style rate limiter to control the frequency of event broadcasts. In `SubscribeReposHandler.m`, a `dispatch_source_t` timer is used to throttle event processing:

```objc
// Initialize backpressure rate limiter (100 events/sec)
_eventRateLimiter = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _syncQueue);
if (_eventRateLimiter) {
  uint64_t interval = NSEC_PER_SEC / 100;
  dispatch_source_set_timer(_eventRateLimiter, DISPATCH_TIME_NOW, interval, interval / 10);
  dispatch_resume(_eventRateLimiter);
}
```

## Backpressure Enforcement

The PDS does not buffer an unlimited number of events for slow clients. Instead, it monitors the outbound queue for each connection and terminates subscribers that fall too far behind.

### Pending Send Thresholds

Each connection has two primary limits:
1. **Frame Count**: `maxPendingSendsPerConnection` (default: 512).
2. **Byte Volume**: `maxPendingBytesPerConnection` (default: 16MB).

If either threshold is reached, the server sends a `ConsumerTooSlow` error and closes the socket.

```objc
if (pendingCount >= self.maxPendingSendsPerConnection ||
    pendingBytes >= self.maxPendingBytesPerConnection) {
    [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                         message:@"connection output queue exceeded server limit"
                    toConnection:connection];
    [self detachConnection:connection];
    [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
    return NO;
}
```

## Configuration

These limits can be tuned via environment variables:

| Environment Variable | Description | Default |
|----------------------|-------------|---------|
| `PDS_FIREHOSE_MAX_REPLAY` | Max events replayed from cursor | 10,000 |
| `PDS_FIREHOSE_MAX_PENDING_SENDS` | Max queued frames before disconnect | 512 |
| `PDS_FIREHOSE_MAX_PENDING_BYTES` | Max queued bytes before disconnect | 16MB |

## Monitoring

The PDS exports metrics to track firehose health:
- `firehose_subscribers`: Current count of active WebSocket connections.
- `firehose_events_total`: Count of events emitted by type (commit, identity, account).
- `firehose_seq`: The current sequence number of the stream.

High values for `firehose_subscribers` relative to total capacity or frequent `ConsumerTooSlow` errors in logs indicate that clients are unable to keep up with the stream volume.

## Related

- [Backpressure](./backpressure)
- [Event Replay](./event-replay)
- [Metrics Collection](../11-reference/metrics-collection.md)
