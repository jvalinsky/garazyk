---
title: AppView Admin UI Brief
status: in-progress
last_verified: 2026-08-12
---

## 2026-08-12 — Serving + Repo sync IA

Syrena’s admin surface is **not** a Mikrus/Beskid clone. Operator questions:

| Service | Metaphor | Primary question |
| --- | --- | --- |
| Beskid | Cache thermometer | Hit ratio / upstream latency? |
| Mikrus | Graph / URI index | Is this `at://` edge findable? |
| **Syrena** | Pipeline → store → **serve** | Will a client get good `app.bsky.*` answers? |

### Dashboard shape (current target)

1. **Serving** — client-facing health first: three-lane pulse (Firehose · Sync · Serving), query families / errors / rate-limit rejects, exception gauges (dead letter, pending index).
2. **Firehose** — per-relay connection, lag, throughput, event counters (shared ingest vocabulary with Mikrus; AppView framing).
3. **Repo sync** — funnel (pending / processing / synced / dirty), workers, enqueue DIDs, retry/cancel, rebuild scope; bounded queue table.
4. **Coverage** — social completeness (handles, profiles, posts) + collection mix; not a generic URI explorer.

Deferred (next slices): ~~Exceptions triage list, Probe (XRPC console), Actor dig (hydrated cards).~~
**Done 2026-08-12:** Exceptions / Probe / Actor dig tabs on `GZSyrenaAdminUIPack`
(bounded dead-letter rows without `raw_record`; allowlisted Probe catalog via
`data-ui-form=appview-probe`; Actor dig from indexed handle/profile metadata).

Do **not** add a Mikrus-style Explore tab. Browse belongs as hydrated social views or Probe later.

## 2026-08-11 — Slices 1-3 implemented, slice 4 packaging done

- Slice 1: SyrenaMetrics (serial-queue counters for ingest events/commits/ops/
  deletes/identities/errors, backfill completed/failed/enqueued, query families
  [backlink/manyToMany/identity/record/other], query errors, rate-limit rejects)
  instrumented in AppViewRuntime ingest/backfill delegates.
- Slice 2: GZSyrenaAdminSnapshot (bounded: health, uptime, ingest relayHealth/
  lagByRelay/throughput from AppViewIngestEngine, backfill queueDepth/
  activeWorkers/repo state counts, index collection counts, DB page_count PRAGMA,
  config relays/backfill/partial) + password-file helper.
- Slice 3: GZSyrenaAdminUIPack with 4 partials (appview-metrics, ingest-health,
  appview-backfill, appview-indexes) + embedded admin host on 127.0.0.1:2596
  wired into AppViewRuntime + syrena/main.m (SYRENA_ADMIN_PASSWORD,
  SYRENA_ADMIN_PASSWORD_FILE, --admin-password-file).
- Slice 4: NixOS module (nixos/modules/syrena.nix), flake package + module
  registration, CMake manifest, module-boundary script entries.
- Tests: SyrenaAdminUITests.m (15 tests: metrics counters/snapshot/sidebar,
  pack auth/scoping, HTML output, password helper). Compilation blocked by
  pre-existing AllTests linker error (GZCommandLineOptions symbol duplication).
- Existing AppViewAdminRoutePack fail-open (validateAuth returns YES when
  adminSecret nil) is preserved for internal automation callers; embedded UI
  uses session auth.

# AppView (`syrena`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
Coordinate the shared ingest vocabulary with [Mikrus](mikrus.md) and compare
source-level troubleshooting with [Relay](relay.md).

## Outcome and evidence

Give operators one view of **serving**, firehose, repo sync (with mutations),
coverage, hooks/lexicons, and query health. `AppViewAdminRoutePack` exposes
lexicon, hook/dead-letter, record, handler, and endpoint inventories for the
protocol admin port; the embedded UI uses session auth + CSRF for mutations.

The current JSON admin route guard allows access when `adminSecret` is empty.
Embedding must remove that fail-open state: internal routes either require the
startup-minted loopback token or are unavailable, while browser routes require
the service session and CSRF for mutations.

## Slices and acceptance

1. Define one immutable AppView snapshot spanning ingest, backfill, database,
   hooks, and endpoint registries; do not poll queue tables for headline cards.
2. Replace fail-open admin auth and preserve internal automation callers with a
   narrow loopback credential contract.
3. Move the existing pack into AppView ownership and add per-relay rendering
   using the same semantics, not shared mutable state, as Mikrus.
4. Embed the admin host and add secret-file/loopback NixOS or container options.
5. **Serving + Repo sync IA** (2026-08-12): rename tabs, three-lane pulse,
   coverage gauges, queue UI + enqueue/retry/cancel/rebuild with CSRF.
6. **Exceptions / Probe / Actor dig** (2026-08-12): sidebar tabs + snapshot
   methods (`exceptionsWithLimit:`, `probeCatalog` / `probeMethod:params:`,
   `actorDigForIdentifier:`). Evidence: `SyrenaAdminUITests` (19).
7. Test multiple relays, disabled ingest/backfill, stale cursor, dead letters,
   bounded pagination, mutation audit, session/CSRF rejection, and concurrent
   ingest while the dashboard polls.

Acceptance requires zero unauthenticated admin JSON when the secret is absent,
no ingest/backfill throughput regression, and parity through the compatibility
host. Rollback restores the compatibility UI, never fail-open auth.
