---
title: Backpressure and Flow Control
---

# Backpressure and Flow Control

Backpressure ensures the PDS remains stable when firehose subscribers cannot consume events as fast as they are generated. The system monitors the outbound queue for each connection and provides warnings, metrics, and eventually connection termination if thresholds are exceeded.

## Queue Architecture

Each `WebSocketConnection` manages an asynchronous `writeQueue` and a `messageQueue` for outbound frames. 

- **Frame Buffering**: Outbound events are enqueued as DAG-CBOR frames.
- **Byte Counting**: The connection tracks `queuedSendBytes` to monitor memory usage.
- **Asynchronous Flushing**: Frames are written to the underlying transport sequentially; as one write completes, the next is dequeued and sent.

## Backpressure Thresholds

The `WebSocketProtocolSession` defines three state levels based on the percentage of `maxOutboundQueueBytes` (default 10MB) currently in use:

1. **Warning**: Triggered when the queue exceeds the warning threshold (default 60%).
2. **Critical**: Triggered when the queue exceeds the critical threshold (default 85%).
3. **Overflow**: Triggered when the queue exceeds 100%.

### State Transitions

When these thresholds are crossed, the connection emits specific actions:

```objc
// In WebSocketConnection.m - sendFrame:
NSUInteger newQueueSize = self.queuedSendBytes + frame.length;
NSArray<WSSessionAction *> *actions = [self.session didEnqueueFrameOfSize:frame.length
                                                       currentQueueSize:newQueueSize];

if (newQueueSize > self.session.maxOutboundQueueBytes) {
  [self notifyQueueOverflow:newQueueSize];
  [self closeWithCode:1009 reason:@"Outbound queue limit exceeded"];
  return;
}
```

## Handling Slow Consumers

### Warnings and Logging

When a consumer reaches a threshold, the PDS logs a warning and records metrics:

- `WSSessionActionTypeBackpressureWarning`: Logs the current fill percentage.
- `WSSessionActionTypeBackpressureCritical`: Indicates a high risk of disconnection.
- `WSSessionActionTypeBackpressureCleared`: Logged when the queue drains below the warning level.

### Termination (Code 1009)

The PDS does not pause the firehose for slow consumers; it drops them. If a subscriber exceeds `maxOutboundQueueBytes`, the connection is closed with WebSocket error code `1009` (Message Too Big / Outbound queue limit exceeded). This protects the PDS from memory exhaustion.

## Monitoring Metrics

Firehose backpressure events are captured in the system metrics:
- `websocket_backpressure_warning_total`
- `websocket_backpressure_critical_total`
- `websocket_queue_overflow_closures_total`

## Configuration

Backpressure limits can be tuned via the `WebSocketProtocolSession` configuration or environment variables:

| Setting | Default | Description |
|---------|---------|-------------|
| `maxOutboundQueueBytes` | 10MB | Maximum bytes allowed in the outbound queue. |
| `backpressureWarningThreshold` | 0.60 | Fill percentage to trigger a warning log. |
| `backpressureCriticalThreshold` | 0.85 | Fill percentage to trigger a critical log. |

## Related

- [Firehose Rate Limiting](./firehose-rate-limiting)
- [WebSocket Server](./websocket-server)
- [Reliability Guarantees](./reliability-guarantees)
