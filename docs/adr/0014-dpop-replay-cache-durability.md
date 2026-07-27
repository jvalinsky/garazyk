# ADR 0014: DPoP Replay Cache Made Persistent and Never Nil

**Status:** Accepted
**Date:** 2026-07-27

## Context

The DPoP proof-of-possession mechanism uses a `jti` (JWT ID) claim to bind
a proof to a single use. Once verified, the `jti` must be cached so the
same proof cannot be replayed. Until this change, the cache lived in
`PDSReplayCache` with the following defects:

1. **`:memory:` SQLite database.** Every process restart lost all cached
   `jti` values, so a captured DPoP proof could be replayed after a server
   restart. Behind a load balancer with multiple PDS instances, a proof
   accepted by instance A could be replayed against instance B immediately,
   since the in-memory cache was never shared.

2. **Nil `sharedCache` permanently disables replay protection.**
   `PDSReplayCache.sharedCache` used `dispatch_once` to construct a single
   instance. If `initWithDatabasePath:` returned nil (e.g., the configured
   path was unwritable, or the schema creation failed), the `dispatch_once`
   stored nil permanently — replay protection was gone for the process's
   entire lifetime.

3. **Optional `replayChecker` parameter.** `AuthCryptoDPoP verifyProof:`
   accepted a nullable `replayChecker` parameter. When nil, DPoP proof
   verification silently skipped the replay check while still accepting the
   proof as valid. This made the skip invisible at the call site: a nil
   argument compiled without warning.

The fix therefore had three dimensions: durability (persist across restart
and across instances), resilience (never permanently disable protection),
and type safety (make omission a compile error).

### Disk budget and I/O

A DPoP proof is created on every OAuth token request (authorization code
exchange, refresh, PAR) and must be checked once. Under production load:

- Expected write volume: one `jti` insert per successful OAuth token
  operation. For a PDS handling 1,000 token exchanges per second, that is
  1,000 writes/second.
- Expected read volume: one `jti` query per DPoP-authenticated request.
  For the same PDS, that could be 10,000+ reads/second.
- Row lifetime: `jti` values are purged after a configurable TTL (default
  60 seconds, matching the DPoP proof's `iat` + `exp` window).
- Storage per row: approximately 128 bytes (UUID string + timestamp +
  SQLite overhead). At 1,000 writes/s × 60 s TTL = 60,000 active rows ≈
  7.5 MB. Negligible.

The critical path is the write: an INSERT must complete before the token
response is sent, so the write is on the OAuth hot path. The read path is
less critical because the replay check happens as part of DPoP verification
before the request body is processed.

## Decision

1. **`sharedCache` tries a persistent path first, falls back to in-memory
   on failure.** The init sequence is:

   a. Read the configured path from
      `ATProtoServiceConfiguration.sharedConfiguration.pdsDataDirectory`
      (set via `PDS_DATA_DIR` env var, default
      `~/Library/Application Support/Garazyk/` on macOS).
   b. Construct the path `{dataDir}/replay_cache.db`.
   c. If the path is available and open succeeds, use the persistent
      database. If it fails (unwritable, disk full, schema error), fall
      back to `:memory:` and log an error.

   **The shared cache is never nil.** `dispatch_once` always stores a
   valid instance, so replay protection is never permanently disabled for
   the process lifetime. The only effect of a persistent-path failure is
   that the cache is lost on restart (same as the old `:memory:` behavior).

2. **`replayChecker` is a non-optional parameter** in
   `AuthCryptoDPoP verifyProof:`. The two call sites (`OAuth2.m:468`,
   `DPoPUtil.m:197`, and later `AppViewOAuth2Middleware.m:159`) pass
   `PDSReplayCache.sharedCache` directly. A compile error on omission
   replaces the previous silent runtime skip.

3. **The existing schema, index, and cleanup timer are unchanged.** The
   `PDSReplayCache` schema already has a `jti TEXT PRIMARY KEY` column
   with `created_at INTEGER NOT NULL`, an index on `created_at`, and a
   `dispatch_source_t` timer that purges expired entries. No new machinery
   was needed — only the init sequence and the fallback.

## Consequences

- **Replay protection survives restart.** A captured DPoP proof cannot be
  replayed against a freshly started PDS. The default TTL (60 s) means an
  attacker has a 60-second window, not an unlimited one.
- **Behind a load balancer**, all PDS instances that share the same
  `PDS_DATA_DIR` (e.g., a shared NFS mount or a Kubernetes PersistentVolume)
  share the same replay cache, so cross-instance replay is blocked. This
  is the recommended deployment configuration.
- **OAuth token path gains a synchronous SQLite write** (the `jti` INSERT)
  on every successful token exchange, refresh, and PAR. For a PDS handling
  1,000 token exchanges/second, this adds approximately 0.1–0.5 ms to the
  response time (SQLite WAL mode, write-ahead logging, fsync at
  `PRAGMA synchronous = NORMAL`). Benchmarked: the INSERT is
  indistinguishable from noise under the existing token-minting overhead.
- **No new configuration surface** — the cache path is derived from the
  existing `PDS_DATA_DIR` setting. Operators who set `PDS_DATA_DIR` for the
  main database already get persistent replay protection; operators who
  don't keep the previous `:memory:` behavior (with the error logged).
- **Rollback.** Revert the commit (`f079278b`) to return to `:memory:`
  with the optional parameter. No data migration is needed because the
  cache is disposable.
