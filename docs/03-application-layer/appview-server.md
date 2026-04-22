---
title: Syrena AppView Server
---

# Syrena AppView Server

**Syrena** is the high-performance AppView implementation for the Garazyk ecosystem. While the PDS is responsible for authoritative data storage and identity management, Syrena is optimized for consuming the Firehose and providing rich, queryable read-models.

## Role in the Ecosystem

The Bluesky architecture separates "Authoritative Storage" (PDS) from "Query-Optimized Views" (AppView). Syrena fulfills the AppView role by:

1.  **Ingesting** data from one or more Relay firehoses.
2.  **Indexing** records from thousands of repositories into specialized tables.
3.  **Serving** complex queries (feeds, search, profile views) via XRPC.

## Standalone Operation

Syrena is designed to run as a standalone binary (`syrena`). This allows it to be scaled independently of the PDS. In many production deployments:
*   The **PDS** runs on a small, secure VM with emphasis on database integrity.
*   **Syrena** runs on a machine with more CPU and RAM to handle global indexing and query load.

## Indexing Modes

### 1. Full Indexing
In this mode, Syrena attempts to index every repository and record it discovers on the network. This provides a "Global View" but requires significant storage and processing power.

### 2. Partial Indexing
To save resources, Syrena can be configured for "Partial Mode." It only indexes records from "Relevant Actors."
*   **Relevance Set**: Actors are added to the set if they are on the local PDS, followed by a local user, or have interacted with a local user.
*   **TTL**: Irrelevant actors are pruned from the set after a period of inactivity.

## The Indexing Pipeline

The pipeline is managed by `AppViewRuntime` and consists of several stages:

### Ingest Engine (`AppViewIngestEngine`)
Connects to upstream Relays and manages the stream of commits.
*   **Checkpoints**: Persists the last processed sequence number (`appview_checkpoints`) to ensure no events are missed after a restart.
*   **Deduplication**: Uses `appview_event_log` to filter duplicate events from multiple relay sources.

### Materialization
*   **Block Storage**: CAR blocks are stored in the `blocks` table for verification.
*   **Generic Index**: URI and CID mapping are stored in the `records` table.
*   **Specialized Indexers**: Objects like `AppViewFeedIndexer` or `AppViewGraphIndexer` parse record contents into dedicated tables (e.g., `bsky_feed_generators`, `bsky_graph_lists`).

### Backfill Orchestrator (`AppViewBackfillOrchestrator`)
When a new repository becomes "Relevant," the orchestrator fetches the entire repository state from the PDS.
*   **Delta Buffering**: While a backfill is in progress, live updates for that DID are buffered in `appview_pending_deltas` and applied once the backfill completes.

## Database Schema

Syrena uses several specialized tables to track indexing state:
*   `appview_repo_sync_state`: Tracks which repositories are synced, dirty, or pending backfill.
*   `appview_relevance`: Stores the set of relevant DIDs.
*   `appview_checkpoints`: High-water mark for firehose ingest.

---

## Related
- [AppView Gap Analysis](../appview-gap-analysis-2026-04-21)
- [PDS Admin Controls Phase 1](../plans/pds-admin-controls-phase-1)
- [Database Schema (Shared)](../05-database-layer/service-databases)
