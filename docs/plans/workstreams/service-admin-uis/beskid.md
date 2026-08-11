---
title: Beskid Admin UI Brief
status: planned
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

1. Instrument cache lookup/write/delete and upstream fetch boundaries with
   synchronized counters; maintain entry gauges during migrations and expiry.
2. Create `GZAdminUIBeskidPack` and a bounded snapshot route under Beskid.
3. Add the dedicated listener, password-file configuration, loopback token,
   clean lifecycle, and packaging/NixOS options.
4. Test hit/miss/expired behavior, upstream failures, rate limiting, redaction,
   empty cache, concurrent access, auth, and polling cost.

Acceptance requires fixture-based counter reconciliation, no sensitive cache
content in HTML/JSON, and unchanged read-through behavior and latency bounds.
Rollback disables only the admin listener.
