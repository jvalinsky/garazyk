---
title: Mikrus Admin UI Brief
status: in-progress
last_verified: 2026-08-11
---

# Link index (`mikrus`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
Mikrus shares `AppViewIngestEngine` concepts with [AppView](appview.md) and
source troubleshooting semantics with [Relay](relay.md), but owns its snapshot,
pack, database, and credentials.

## Outcome and evidence

Add the first admin pack for Mikrus. Today it serves `/` and `/_health`, opens
`mikrus.db`, `ingest-state.db`, and `ratelimits.db`, optionally ingests from
configured relays, and exposes backlink, many-to-many, identity, and record
queries. There are no operational counters or admin credential yet.

## Dashboard shape

- **Overview:** health, uptime, ingest enabled/running, configured/connected
  relays, cursor/lag, event and error rates, indexed records, DIDs, collections,
  and database pressure.
- **Ingestion:** overall and per-relay cursor, last event, commits/operations,
  rejected records, reconnects, checkpoint age, and last error.
- **Indexes:** backlink edges and sources, many-to-many edges by relationship,
  cached identities, record totals by collection, and bounded recent activity.
- **Queries:** request rate, latency, not-found rate, rate-limit rejects, and
  result-size limits by endpoint family.
- **Actions:** phase one is read-only. Pause/resume or reconnect may be added only
  through explicit ingest-engine service methods with audit and CSRF coverage.

## Slices and acceptance

1. ~~Add cheap materialized counters at write/delete boundaries and a synchronized
   ingest snapshot; no dashboard refresh may aggregate the whole link index.~~
   **Done 2026-08-11:** `MikrusMetrics` with serial-queue counters (ingest
   events/commits/ops/deletes/identities, records indexed/deleted, errors, query
   families: backlink, many-to-many, identity, record, rate-limit rejects).
   Counters instrumented in `MikrusRuntime` delegate + `MikrusXrpcRoutePack` handlers.
2. ~~Create `GZAdminUIMikrusPack` under Mikrus ownership with overall/per-relay
   selection and bounded index-family tables.~~
   **Done 2026-08-11:** `GZMikrusAdminUIPack` with three read-only partials
   (`/admin/partials/mikrus-metrics`, `-ingestion`, `-indexes`) and a
   `GZMikrusAdminSnapshot` composing metrics, `AppViewIngestEngine` state
   (relayHealth, lagByRelay, throughput), approximate edge count via bounded
   rowid scan, database pressure, and ingest configuration.
3. ~~Add a dedicated listener, password-file configuration, internal loopback
   credential, lifecycle composition, and packaging/NixOS options.~~
   **Done 2026-08-11:** `MikrusRuntime` composes `GZAdminUIHost` on loopback
   (127.0.0.1:2593, max concurrency 8). Password from
   `MIKRUS_ADMIN_PASSWORD_FILE`/`MIKRUS_ADMIN_PASSWORD`. CLI flags
   `--admin-ui-host`, `--admin-ui-port`, `--admin-password-file`.
   `nixos/modules/mikrus.nix` with systemd credential, `NoNewPrivileges`,
   `ProtectSystem=strict`; flake package + nixosModules.
4. ~~Test ingest disabled, no relays, multiple relays, checkpoint restart, index
   delete/correction, rate limits, stale/error states, auth, and concurrent
   indexing/polling.~~
   **Done 2026-08-11:** `MikrusMetricsTests` (counter aggregation),
   `MikrusAdminSnapshotTests` (empty snapshot, db pressure),
   `MikrusAdminUIPackTests` (unauth redirect, scoped session, sibling reject,
   login, loopback+concurrency, password-file). 9 tests, 0 failures. Full relay
   ingest scenarios deferred to hamownia topology tests.

Acceptance requires counters to reconcile against fixture databases, polling
to add no unbounded query plan, and the public XRPC surface to remain unchanged.
Rollback disables the embedded listener without changing ingestion or indexes.
