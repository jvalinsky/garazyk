---
title: "Tutorial 15: Syrena AppView Operation"
---

# Tutorial 15: Syrena AppView Operation

## Overview

Syrena is the AppView engine of the Garazyk ecosystem. While the PDS focuses on authoritative storage, Syrena is optimized for consuming the network firehose and materializing query-optimized read models. This tutorial covers the lifecycle of data within Syrena, from ingestion to specialized indexing.

**Learning Objectives:**
- Understand the roles of `AppViewIngestEngine` and `AppViewBackfillOrchestrator`.
- Trace the materialization pipeline from raw blocks to specialized indexers.
- Learn how Syrena handles backfills for newly discovered repositories.
- Verify AppView health and state using the `syrena` CLI.

**Estimated Time:** 45-60 minutes

---

## The Dual-Engine Architecture

Syrena's operational stability relies on two core components working in tandem:

1.  **`AppViewIngestEngine`**: The real-time listener. It connects to upstream Relays and processes the Firehose, ensuring high-water marks (checkpoints) are persisted.
2.  **`AppViewBackfillOrchestrator`**: The historical catch-up engine. When a repository is first discovered or becomes "relevant," this orchestrator manages the full sync process without interrupting live ingest.

---

## Prerequisites

- Complete [Tutorial 5: Firehose](./tutorial-5-firehose) and [Tutorial 14: Advanced Firehose](./tutorial-14-advanced-firehose).
- A running Garazyk PDS or access to a public Relay (e.g., `https://bsky.network`).
- `syrena` binary built and available in your path.
- `deciduous` CLI tool installed.

---

## Step 1: Track the Audit with Deciduous

Before diving into the operational internals, initialize your session in the `deciduous` graph.

```bash
deciduous add goal "Audit AppView Operation" -c 95
# Track your progress as you complete each step
deciduous add action "Analyzing IngestEngine checkpoint logic" -c 90
```

---

## Step 2: Connecting to Upstream Relays

Syrena does not store its own authoritative data; it consumes it from Relays.

### Configuration
Review your `syrena.config.json` (or equivalent environment variables). Syrena can connect to multiple relays to ensure high availability.

### The Connection Loop
In `AppViewIngestEngine.m`, observe how the engine:
1.  **Fetches the last checkpoint**: Queries the `appview_checkpoints` table for the last processed sequence number.
2.  **Initiates WebSocket**: Connects to `com.atproto.sync.subscribeRepos?cursor=...`.
3.  **Deduplicates**: If multiple relays are used, it filters out duplicate sequence numbers using a sliding window buffer.

---

## Step 3: The Materialization Pipeline

Once a commit event arrives, it enters the materialization pipeline.

### 1. Block Extraction
The Ingest Engine extracts CAR blocks from the event. These raw blocks are temporarily stored to allow for CID verification and late-binding indexing.

### 2. Generic Record Indexing
The event is parsed into a generic record format (URI, DID, Collection, RKey, CID) and stored in the main `records` table.

### 3. Specialized Indexers
This is where the "View" is created. Syrena dispatches the record to specific indexers based on its collection:
- **`AppViewFeedIndexer`**: Processes `app.bsky.feed.post` and `app.bsky.feed.like`.
- **`AppViewGraphIndexer`**: Processes `app.bsky.graph.follow` and block lists.
- **`AppViewActorIndexer`**: Updates profile information and handles.

**Technical Detail:** 
Look for `processRecord:inCollection:forActor:` in the various `Indexer.m` files. Each indexer is responsible for its own SQL schema (e.g., `bsky_feed_posts`).

---

## Step 4: Backfill Logic for New Repositories

When Syrena encounters a DID it hasn't seen before, it triggers a backfill.

### The Orchestrator's Workflow
1.  **Detection**: `AppViewIngestEngine` identifies an unknown DID.
2.  **Queueing**: `AppViewBackfillOrchestrator` adds the DID to its priority queue.
3.  **Checkout**: The orchestrator performs a `com.atproto.sync.getRepo` call to the PDS to get the full state.
4.  **Delta Buffering**: While the full state is being indexed, any *new* live events for that DID are buffered in `appview_pending_deltas` to prevent race conditions.
5.  **Reconciliation**: Once the backfill is done, the pending deltas are applied, and the repo is marked as `synced`.

---

## Troubleshooting

| Failure Mode | Symptom | Root Cause / Mitigation |
| --- | --- | --- |
| **Backfill Stall** | `appview_repo_sync_state` shows many `pending` repos that never transition. | Network congestion or PDS rate-limiting. Check `AppViewBackfillOrchestrator` logs. |
| **Duplicate Events** | Specialized tables contain duplicate entries for the same URI. | Deduplication buffer in `AppViewIngestEngine` is too small or checkpoint logic failed. |
| **Indexing Lag** | High delta between Relay sequence and AppView checkpoint. | Slow specialized indexers or database write contention. Consider optimizing SQL indexes. |
| **CID Mismatch** | `AppViewIngestEngine` logs "Invalid CID for block". | Data corruption on the wire or a malicious relay. Syrena should drop the event and alert. |

---

## Step 5: Verification with Syrena CLI

Use the `syrena` utility to inspect the internal state of the AppView.

```bash
syrena status
syrena backfill list
syrena index inspect did:plc:123... --collection app.bsky.feed.post
syrena index reindex did:plc:123...
```

---

## Summary

The Syrena AppView is a complex state machine that transforms a stream of commits into a queryable social graph. By separating real-time ingest from historical backfill and using specialized indexers, it provides the performance needed for global-scale applications.

Always use `deciduous` to document changes to indexing logic or new specialized indexers you implement.

## Next Steps

1. Explore [Tutorial 16: Custom AppView Indexers](./tutorial-16-custom-indexers) (Draft).
2. Review the [AppView Server Documentation](../03-application-layer/appview-server.md).
3. Check [Database Schema](../05-database-layer/service-databases) for table definitions.
