# ADR 0013 — Blob lifecycle conformance

**Status:** Accepted
**Date:** 2026-07-27

## Context

AT Protocol blobs begin as temporary uploads. They are not downloadable or
listable until a current record in the repository references them. Garazyk had
no temporary/referenced state, no record-to-blob reference tracking, inactive
usage triggers, and an upload path with no account-wide storage limit.

## Decision

Garazyk models blobs as `temporary` or `referenced` and records references from
current repository records. It applies both required reclamation mechanisms:

1. Deleting a record removes blob metadata when no other current record in that
   repository references the CID. This promptly reclaims references created by
   normal record lifecycle operations.
2. A startup and hourly sweep removes never-referenced temporary blobs after a
   configurable grace period. This covers uploads which are never attached to
   a record and provider bytes orphaned across repositories.

The default temporary-blob grace period is six hours. Configuration and the
`PDS_BLOB_TEMPORARY_GRACE_PERIOD_SECONDS` environment override are clamped to a
one-hour minimum.

Per-account blob storage is limited at upload using the live `account_usage`
counters. The default limit is 10 GiB and may be configured; a rejected upload
does not leave provider bytes behind.

Blob data, file paths, and blob listings require referenced metadata for the
requested owner DID. Missing DIDs and failed store lookups deny access rather
than falling through to the provider.

## Consequences

- Uploading a blob no longer makes it immediately downloadable or visible in
  `listBlobs`; clients must successfully create a referencing record first.
- Record deletion can make a previously downloadable blob unavailable as soon
  as the last same-repository reference is removed.
- Temporary uploads remain available to clients only for attachment, not
  retrieval, during the grace interval; a later sweep reclaims unreferenced
  data.
- Existing databases gain lifecycle metadata, reference tracking, installed
  usage triggers, and backfilled usage through the V6 and V7 migrations.

## Amendment (2026-07-27): block usage attribution

The six `account_usage` triggers were adopted as-written on the basis that
they were already correct and had merely never been installed. That held for
four of them. The two block triggers attributed bytes with
`(SELECT did FROM records LIMIT 1)`, which resolves to NULL whenever a block
is written before the shard has any record row — that is, on every account's
initial commit, since `PDSRepositoryService+RepoInit` stores the empty-tree
commit block before any record exists.

Because SQLite treats NULL as distinct from NULL for uniqueness,
`ON CONFLICT(did)` could not merge those rows: each such block created its own
NULL-keyed `account_usage` row, and the real account's `repo_bytes` was short
by exactly the bytes stranded on them. The same `records`-keyed assumption
also made V7's backfill skip a shard that had only its initial commit block.

`ipld_blocks` now carries the owning `did`, written by
`-[PDSActorStore putBlock:forDid:]`, and the two triggers attribute via
`NEW.did`/`OLD.did`. Migration V8 adds and backfills the column, reinstalls
the triggers against it, discards the orphan rows, and recomputes `repo_bytes`
from `ipld_blocks` — a recomputation rather than an accumulation, so the
repair is idempotent and also covers shards V7 skipped. The owner is resolved
from the shard's `rotation_keys`/`signing_keys` singletons, which are written
at account creation and are therefore populated before the first block.

Under-counting `repo_bytes` is a quota-accounting understatement, not an
over-charge: affected accounts were credited less storage than they used. The
magnitude is one commit block per affected account, so no account is expected
to have been wrongly admitted past a quota by a meaningful margin.
