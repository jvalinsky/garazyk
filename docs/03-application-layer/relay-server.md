---
title: Zuk Relay Server
---

# Zuk Relay Server

**Zuk** is a high-capacity AT Protocol Relay implementation. Its primary purpose is to aggregate repository updates from multiple PDS instances and provide a single, unified Firehose for downstream consumers (like the AppView).

## Core Responsibilities

1.  **Ingestion**: Zuk connects to the Firehose of many PDS instances simultaneously.
2.  **Aggregation**: It normalizes and sequences events from these disparate sources.
3.  **Broadcasting**: It provides its own Firehose (`com.atproto.sync.subscribeRepos`) which emits the aggregated stream.
4.  **Backfill Support**: It can serve historical blocks and commits to downstream indexers that need to catch up.

## Architecture

Zuk is built using the same **Sans-I/O** principles as the PDS, allowing its relay logic to scale across different networking backends.

### 1. Crawler
The Crawler component is responsible for discovering new PDS instances. It can be manually triggered via the `com.atproto.admin.requestCrawl` endpoint or automatically follow links in the network.

### 2. Aggregator
The Aggregator maintains a global sequence of events. It ensures that even if events arrive out of order from different PDS instances, the downstream Firehose remains consistent and monotonically increasing.

### 3. Broadcaster
The Broadcaster drives the outbound WebSocket Firehose. It implements the same backpressure and framing logic as the PDS but is optimized for the much higher throughput required by a global relay.

## Operational Deployment

Zuk runs as a standalone binary (`zuk`). In a typical deployment:
*   Zuk needs significant outbound bandwidth to serve many AppView instances.
*   It requires a fast disk (NVMe) for its block cache to handle backfill requests without stalling the live firehose.

---

## Related
- [Firehose Overview](../08-sync-firehose/firehose-overview)
- [Commit Broadcasting](../08-sync-firehose/commit-broadcasting)
- [PDS Admin Controls Phase 1](../plans/pds-admin-controls-phase-1)
