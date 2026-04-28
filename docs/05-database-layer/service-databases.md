---
title: Service Databases
---

# Service Databases

## Overview

Service databases store shared operational state. They contain data independent of individual actor repositories, including account metadata, sessions, DID cache, and sequencer state.

## Storage Contents

The shared stores contain:

- account and admin operational metadata.
- session and authentication state.
- DID and handle resolution cache entries.
- sequencer and event-persistence state for sync.

Data belonging to the process, rather than a specific DID's repository, resides here.

## Key Tables and Entities

Three SQLite databases isolate operational metadata from event logs.

### 1. Main Service Database (`service.db`)
*   `accounts`: DID, handle, email, password hashes, 2FA state.
*   `oauth_refresh_tokens`: Valid OAuth2 refresh sessions.
*   `oauth_clients`, `oauth_authorization_codes`, `oauth_grants`: OAuth2/OpenID Connect state.
*   `invite_codes`: Registration invite management.
*   `admin_takedowns`, `admin_audit_log`, `reports`: Trust & Safety data.
*   `labels`: Cached assertions about actors/content.
*   `passkeys`: WebAuthn metadata.
*   `actor_preferences`, `actor_mutes`: Per-account service settings.
*   `conversations`, `messages`, `groups`: Chat metadata.
*   `video_jobs`: Video processing queue (transcoding, thumbnail generation, retries).

### 2. DID Cache Database (`did_cache.db`)
*   `did_cache`: Resolved DID documents with expiration tracking.

### 3. Sequencer Database (`sequencer.db`)
*   `events`: PDS sequencer event log.
*   `repo_sequence`: Repository-specific sequence numbers.

## Synthetic Service Store

`ServiceDatabases` uses the synthetic DID `__service__` to access shared stores via standard pool abstractions. This ensures consistent access while distinguishing shared data from actor data. Contributors often confuse shared operational storage with actor-store code.

## Typical Operations

Service databases handle:

- account lookups and updates.
- session persistence.
- DID cache operations.
- sequencer event persistence.
- video job management.

These are process-level concerns.

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

