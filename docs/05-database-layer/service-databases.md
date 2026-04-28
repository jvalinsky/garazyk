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

The service layer is backed by three distinct SQLite databases to isolate operational metadata from high-volume event logs.

### 1. Main Service Database (`service.db`)
*   `accounts`: Primary user account registry (DID, handle, email, password hashes, 2FA state).
*   `oauth_refresh_tokens`: Valid OAuth2 refresh sessions (formerly `refresh_tokens`).
*   `oauth_clients`, `oauth_authorization_codes`, `oauth_grants`: Full OAuth2/OpenID Connect provider state.
*   `invite_codes`: PDS registration invite management.
*   `admin_takedowns`, `admin_audit_log`, `reports`: Trust & Safety operational data.
*   `labels`: Locally generated or cached assertions about actors/content.
*   `passkeys`: WebAuthn credential metadata.
*   `actor_preferences`, `actor_mutes`: Per-account service-side settings.
*   `conversations`, `messages`, `groups`: Chat and social group metadata.

### 2. DID Cache Database (`did_cache.db`)
*   `did_cache`: Local cache of resolved DID documents with expiration tracking.

### 3. Sequencer Database (`sequencer.db`)
*   `events`: The canonical PDS sequencer event log for the firehose.
*   `repo_sequence`: Tracking for repository-specific sequence numbers.

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
- [Testing Map](../11-reference/testing-map)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

