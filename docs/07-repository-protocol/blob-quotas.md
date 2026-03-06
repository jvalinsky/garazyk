---
title: Blob Quotas
---

# Blob Quotas

## Overview

September PDS does not currently implement a full per-account storage quota
system. The shipped protection model is narrower and easier to reason about:
reject obviously bad uploads early, limit how quickly a DID can create blob
pressure, and expose enough metrics for operators to watch overall capacity.

**What exists today:**
- MIME-aware size validation in `MimeTypeValidator`
- Route-level payload checks in `com.atproto.repo.uploadBlob`
- Per-DID blob upload rate limiting in `RateLimiter`
- Global blob count and storage metrics

**What does not exist yet:**
- Per-account byte quotas
- Quota status, set, reset, or repair CLI commands
- Automatic quota tier management

## Why The Current Design Is Smaller

A true storage quota sounds straightforward, but it creates hard accounting
questions at write time. The server has to know which database is authoritative,
how provider-level deduplication affects per-user usage, and what should happen
if a delete races with a record update or import. The current implementation
avoids inventing answers it cannot enforce consistently.

That is why the codebase currently focuses on three simpler guarantees:
- validate uploads before storing provider data
- bound write pressure per DID with rate limiting
- expose aggregate capacity signals for operators

## Effective Limits On Uploads

### Route-Level Guardrail

`com.atproto.repo.uploadBlob` rejects requests larger than 1 MiB before the blob
service runs. In practice this is the tightest limit in the current request
path, so it wins even when the MIME category would allow a larger payload.

### MIME-Aware Size Validation

`BlobStorage` still sends each upload through `MimeTypeValidator`. That keeps
the storage layer honest if the route-level cap changes later or if other blob
entry points are added.

**Current category caps:**
- Images: 5 MiB
- Videos: 50 MiB
- Audio: 10 MiB
- Fonts: 10 MiB
- 3D models: 100 MiB
- Documents: 10 MiB
- Applications and other types: 5 MiB

### Per-DID Upload Rate Limiting

Blob uploads also have a separate per-DID rate limit. This is the closest thing
the current codebase has to a quota feature: it limits how quickly an account
can create new blob pressure, not how many retained bytes it owns forever.

```json
{
  "rate_limit": {
    "enabled": true,
    "blob_limit": 50,
    "blob_window": 3600
  }
}
```

Environment overrides:
- `PDS_RATELIMIT_BLOB_LIMIT`
- `PDS_RATELIMIT_BLOB_WINDOW`

## Where These Limits Live

- Request-size rejection happens in
  `ATProtoPDS/Sources/Network/XrpcRepoMethods.m`.
- MIME validation and blob metadata writes live in
  `ATProtoPDS/Sources/Blob/MimeTypeValidator.m` and
  `ATProtoPDS/Sources/Blob/BlobStorage.m`.
- Blob rate-limit configuration is loaded in
  `ATProtoPDS/Sources/App/PDSConfiguration.m` and enforced in
  `ATProtoPDS/Sources/Network/RateLimiter.m`.

This split matters operationally. The transport layer protects the server from
oversized requests, while the storage layer remains the last line of defense for
blob correctness.

## Operational Visibility

Because there is no per-user quota ledger, operators should think in terms of
system capacity and per-user write pressure rather than a user-facing quota
balance.

The current observability surfaces are:
- Prometheus metrics `pds_blob_count` and `pds_blob_storage_bytes`
- The admin metrics handler in
  `ATProtoPDS/Sources/Admin/PDSAdminHandler.m`
- Explicit blob listing and deletion flows through the blob service and XRPC
  methods

```bash
curl -s http://localhost:2583/metrics | rg '^pds_blob_(count|storage_bytes)'
```

For account-level inspection, use the implemented blob list and delete flows
rather than looking for quota status or repair commands that do not exist.

## Current Limitations

- There is no byte-accurate per-account storage quota in the current tree.
- There is no shipped `kaszlak quota` command family.
- There is no quota repair or reset tooling after manual database edits.
- Aggregate metrics exist, but per-user blob storage metrics do not.

Older docs that describe `kaszlak quota status`, `quota set`, or `quota reset`
should be treated as future design notes, not current behavior.

## If You Need Real Quotas

The next step is not to add a CLI first. The next step is to define a reliable
accounting model.

That work should answer:
- whether quota state lives in actor databases, a service database, or derived
  metrics
- how shared or deduplicated provider blobs count against multiple DIDs
- which write boundary enforces the quota before persistence becomes visible
- what introspection and repair tooling operators need when accounting drifts

Once those invariants are explicit, the CLI and admin surfaces can describe a
real feature instead of a hypothetical one.

## Summary

Current blob protection in September PDS is implemented as validation, rate
limiting, and observability. It is not a full quota subsystem yet, and operators
should run the server with that smaller mental model.
