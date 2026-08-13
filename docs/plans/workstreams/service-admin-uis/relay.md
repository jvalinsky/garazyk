---
title: Relay Admin UI Brief
status: partially-implemented
last_verified: 2026-08-12
---

# Relay (`zuk`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md) and the
[shared contract](README.md). This is the operational reference for the
[PLC](plc.md), [AppView](appview.md), and [Mikrus](mikrus.md) briefs.

## Related active resource work

[Workstream 17](../17-zuk-relay-resource-bounds.md) owns the P0 relay
cursor/resource incident and will extend this existing Relay-owned snapshot
and pack with byte-counted ingress, replay, subscriber, persistence,
validation, crawl-admission, cgroup memory, and authoritative upstream-set
signals. It must add fields here rather than create a second dashboard. The
current UI acceptance below remains valid; Phase 41 records the additive UI
and NixOS evidence.

## Outcome and current evidence

The legacy dashboard has been converged onto a Relay-owned operations pack.
`GZRelayAdminSnapshot` serializes bounded reads of `RelayMetrics` and
`RelayUpstreamManager`; `GZRelayAdminUIPack` renders health, totals, source
state, crawl state, repository count, events, cursors, and reconnect attempts
from that view. `zuk` runs the pack on a password-gated, loopback-default
`GZAdminUIHost` listener (concurrency 8), while the protocol/firehose listener
keeps only its read-only relay monitoring routes. The same pack remains in
the former monolithic admin UI as a read-only compatibility surface until M5.

`RELAY_ADMIN_PASSWORD_FILE` is loaded through a systemd credential in
`nixos/modules/zuk.nix`; failures are redacted and neither the password nor its
contents are put in the Nix store. The browser receives only the Relay-scoped
HttpOnly session cookie and rotating CSRF nonce. Reconnect, disconnect, and
request-crawl controls exist only on the embedded listener and require both.

## Dashboard shape

- **Overview:** health, current sequence, connected/configured sources, and
  aggregate events.
- **Sources:** per-upstream connection state, cursor, inventory count, crawl
  state, retry count, and event total in an accessible polling table.
- **Actions:** request crawl plus reconnect/disconnect all; all require a
  scoped session and one-time CSRF nonce. DID/protocol operations remain on
  their protocol surface.

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

## Current validation and remaining acceptance

On **2026-08-12**, fresh native configuration and `AllTests --gated=run`
passed (exit 0, ~9.6 min) with **11 GB** free on the host volume (prior
2026-08-11 disk-full block cleared). Focused relay suites re-verified the same
day: `RelayAdminUIPackTests` (8/0), `ZukCommandTests` (6/0, including
post-namespace-rename source composition check), and `UIServerRuntimeTests`
(28/0).

On 2026-08-11, focused evidence also included clean listener shutdown under
loopback access. The pack tests cover empty/populated snapshots,
scoped-session isolation, missing/stale CSRF, one-time CSRF rotation, mutation
state, default loopback binding, the 8-request limit, credential-file
trimming/redaction, and compatibility-host route parity.
`scripts/admin_ui_visual_smoke_test.ts` and
`scripts/admin_ui_browser_smoke_test.ts` passed with real loopback
listeners and Chromium. The latter brought up a local PLC/PDS/Relay/AppView/
Germ/Mikrus/Beskid topology and verified login, session/CSRF rejection,
keyboard navigation, heading/tab semantics, CSP, and the Lab OAuth flow.

**Re-run (2026-08-12):** both browser and visual smokes passed on macOS after
the visual script was corrected to focus the autofocused password field instead
of tabbing past it.

**Re-run (2026-08-12, afternoon):** `scripts/test/nixos_zuk_module_smoke.sh`
passed on macOS (flake `nixosModules.zuk` type check + `eval-config.nix`
verification of `RELAY_ADMIN_PASSWORD_FILE` wiring). `scripts/test/relay_admin_loopback_smoke.ts`
passed: PLC/PDS/relay binary topology with fixed ports, loopback admin listener,
24 rounds of HTMX partial polling on metrics/sources while `subscribeRepos`
delivered commit events during post creation.

M4 live-event inspector fields restored on 2026-08-12 from bounded upstream
source fields (`lastEventAt`, `connectedAt`, capped `eventsByKind` ≤8) on
`GZRelayAdminSnapshot` / sources table — not a browser-side polling shortcut.
Evidence: `RelayAdminUIPackTests` (8).

**GNUstep/Linux binary gate (2026-08-12):** `garazyk-gnustep-toolchain:local`
built `zuk` Release (`cmake --build … --target zuk`) and
`zuk serve --help` printed admin-ui host/port options plus
`RELAY_ADMIN_PASSWORD(_FILE)` env docs (exit 0).

**Resolved (2026-08-11 → 2026-08-12):** the prior full-suite block from host
volume exhaustion (131 MB free, `NSPOSIXErrorDomain` 28 in
`AdminAuthSyncTests`) is no longer reproducing after freeing disk space.
Duplicate test processes from that attempt were terminated; the 2026-08-12
run was a single clean process with exit 0.

Rollback keeps the current dashboard available until the pack and dedicated
listener pass; it never weakens the existing session gate.
