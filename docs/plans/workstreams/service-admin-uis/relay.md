---
title: Relay Admin UI Brief
status: partially-implemented
last_verified: 2026-08-11
---

# Relay (`zuk`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md) and the
[shared contract](README.md). This is the operational reference for the
[PLC](plc.md), [AppView](appview.md), and [Mikrus](mikrus.md) briefs.

## Outcome and current evidence

`zuk` already serves an authenticated operations dashboard. It provides an
overall view plus a selectable per-upstream view, health and metrics, live
events, crawl inventory state, connection/retry state, event-kind counts, and
crawl/reconnect/disconnect actions. `GZAdminUIAuthManager` provides a
service-scoped session and CSRF rotation, and `nixos/modules/zuk.nix` loads
`RELAY_ADMIN_PASSWORD_FILE` through a systemd credential.

The remaining work is architectural convergence: the dashboard is currently
custom HTML in `Garazyk/Binaries/zuk/DashboardHTML.m` and is registered from
`zuk`'s main server. It must become the Relay-owned `GZAdminUIRelayPack`, use
the shared assets, and run on the dedicated listener required by ADR 0033.

## Dashboard shape

- **Overview:** health, uptime, current sequence, connected/configured sources,
  event rate, subscribers, validation failures, and last event age.
- **Sources:** overall and per-upstream events, event-kind distribution,
  connection age, cursor, inventory/account counts, crawl state, retries, last
  error, and last event.
- **Delivery:** downstream subscribers, broadcasts/drops, queue pressure, and
  slow-consumer disconnects when these counters exist.
- **Actions:** request crawl, add/remove/connect/disconnect one upstream, and
  reconnect/disconnect all. All remain session plus CSRF protected.

## Slices and acceptance

1. Extract a Relay snapshot protocol from `RelayAPIHandler` and
   `RelayUpstreamManager`; keep per-upstream reads synchronized and bounded.
2. Move rendering/routes into a Relay-owned pack without losing the live
   overall/per-source inspector or accessible table behavior.
3. Start `GZAdminUIHost` on a configurable loopback admin port with concurrency
   8; leave protocol and firehose routes on the service listener.
4. Replace the dashboard's custom CSS/JS with shared tokens and components,
   preserving 200% zoom, reduced motion, keyboard focus, empty states, and
   narrow-screen table access.
5. Extend `nixos/modules/zuk.nix` and its VM/smoke coverage for the separate
   port while keeping the existing password file reusable.

Acceptance requires parity with the live dashboard, independent sessions beside
another service UI, mutation auth/CSRF negative tests, a sustained firehose
during UI polling, and no token in browser requests or rendered assets.

Rollback keeps the current dashboard available until the pack and dedicated
listener pass; it never weakens the existing session gate.
