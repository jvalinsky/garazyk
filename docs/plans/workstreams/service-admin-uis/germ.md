---
title: Germ Admin UI Brief
status: planned
last_verified: 2026-08-11
---

# E2EE mailbox (`germ`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
Apply the stricter of this brief and the [Chat privacy rules](chat.md).

## Outcome and evidence

Add the first Germ admin pack without turning an E2EE transport into a metadata
inspection tool. Germ stores ephemeral and rendezvous mailbox addresses plus
opaque ciphertext in `germ-mailbox.db`, authenticates XRPC calls through
`ChatAuthManager`, and currently exposes only a plain health route. It has no
operator credential or operational counters.

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

1. Add aggregate counters at mailbox service boundaries and cheap expiry/queue
   gauges maintained by writes or scheduled maintenance.
2. Create `GZAdminUIGermPack` with aggregate-only response models and tests that
   reject forbidden keys.
3. Add a dedicated loopback listener, operator password-file configuration,
   scoped session, lifecycle composition, and packaging/NixOS options.
4. Test empty and high-volume mailboxes, expiration, rendezvous, auth failures,
   concurrency, response-key allowlists, session rejection, and polling cost.

Acceptance requires an automated assertion that no response contains mailbox
addresses, agent references, ciphertext, or tokens, plus unchanged mailbox
delivery semantics. Rollback disables the UI and leaves mailbox state untouched.
