---
title: Service Databases
---

# Service Databases

## Overview

Service databases hold shared operational state for the whole server. They are the storage layer for data that should not live inside one actor's repository database, such as account metadata, sessions, DID cache, and sequencer state.

## What Lives Here

Treat the shared stores as the home for:

- account and admin-facing operational metadata
- session and auth-adjacent shared state
- DID and handle resolution cache entries
- sequencer and event-persistence state used by sync surfaces

If the data belongs to the process rather than to one DID's repo, it usually belongs here.

## Key Tables and Entities

### Account & Auth
*   `accounts`: Primary user account registry (DID, handle, email).
*   `refresh_tokens`: Valid OAuth2/JWT refresh sessions.
*   `invite_codes`: PDS registration invite management.

### Trust & Safety
*   `age_assurance_states`: Metadata and tokens for age verification flows.
*   `chat_actor_metadata`: Mute/block/label state for chat participants.
*   `chat_event_log`: Permanent audit trail of all safety-sensitive chat actions.
*   `moderation_events`: Log of global moderation actions (takedowns, etc.).

### AppView Indexing
*   `appview_checkpoints`: Firehose sequence numbers for each upstream relay.
*   `appview_repo_sync_state`: Indexing status per DID.
*   `appview_relevance`: The set of DIDs being actively indexed in partial mode.

### Identity & Sync
*   `did_cache`: Local cache of resolved DID documents.
*   `events`: The PDS sequencer event log for the firehose.

## Why The Synthetic Service Store Matters

`ServiceDatabases` uses the synthetic DID `__service__` to access the shared-store path through the same pool abstractions used elsewhere. That choice matters because it keeps shared-store access consistent without pretending it is actor-owned data.

When contributors miss that boundary, they often search actor-store code for bugs that actually live in shared operational storage.

## Typical Operations

You usually land in the service databases for:

- account lookup and updates
- session persistence and token-adjacent state
- DID cache reads and writes
- sequencer event persistence for sync consumers

These are process-level concerns, not repository-structure concerns.

## Related Deep Dives

- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)

## Related Reading

- [SQLite Architecture](./sqlite-architecture)
- [Actor Databases](./actor-databases)
- [Testing Map](../11-reference/testing-map)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n