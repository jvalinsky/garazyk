---
title: Beskid Admin UI Brief
status: in-progress
last_verified: 2026-08-11
---

# Edge cache (`beskid`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
See [PDS](pds.md) for the upstream records it caches and [PLC](plc.md) for the
identity directory it depends on.

## Outcome and evidence

Add the first Beskid admin pack. Beskid currently exposes only a basic health
route beside its record/identity cache XRPC surface. `BeskidDatabase` stores
TTL-bound record and identity entries; route handlers perform read-through
fetches and share the rate limiter. There are no hit/miss, expiry, upstream, or
latency counters yet.

## Dashboard shape

- **Overview:** health, uptime, record/identity entry gauges, hit ratio, expiry
  rate, upstream success/error rate, request latency, rate-limit rejects, and
  database pressure.
- **Cache families:** overall plus record and identity views with entries,
  hits/misses, writes, evictions, expired reads, TTL configuration, and oldest
  or soonest expiry. Never render cached record bodies, signing keys, or raw DID
  documents.
- **Upstreams:** bounded destination host summaries, request count, latency,
  failures, and last success; omit query strings and credentials.
- **Actions:** begin read-only. Later evict-one or purge-expired actions require
  typed database methods, exact target confirmation, audit, and CSRF protection.

## Slices and acceptance

1. ~~Instrument cache lookup/write/delete and upstream fetch boundaries with
   synchronized counters; maintain entry gauges during migrations and expiry.~~
   **Done 2026-08-11:** `BeskidMetrics` with serial-queue counters
   (hits/misses/expired/writes/deletes for record + identity), entry gauges
   seeded from one-time COUNT at startup and maintained on write/delete/expired-read,
   bounded per-host upstream aggregation (cap 32), and rate-limit reject counter.
2. ~~Create `GZAdminUIBeskidPack` and a bounded snapshot route under Beskid.~~
   **Done 2026-08-11:** `GZBeskidAdminUIPack` with three read-only partials
   (`/admin/partials/beskid-metrics`, `-cache`, `-upstreams`) and a
   `GZBeskidAdminSnapshot` with bounded snapshot (health, uptime, cache families,
   TTL config, upstream host summaries, database storage bytes via PRAGMA).
   HTML partials never render record bodies, signing keys, raw DID documents,
   query strings, or credentials.
3. ~~Add the dedicated listener, password-file configuration, loopback token,
   clean lifecycle, and packaging/NixOS options.~~
   **Done 2026-08-11 (listener/password/lifecycle):** `BeskidRuntime` composes
   `GZAdminUIHost` on a dedicated loopback listener (127.0.0.1:2595) with
   max concurrency 8. Password resolved from `BESKID_ADMIN_PASSWORD_FILE` or
   `BESKID_ADMIN_PASSWORD` (file wins); listener starts only when configured.
   CLI: `--admin-ui-host`, `--admin-ui-port`, `--admin-password-file`.
   NixOS module deferred to follow-up (no existing `beskid.nix`).
   **Done 2026-08-11 (packaging):** `nixos/modules/beskid.nix` with
   systemd-credential admin-password-file loading, loopback bind, admin port
   option (2595), `ProtectSystem=strict`/`NoNewPrivileges`, and a
   `flake.nix` package derivation (`beskid`); `nixos/examples/beskid.nix`
   example wired for sops-nix/agenix.
4. ~~Test hit/miss/expired behavior, upstream failures, rate limiting, redaction,
   empty cache, concurrent access, auth, and polling cost.~~
   **Done 2026-08-11:** `BeskidMetricsTests` (counters, bounded upstreams,
   concurrent updates), `BeskidAdminSnapshotTests` (empty cache, counters
   reflect ops, redaction, soonest expiry, DB pressure), `BeskidAdminUIPackTests`
   (unauth redirect, scoped session, sibling-cookie rejection, redaction, login
   wrong-password/correct, loopback+concurrency assertion, upstream HTML no
   credentials, password-file trim+redact). 16 tests, 0 failures.

Acceptance requires fixture-based counter reconciliation, no sensitive cache
content in HTML/JSON, and unchanged read-through behavior and latency bounds.
Rollback disables only the admin listener.
