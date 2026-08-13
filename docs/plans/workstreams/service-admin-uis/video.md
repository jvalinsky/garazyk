---
title: Video Admin UI Brief
status: in-progress
last_verified: 2026-08-12
---

# Video (`jelcz`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
The narrow PDS dependency is coordinated with the [PDS brief](pds.md).
Content-addressed delivery semantics are governed by
[ADR 0036](../../../adr/0036-content-addressed-video-distribution.md) and
[workstream 12](../12-content-addressed-video.md); MUXL packaging by
[workstream 10 Phase 9](../10-dasl-conformance.md).

## Outcome and evidence

Operators of `jelcz` need one place that answers four questions, in order:

1. **Is the worker healthy and keeping up?** Queue depth, concurrency, oldest
   age, 24h success/fail, PDS upload posture.
2. **Which jobs explain a problem?** Bounded recent rows with state filters,
   progress, and a **product** badge (`HLS` / `CA VOD` / `MUXL`).
3. **What does `/watch` actually serve right now?** Distribution posture —
   CA MASL vs filesystem HLS, MUXL packaging, mirror fetch, reclaim sweep —
   without leaking store paths or credentials.
4. **What safe action can I take?** Retry a failed job. Cancel/purge stays
   hidden until a typed cleanup contract exists.

The pack is embedded under Video ownership (`GZJelczAdminUIPack`) with a
dedicated loopback listener. Job detail is an **allowlisted DTO**: never
`service_auth_token`, never absolute paths, never S3/PDS secrets. Free-form
errors collapse to short categories (`transcode`, `pds-upload`, `ca-manifest`, …).

## Dashboard shape

| Tab | Purpose |
| --- | --- |
| **Overview** | Health + queue + **Distribution posture** summary card |
| **Jobs** | Per-state counts, filter chips, recent rows (product + progress), sectional detail (Identity / Pipeline / Distribution / Failure), retry on failed |
| **Distribution** | Operator explanation of watch mode and feature flags (CA / MUXL / mirrors / sweep) |
| **Capacity** | Worker limits + delivery/reclaim flags (not path listings) |

## UX principles (post CA VOD)

- Treat **transcode queue** and **content-addressed distribution** as two
  related but distinct stories. Do not bury CA flags only under Capacity.
- Prefer **product labels** over raw schema column names in tables.
- Prefer **posture** (on/off/configured) over filesystem inventory.
- Empty, degraded, and unreachable states must remain distinct.
- Polling must not `COUNT(*)` the full jobs table via row scans when
  `jobCountsByStateWithError:` is available.

## Slices and acceptance

1. ~~Synchronized worker/queue snapshot and per-state counters.~~ **Done**
   (embedded snapshot; cheap `GROUP BY` counts on `GZJelczDatabase`).
2. ~~Allowlisted job DTO excluding tokens/paths/unrestricted errors.~~ **Done**
   (`JelczAdminUIPackTests` redaction + category tests, 2026-08-12).
3. ~~Pack under Video ownership + embedded listener.~~ **Done** (`jelcz` main).
4. ~~Password-file / bind / NixOS options.~~ **Done** (prior M4 packaging).
5. **In progress (2026-08-12):** CA-aware Overview / Distribution / Jobs product
   columns; remaining: live browser smoke against `jelcz` with CA on/off, and
   retry audit under concurrent workers.

Acceptance requires a regression test proving stored service-auth tokens never
reach HTML/JSON, no worker throughput regression from admin polling, and safe
behavior when the PDS is unavailable. Rollback disables only the admin
listener; secret-bearing generic detail must not return.
