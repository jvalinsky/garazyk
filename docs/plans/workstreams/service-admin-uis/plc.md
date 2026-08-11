---
title: PLC Admin UI Brief
status: complete
last_verified: 2026-08-11
---

# PLC directory (`campagnola`)

**Authority:** workstream 11 [M3](../11-per-service-admin-uis.md#m3-plc-pilot-campagnola),
the [shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
See [Relay](relay.md) for the session-gated reference and [PDS](pds.md) for the
operator flows that depend on DID resolution.

## Outcome and evidence

**Implemented and verified 2026-08-11.** Phase 30 is closed. This brief
governs the PLC pilot only; no other service pack is being rolled out alongside
it.

Make `campagnola` the first shared-library pilot. Existing PLC UI routes cover
DID resolution/history, health, metrics, list, and export. `PLCMetrics` already
tracks requests, errors, cache hits/misses, verification outcomes, operation
types, and latency. Replica mode adds `PLCSyncEngine` state, cursor, ingested and
failed totals, last sync, pause/resume, and sync-once primitives. PLC currently
has no admin credential, so the listener must be absent when no password is
configured.

## Dashboard shape

- **Overview:** primary/replica mode, read-only state, health, operations, DIDs,
  request/error rate, verification failures, cache hit ratio, and last sync.
- **Replication:** upstream, state, cursor, lag when upstream head is known,
  batch/worker settings, ingested/failed totals, retry age, and recent errors.
- **Directory:** bounded DID lookup, current document summary, operation-chain
  length, nullification state, and audit verification result.
- **Metrics:** request and resolution latency distributions and cache behavior.
- **Actions:** replica-only pause, resume, and sync once. DID submission remains
  a protocol operation, not a generic dashboard mutation.

## Slices and acceptance

1. Add a thread-safe PLC snapshot adapter over `PLCMetrics`, the store, and the
   optional sync engine; primary mode must not invent replica fields.
2. Move the existing PLC pack/client/routes under `Garazyk/Sources/PLC/AdminUI/`.
3. Compose the admin host into `PLCRuntimeComposite`; add admin bind/port and a
   password-file path, with loopback/default-off behavior.
4. Add a `campagnola` NixOS module or shared service-module integration using a
   systemd credential rather than a Nix-store password.
5. Test primary, replica, empty-store, error, pause/resume, wrong-password,
   missing-CSRF, cookie-isolation, concurrency-8, and clean-stop behavior.

## Current evidence (2026-08-11)

- `GZPLCAdminSnapshot` takes a serial store/metrics/sync view using exact,
  constant-size count queries rather than materializing the directory or log,
  with
  primary/replica mode, replication fields, cache/verification/latency data,
  and a 50-entry mutation audit.
- `campagnola` runs a separate loopback `GZAdminUIHost` with concurrency 8;
  absent password configuration omits that listener. `--admin-ui-host`,
  `--admin-ui-port`, `GARAZYK_PLC_ADMIN_UI_HOST`,
  `GARAZYK_PLC_ADMIN_UI_PORT`, `--admin-password-file`, and
  `GARAZYK_PLC_ADMIN_PASSWORD_FILE` are supported. The NixOS module uses a
  systemd `LoadCredential` and never stores the password in Nix derivations.
- Native configure/build, `PLCAdminSnapshotTests` (6), `PLCAdminUIPackTests`
  (8), `CampagnolaCommandTests` (5), `UIServerRuntimeTests` (28), Admin UI
  design-system/asset synchronization, module-boundary, namespace,
  recursive-setter, host-process-exit, Nix parse, and diff checks passed. The
  focused pack tests cover wrong password, service-cookie
  isolation, missing/stale CSRF, mutation audit, loopback, concurrency, and
  password-file redaction, and clean shutdown of both loopback listeners.
- The local-network `./build/tests/AllTests --gated=run` completed 5,018 tests
  with 0 failures. `scripts/admin_ui_browser_smoke_test.ts` also passed against
  a fresh binary topology, exercising authenticated browser sessions and CSRF.
- After OrbStack Docker 29.4.0 became available, `docker build -f
  docker/Dockerfile.gnustep -t garazyk-gnustep .` passed. The initial Linux
  build found that GNUstep treats `dispatch_queue_t` as non-object; the adapter
  now uses the repository's `PDS_DISPATCH_QUEUE_STRONG` macro. The resulting
  `garazyk-gnustep` image
  (`sha256:2cdad4e4c38364d2327e9eac81ba0f7a43535f48c6bb039981099afddd296f0f`)
  also passed `campagnola serve --help` under its runtime user.


Acceptance is the M3 gate: `campagnola` and the compatibility host serve the
same pack, can run together without session collision or starvation, and no
admin listener exists when the password is absent. Rollback removes only the
embedded listener and leaves the compatibility pack intact.
