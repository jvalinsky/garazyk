---
title: Relay Service
---

# Relay Service

## Overview

`PDSRelayService` is an outbound hinting service. Its job is not to aggregate global repo events or provide a massive firehose — that is the role of the **[Zuk Relay Server](./relay-server)**. Instead, this service simply notifies configured relays to crawl this PDS when local records change.

That narrow contract is the key to understanding the implementation.

## How It Is Triggered

The relay service subscribes to `PDSRecordDidChangeNotification`, which the
record service emits when record mutations occur.

This means relay notification is downstream from successful local record work.
The relay service is not deciding whether a repository change happened. It is
reacting after the record layer already did.

## What The Service Actually Sends

When triggered, the service:

- collects the affected DIDs in memory
- debounces notifications for one second
- enforces a twenty-minute minimum interval between relay notifications
- sends `POST /xrpc/com.atproto.sync.requestCrawl` to each configured relay
- includes this PDS hostname in the JSON body

That is intentionally smaller than a per-DID replication feed. The current
message is a crawl hint, not a detailed change payload.

## Why The Debounce Exists

Record writes often arrive in bursts. Without a debounce, one local workflow
could trigger a swarm of redundant relay requests. The one-second delay lets the
service collapse nearby writes into one crawl hint.

The longer twenty-minute threshold serves a different purpose: keep the server
from repeatedly nagging relays during sustained write activity.

## What The Service Does Not Do

The relay service does not currently provide:

- a durable retry queue
- per-DID relay payloads
- acknowledgement tracking
- backfill state
- firehose subscription logic

Those are separate problems. The docs should not describe this class as if it
already solved them.

## Relationship To Other Sync Components

Do not confuse `PDSRelayService` with `SubscribeReposHandler` or `RelayClient`.

- `PDSRelayService` asks relays to crawl us
- `SubscribeReposHandler` serves our own firehose and sync surfaces
- `RelayClient` consumes remote relay feeds

Each of those pieces belongs to sync, but they solve different sides of the
federation story.

## Related Reading

- [Repository Service](./repository-service)
- [Services Overview](./services-overview)
- [Request Lifecycle](../01-getting-started/request-lifecycle)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n