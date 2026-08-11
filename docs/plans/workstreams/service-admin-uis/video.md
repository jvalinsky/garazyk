---
title: Video Admin UI Brief
status: planned
last_verified: 2026-08-11
---

# Video (`jelcz`)

**Authority:** [workstream 11](../11-per-service-admin-uis.md), the
[shared contract](README.md), and [ADR 0033](../../../adr/0033-per-service-embedded-admin-uis.md).
The narrow PDS dependency is coordinated with the [PDS brief](pds.md).

## Outcome and evidence

Move the existing Video pack into `jelcz` and expose the worker and queue state
needed to operate transcoding. Current UI routes provide health, jobs, job
detail, quotas, and retry. `VideoWorker` has active state, concurrency, pending
scans, progress, retries, and processing stages. `JelczDatabase` stores a
`service_auth_token` with each job, while the current generic detail renderer
enumerates every returned field. The embedded plan must replace that with an
explicit safe allowlist before serving job detail.

## Dashboard shape

- **Overview:** health, worker active/capacity, queue depth and oldest age,
  throughput, failures/retries, processing latency, storage pressure, and PDS
  upload health.
- **Jobs:** overall and per-state counts, bounded rows, age, progress, media
  dimensions/duration, retry count, stage and sanitized error category.
- **Capacity:** configured upload/duration limits, active workers, temp/output
  space, HLS variant counts, and storage backend status.
- **Actions:** retry a failed job. Cancel or purge requires a typed worker/store
  operation and storage cleanup contract before it appears.

## Slices and acceptance

1. Add a synchronized worker/queue snapshot and materialized per-state counters;
   avoid counting the full jobs table on each refresh.
2. Replace dictionary enumeration with an allowlisted job DTO that excludes
   `service_auth_token`, raw paths, PDS credentials, and unrestricted errors.
3. Move the pack under Video ownership, retain only the narrow PDS client calls,
   and embed the dedicated session-gated listener.
4. Add password-file, bind/port, and storage-safe NixOS/container options.
5. Test each job state, capacity, retry audit, PDS/storage failures, redaction,
   auth/CSRF, worker concurrency, and HLS/upload progress during polling.

Acceptance requires a regression test proving stored service-auth tokens never
reach HTML/JSON/logs, no worker throughput regression, and safe behavior when
the PDS is unavailable. Rollback retains the compatibility UI only after the
allowlist fix; secret-bearing generic detail must not return.
