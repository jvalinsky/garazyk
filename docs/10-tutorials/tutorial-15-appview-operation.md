---
title: "Tutorial 15: AppView Operation"
---

# Tutorial 15: AppView Operation

Syrena is the AppView engine for the Garazyk ecosystem. While the PDS focuses on authoritative storage, Syrena consumes the network firehose to materialize query-optimized read models.

## Dual-Engine Architecture

Syrena relies on two core components:

1. **`AppViewIngestEngine`:** The real-time listener that connects to upstream Relays and processes the firehose.
2. **`AppViewBackfillOrchestrator`:** The historical sync engine that handles newly discovered or relevant repositories without interrupting live ingest.

## The Materialization Pipeline

When a commit event arrives, it passes through several stages:

### 1. Block Extraction
The Ingest Engine extracts CAR blocks from the event. These blocks are briefly stored for CID verification and indexing.

### 2. Record Indexing
The event is parsed into a generic record format (URI, DID, Collection, RKey, CID) and stored in the primary `records` table.

### 3. Specialized Indexers
Syrena dispatches records to specific indexers based on their collection:
- **`AppViewFeedIndexer`:** Posts and likes.
- **`AppViewGraphIndexer`:** Follows and blocks.
- **`AppViewActorIndexer`:** Profiles and handles.

Each indexer maintains its own SQL schema (e.g., `bsky_feed_posts`).

## Backfill Logic

When Syrena encounters an unknown DID, it triggers a backfill:

1. **Detection:** `AppViewIngestEngine` identifies the new DID.
2. **Queueing:** `AppViewBackfillOrchestrator` adds the DID to its priority queue.
3. **Checkout:** The orchestrator calls `com.atproto.sync.getRepo` to fetch the full repository state.
4. **Buffering:** New live events for that DID are buffered in `appview_pending_deltas` while the backfill is in progress.
5. **Reconciliation:** Once the backfill is complete, the pending deltas are applied.

## Verification

Use the `syrena` CLI to inspect the internal state:

```bash
syrena status
syrena backfill list
syrena index inspect did:plc:123... --collection app.bsky.feed.post
```

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| Backfill Stall | Network or rate-limiting | Check `AppViewBackfillOrchestrator` logs for PDS connection errors. |
| Indexing Lag | Slow indexers or DB contention | Optimize SQL indexes or investigate specialized indexer performance. |
| CID Mismatch | Data corruption | Drop the event and alert; investigate the upstream relay's integrity. |

## See Also

- [AppView Server Documentation](../03-application-layer/appview-server.md)
- [Database Schema](../05-database-layer/service-databases)
- [Tutorial 14: Advanced Firehose](./tutorial-14-advanced-firehose)
