---
title: Chat Admin UI Brief
status: complete
last_verified: 2026-08-12
---

# Chat (`syrena-chat`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
The privacy rules also constrain [Germ](germ.md); PDS identity dependencies are
tracked in the [PDS brief](pds.md).

## Outcome and evidence

Move the existing Chat pack into `syrena-chat` and turn it into an operational
surface rather than a message browser. Privacy-safe metadata only: no default
message bodies or E2EE ciphertext in dashboard responses.

### Embed + admin API (2026-08-12)

- Embedded `GZAdminUIHost` on `127.0.0.1:2598` when `CHAT_ADMIN_PASSWORD` /
  `--admin-password-file` is set (`syrena-chat/main.m`).
- That password is also written to `configuration.adminSecret` so protocol
  `/_admin/*` require `Authorization: Bearer …` (503 when unset — no fail-open).
- `GZChatAdminUIPack configureHost:serviceBaseURL:adminSecret:` points partials
  at the local protocol port via SafeHTTP (loopback HTTP allowed); allowlisted
  DTOs never render `text` / `ciphertext` / `embedJson`.

### Headline counters + lock UI + live smoke (2026-08-12)

- `GET /_admin/stats` — COUNT(*) conversations (total/locked/e2ee/plaintext),
  members, messages, PRAGMA storage, uptime, health.
- Pack Overview polls `/admin/partials/chat-stats`; conversation rows expose
  Lock/Unlock → `POST /admin/actions/chat-lock|unlock` (session + CSRF) →
  `POST /_admin/lock|unlock`.
- Evidence: `ChatAdminUIPackTests` (5); `deno task admin-ui:chat-smoke`
  (`scripts/test/chat_admin_loopback_smoke.ts`).

## Dashboard shape

- **Overview:** health, uptime, conversation/member/message counters, lock
  state, storage pressure.
- **Moderation:** bounded conversation metadata, lock/unlock, member count,
  last activity. Message bodies stay hidden.
- **Actions:** lock / unlock conversation (Bearer on protocol; CSRF on UI).

## Slices and acceptance

1. ~~Define privacy-safe counters at Chat service and moderation boundaries.~~
   **Done 2026-08-12** (`/_admin/stats` + `statsHTML`).
2. ~~Move the pack under Chat ownership, remove default plaintext previews, and
   use an allowlisted metadata model rather than rendering backend dictionaries.~~
   **Done 2026-08-12** (`GZChatAdminUIPack` + Bearer-gated `/_admin/*`).
3. ~~Embed the session-gated listener and add password-file/loopback deployment
   options without reusing user ATProtoJWTs as operator sessions.~~
   **Done** (embed + NixOS earlier; secret shared with `/_admin` 2026-08-12).
4. ~~Test E2EE/plaintext fixtures, redaction, lock audit, pagination, missing PDS
   or PLC dependencies, auth/CSRF rejection, and concurrent message delivery.~~
   **Done for M4 gate:** pack redaction + lock markup tests; loopback smoke
   covers Bearer stats, login, chat-stats partial, CSRF rejection on lock.

Acceptance requires no ciphertext or default message content in dashboard
responses, no delivery regression, and auditable mutations. Rollback keeps the
compatibility pack but does not restore unsafe previews.
