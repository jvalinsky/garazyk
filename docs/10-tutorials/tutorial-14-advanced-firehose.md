---
title: "Tutorial 14: Advanced Firehose"
---

# Tutorial 14: Advanced Firehose

Building on the basics of event streaming, this tutorial covers the production features of the Garazyk firehose: backfill replay, cursor validation, and backpressure management.

## Backfill and Replay

When a client connects with a `cursor` parameter, they are requesting a "catch-up" on missed events.

### Replay Logic
The `SubscribeReposHandler` manages this process:
1. **Query:** Fetches events from the `service_events` table where the sequence number is greater than the provided cursor.
2. **Stream:** Sequentially sends these historical events to the client.
3. **Transition:** Once the replay is complete, the connection automatically switches to live updates.

Garazyk enforces a `maxReplayEventsPerConnection` limit (default 10,000) to protect server resources from excessive backfill requests.

## Cursor Validation

The server applies several rules to determine cursor validity:

- **Future Cursor:** If the requested sequence number is higher than the server's current head, the connection is rejected.
- **Malformed Cursor:** Non-numeric or negative values are rejected.
- **Outdated Cursor:** If the requested event has been pruned or is beyond the replay window, the server sends an `#info` frame with an `OutdatedCursor` code.

## Backpressure and Flow Control

A high-volume firehose can overwhelm slow consumers. Garazyk protects itself by monitoring the send buffer for every connection.

### `ConsumerTooSlow`
If a client falls too far behind:
1. **Thresholds:** The PDS checks `pendingSendCount` (limit 512) and `pendingSendBytes` (limit 16MB).
2. **Disconnection:** If either threshold is exceeded, the server sends a `ConsumerTooSlow` error and closes the connection.

## Verification

### Test Backfill
Request a sequence number from the recent past to trigger a replay:
```bash
# Example using websocat
websocat "ws://127.0.0.1:2583/xrpc/com.atproto.sync.subscribeRepos?cursor=100"
```

### Observe Backpressure
A client that connects but fails to read from the socket will eventually trigger a `ConsumerTooSlow` disconnection.

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| `OutdatedCursor` | Event pruned | The client must perform a full repository re-sync; it can no longer catch up via the firehose. |
| `ConsumerTooSlow` | Slow client | Optimize the client-side parser or implement an internal event queue. |
| Stalled Backfill | DB Latency | Ensure the `service_events` table is correctly indexed on the sequence column. |

## See Also

- [Event Replay](../08-sync-firehose/event-replay)
- [Backpressure Reference](../08-sync-firehose/backpressure)
- [Tutorial 5: Firehose](./tutorial-5-firehose)
