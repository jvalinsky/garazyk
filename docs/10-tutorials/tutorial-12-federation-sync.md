---
title: "Tutorial 12: Federation & Sync"
---

# Tutorial 12: Federation & Sync

Garazyk operates within a federated network where data is replicated between Personal Data Servers (PDS), Relays, and AppViews.

## Federation Topology

Your PDS is the authority for your data. It pushes events to a Relay via a firehose. Conversely, your PDS can pull data from a Relay to stay updated on other users.

- **PDS:** The authoritative host for repository records.
- **Relay:** A high-volume aggregator that re-broadcasts firehoses from many PDSs.
- **AppView:** A consumer that transforms firehose data into optimized read models (e.g., search, feeds).

## Upstream Subscriptions

The `RelayClient` manages connections to upstream Relays.

### Connection Lifecycle
1. **Handshake:** Initiates a WebSocket connection to `com.atproto.sync.subscribeRepos`.
2. **Cursor Management:** Passes the last known sequence number as a `cursor`. This ensures the PDS resumes exactly where it left off, avoiding data gaps.
3. **Event Handling:** Processes `Commit`, `Identity`, and `Handle` events via the `FirehoseSubscriptionDelegate`.

## Upstream Management

`RelayUpstreamManager` orchestrates one or more `RelayClient` instances.

- **Resilience:** Uses exponential backoff to handle connection failures.
- **Auto-Reconnect:** Continuously attempts to restore connections to configured upstreams.
- **Monitoring:** Tracks host status and exposes health metrics.

## Persistence

The PDS must remember its position in each upstream's stream. `RelayClient` persists the latest sequence number (`seq`) to the database. Upon restart, it reads these cursors to re-establish its "place in line."

## Verification

### Monitor Event Flow
Check relay-specific metrics to verify event consumption:
```bash
curl -sS http://127.0.0.1:2583/_metrics | grep relay_
```

### Inspect Logs
Watch for `RelayClient` entries to verify handshakes and cursor usage:
```bash
tail -f pds.log | grep RelayClient
```

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| Data Gaps | Cursor not persisted | Verify that sequence numbers are being saved to the database. |
| Reconnect Storm | Aggressive retry policy | Adjust the base reconnect interval in `RelayUpstreamManager`. |
| 401 Unauthorized | Auth failure | Ensure the `accessToken` for the upstream Relay is valid and configured. |
| Dropped Events | Backpressure | The PDS is consuming events slower than the Relay is sending them. Optimize the downstream handler. |

## See Also

- [Firehose Overview](../08-sync-firehose/firehose-overview)
- [Metrics Collection](../11-reference/metrics-collection)
- [Tutorial 5: Firehose](./tutorial-5-firehose)
