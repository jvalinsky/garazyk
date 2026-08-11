---
title: PDS Admin UI Brief
status: planned
last_verified: 2026-08-11
---

# PDS (`kaszlak`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
PDS dependencies are visible in [PLC](plc.md), [Beskid](beskid.md),
[Chat](chat.md), and [Video](video.md), but the PDS UI reports only local state.

## Outcome and evidence

Embed the largest admin surface last. `kaszlak` owns the existing PDS, Ozone,
Security, Data Explorer, MST, and Lab packs. Current routes cover accounts,
invites, blobs, server statistics, audit logs, reports, moderation/security
operations, repository exploration, and protocol labs. The existing PDS pack
also renders fleet-wide Overview and Connections; those cross-service panels
are deleted under workstream 11 M5 rather than embedded.

## Dashboard shape

- **Overview:** health, uptime, accounts/repos/records/blobs, sequencer head and
  age, write/error rate, active sessions, moderation backlog, storage pressure,
  database pool/WAL health, and service dependency status only where the PDS
  itself already depends on it.
- **Accounts and invites:** bounded search/detail, account state, invite usage,
  and explicitly confirmed disable/takedown/delete operations.
- **Repositories and blobs:** safe repository summary, collection/cardinality,
  blob count/bytes, missing/orphan audit state, sequencer events, MST inspection,
  and cursor pagination. No raw SQL or unrestricted record dumps.
- **Moderation and security:** reports, audit history, OAuth/security diagnostics,
  and narrow actions with reason, subject, actor, result, and request ID.
- **Lab:** protocol diagnostics remain clearly separated from production
  mutations and inherit the same session and CSRF boundary.

## Slices and acceptance

1. Define one cheap PDS overview snapshot from existing health, sequencer,
   metrics, pool, moderation, and storage components; headline polling must not
   scan actor stores or blob directories.
2. Move all six packs and clients under PDS ownership, remove Overview and
   Connections, and keep the host service-agnostic.
3. Replace broad backend dictionaries with per-view DTO allowlists, especially
   for account email, tokens, audit payloads, repository records, and security
   material.
4. Embed the listener and internal token in `kaszlak`; migrate its admin
   credential to operator login without exposing backend tokens to the browser.
5. Add NixOS/container secret-file, bind/port, backup-aware, and reverse-proxy
   examples; move the Lab OAuth scenario to the PDS listener.
6. Test each pack, dangerous-action confirmation, audit, auth/CSRF, pagination,
   empty/large stores, pool starvation, concurrent repository writes, 200% zoom,
   and scenario/topology compatibility.

Acceptance requires all six local packs to work without fleet credentials,
bounded polling under a representative multi-actor database, no protocol-write
regression, and clean Deno topology/scenario gates. Rollback returns the packs
to the compatibility host while leaving the PDS protocol listener unchanged;
it never restores fleet-wide Overview or Connections credentials.
