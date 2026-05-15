---
title: Service Databases
---

# Service Databases

## Overview

Service databases store shared operational state, including account metadata, sessions, DID cache, and sequencer state. These are independent of individual actor repositories.

## Storage Contents

- Account and admin metadata.
- Session and authentication state.
- DID and handle resolution cache.
- Sequencer and event-persistence state.

## Key Databases

### 1. Main Service Database (`service.db`)
- `accounts`: DID, handle, email, password hashes, 2FA.
- `oauth_refresh_tokens`, `oauth_clients`, `oauth_grants`: OAuth2/OIDC state.
- `invite_codes`: Registration invite management.
- `admin_takedowns`, `admin_audit_log`, `reports`: Trust & Safety.
- `labels`: Cached assertions.
- `passkeys`: WebAuthn metadata.
- `actor_preferences`, `actor_mutes`: Per-account settings.
- `conversations`, `messages`, `groups`: Chat metadata.
- `video_jobs`: Processing queue.

### 2. DID Cache Database (`did_cache.db`)
- `did_cache`: Resolved DID documents with expiration.

### 3. Sequencer Database (`sequencer.db`)
- `events`: PDS sequencer event log.
- `repo_sequence`: Repository-specific sequence numbers.

## Synthetic Service Store

`ServiceDatabases` uses the synthetic DID `__service__` to access shared stores via standard pool abstractions. This ensures consistent access while distinguishing shared data from actor data.

## Related Deep Dives
- [Shared vs Actor Database Boundary](./shared-vs-actor-database-boundary)
- [Transactions, WAL, and Concurrency](./transactions-wal-and-concurrency)
- [SQLite Architecture](./sqlite-architecture)

## Related Reading
- [Actor Databases](./actor-databases)
- [WAL Mode](./wal-mode)
- [Session and JWT Lifecycle](../06-authentication/session-and-jwt-lifecycle)
- [Firehose Overview](../08-sync-firehose/firehose-overview)
- [Glossary](../GLOSSARY)

