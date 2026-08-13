---
title: Germ Admin UI Brief
status: partially-implemented
last_verified: 2026-08-12
---

# E2EE mailbox (`germ`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
Apply the stricter of this brief and the [Chat privacy rules](chat.md).

## Outcome and evidence

Germ embeds `GZGermAdminUIPack` on a password-gated loopback listener
(`127.0.0.1:2599`) with aggregate-only HTMX partials (health / flow / storage)
fed from `GET /_admin/metrics`. NixOS module and deployment example landed
earlier (`22474f0f`, `6079815d`).

**2026-08-12:** Fixed an ARC lifetime bug where `GZAdminUIHost` was released
before `GZServiceLifecycle` returned (listener accepted TCP but never
dispatched). Host is now retained for the service lifetime (same pattern as
chat/jelcz). Checked-in smoke:
`deno run -A scripts/test/germ_admin_loopback_smoke.ts` — login, overview
shell, 8 rounds of live metrics partials, and privacy-key rejection on
`/_admin/metrics` (exit 0).

## Dashboard shape

- **Overview:** health, uptime, active/expired ephemeral addresses, registered
  rendezvous addresses, queued opaque messages, deliveries, polls, misses,
  expirations, auth failures, and database pressure.
- **Flow:** rate and error aggregates for claim, deliver, poll, rendezvous
  registration, and rendezvous delivery; queue age uses coarse buckets.
- **Privacy:** never render ciphertext, mailbox addresses, agent references,
  DID mappings, access tokens, or row-level message history. Do not expose a
  search box for people or addresses. Small-count buckets may be rounded or
  withheld to reduce correlation risk.
- **Actions:** first release is read-only. A future purge-expired action must be
  a typed maintenance operation with aggregate result, confirmation, audit, and
  CSRF; it must not return deleted identifiers.

## Slices and acceptance

1. ~~Add aggregate counters at mailbox service boundaries and cheap expiry/queue
   gauges maintained by writes or scheduled maintenance.~~ **Done.**
2. ~~Create `GZAdminUIGermPack` / `GZGermAdminUIPack` with aggregate-only
   response models.~~ **Done** (forbidden-key assertion in loopback smoke).
3. ~~Add a dedicated loopback listener, operator password-file configuration,
   scoped session, lifecycle composition, and packaging/NixOS options.~~
   **Done** (retain fix 2026-08-12).
4. ~~Loopback smoke for live metrics rendering + privacy assertions.~~
   **Done 2026-08-12** via `scripts/test/germ_admin_loopback_smoke.ts`.
   High-volume mailbox fixture stress remains optional hardening.

Acceptance requires an automated assertion that no response contains mailbox
addresses, agent references, ciphertext, or tokens, plus unchanged mailbox
delivery semantics. Rollback disables the UI and leaves mailbox state untouched.
