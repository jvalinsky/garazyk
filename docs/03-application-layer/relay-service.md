---
title: Relay Service
---

# Relay Service

`PDSRelayService` is an outbound notification service. It notifies configured relays to crawl the PDS when local records change. It does not aggregate global repository events; that role is performed by the **[Zuk Relay Server](./relay-server)**.

## Triggering Mechanism

The service subscribes to `PDSRecordDidChangeNotification`, emitted by the [Record Service](./record-service) after successful record mutations. This ensures that relay notifications occur only after the local data is persisted.

## Notification Process

When triggered, the service:
1.  Collects affected DIDs in memory.
2.  Debounces notifications for one second to collapse burst writes.
3.  Enforces a twenty-minute minimum interval between notifications to a specific relay.
4.  Sends `POST /xrpc/com.atproto.sync.requestCrawl` to each configured relay, including the PDS hostname in the payload.

This notification is a crawl hint, not a detailed replication feed.

## Debounce Logic

Record writes often arrive in bursts (e.g., during a profile update or batch write). The one-second debounce prevents swamping relays with redundant requests. The twenty-minute threshold prevents repetitive "nagging" during sustained user activity.

## Scope and Limits

`PDSRelayService` focuses strictly on notification. It does not implement:
- Durable retry queues.
- Per-DID replication payloads.
- Acknowledgement tracking or backfill state.
- Firehose subscription logic.

## Relationship to Sync Components

`PDSRelayService` is one part of the federation stack:
- **`PDSRelayService`**: Requests that relays crawl the local PDS.
- **`SubscribeReposHandler`**: Serves the local [Firehose](../08-sync-firehose/firehose-overview) and sync surfaces.
- **`RelayClient`**: Consumes remote relay feeds for local indexing.

## Related

- [Repository Service](./repository-service)
- [Record Service](./record-service)
- [Services Overview](./services-overview)
- [Firehose Overview](../08-sync-firehose/firehose-overview)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Documentation Map](../11-reference/documentation-map.md)

