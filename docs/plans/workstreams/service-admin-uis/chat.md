---
title: Chat Admin UI Brief
status: planned
last_verified: 2026-08-11
---

# Chat (`syrena-chat`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
The privacy rules also constrain [Germ](germ.md); PDS identity dependencies are
tracked in the [PDS brief](pds.md).

## Outcome and evidence

Move the existing Chat pack into `syrena-chat` and turn it into an operational
surface rather than a message browser. The current pack lists conversations and
messages and can lock a conversation. It hides E2EE ciphertext behind a label,
but can preview plaintext messages. The service already has an admin secret and
ATProtoJWT validation, and exposes only a minimal health response.

## Dashboard shape

- **Overview:** health, uptime, conversations/groups/members, message rate,
  delivery failures, locked conversations, auth failures, and storage pressure.
- **Traffic:** aggregate counts and latency by endpoint and plaintext/E2EE mode.
  Never calculate aggregates by decrypting or inspecting message content.
- **Moderation:** bounded conversation metadata, lock state, member count, last
  activity, and audit history. Message bodies are hidden by default; any
  explicitly authorized plaintext inspection is separately audited and may be
  omitted from the first embedded release.
- **Actions:** lock a conversation; unlock or content inspection only if a
  service-level policy and typed method exist.

## Slices and acceptance

1. Define privacy-safe counters at Chat service and moderation boundaries.
2. Move the pack under Chat ownership, remove default plaintext previews, and
   use an allowlisted metadata model rather than rendering backend dictionaries.
3. Embed the session-gated listener and add password-file/loopback deployment
   options without reusing user ATProtoJWTs as operator sessions.
4. Test E2EE/plaintext fixtures, redaction, lock audit, pagination, missing PDS
   or PLC dependencies, auth/CSRF rejection, and concurrent message delivery.

Acceptance requires no ciphertext or default message content in dashboard
responses, no delivery regression, and auditable mutations. Rollback keeps the
compatibility pack but does not restore unsafe previews.
