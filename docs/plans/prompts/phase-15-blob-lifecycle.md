---
phase: 15
title: Blob lifecycle conformance
status: in-progress
agent: worker
depends_on: []
---

# Phase 15: Blob lifecycle conformance

## Progress

Started 2026-07-26 in worktree `../garazyk-storage` (branch `phase-15-16`).
Read both spec pages, workstream 01 S9, Schema.m, PDSSchemaManager.m,
ActorStore.m, PDSMigrationManager.m. Beginning slice 1.

Resumed 2026-07-27 after slices 1-2. Beginning slice 3: enforce the
account-wide blob-byte quota from the live, backfilled `account_usage` row
before provider storage.

## Mission

Implement the published blob lifecycle, which Garazyk currently does not model
at all, and activate the usage accounting that already exists in the tree but
was never installed. Workstream 01 § S9 is authoritative.

Read the two spec pages before writing code — this phase is conformance work
and the contract is external:

- <https://atproto.com/specs/blob>
- <https://atproto.com/guides/blob-lifecycle>

The contract in brief: uploaded blobs are **temporary**, not retrievable and
not listed; they become **referenced** and publicly accessible only when a
record referencing them is created; on record delete the server checks whether
any other current record **in the same repository** references the blob and
deletes it if not; never-referenced temporary blobs are swept after a grace
period with a one-hour firm floor. Reclamation is therefore **both** an
immediate reference check and a time-based sweep — not a choice between them.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S9
  (authoritative; if this prompt disagrees, the workstream wins)
- `Garazyk/Sources/Database/Schema.m:129-195` — six complete
  `kPDSAccountUsage*` triggers that are never installed. Do not rewrite them;
  install them.
- `Garazyk/Sources/Admin/Diagnostics/BlobAudit/PDSBlobReferenceScanOperation.m`
  — existing reference-scan logic, currently report-only. Reuse its traversal
  for the sweep rather than writing a second one.
- Workstream 07's O2 phase B lesson: a schema rewrite must carry over every
  constraint (FKs, CHECKs, DEFAULTs), not just columns and the PK.

## Decisions already taken (do not re-litigate)

- Both reclamation mechanisms ship: per-repository delete-on-last-reference,
  and a grace-period sweep. Grace is configurable, floor one hour, default
  several hours.
- Per-account quota is configurable and **enabled by default**, enforced at
  upload with a quota-exceeded error.

## Scope and order

One coherent slice per commit, in this order. The order matters: quota
counters must be live and backfilled before enforcement, and the visible
read-path restriction lands last.

1. **Model the lifecycle.** Add referenced/temporary state to `blobs` and a
   record→blob reference table. Reconcile the two divergent `blobs`
   definitions — `Database/Schema.m:108` has
   `FOREIGN KEY (did) REFERENCES accounts(did)` and
   `Database/Schema/PDSSchemaManager.m:512` does not — into one authoritative
   schema as part of this migration.
2. **Install the usage triggers** during migration and backfill
   `account_usage` from existing `blobs`/`ipld_blocks`/records. Verify the
   already-wired consumers stop reading zeros:
   `Network/XrpcVendorPack.m:253-266`, `Services/PDS/PDSAccountService.m:585`,
   `Network/XrpcAdminPack+AccountInfo.m:93`.
3. **Enforce quota at upload** in `Blob/BlobStorage.m uploadBlob:`, using the
   now-live counters. A rejected upload must leave no provider bytes behind.
4. **Reference extraction.** Extract blob references on record create and
   delete. On delete, drop the blob only when no other current record in the
   same repository references it.
5. **Grace-period sweep** for temporary blobs, and clean up provider bytes on
   the metadata-save failure path at `Blob/BlobStorage.m:130-132` instead of
   deliberately orphaning them.
6. **Restrict the read path.** `getBlobWithCID:did:` and
   `blobFilePathWithCID:did:` (`Blob/BlobStorage.m:146,195`) serve only
   referenced blobs; the ownership check fails closed on both a nil `did` and
   a failed `storeForDid:` rather than falling through to the provider; and
   temporary blobs are excluded from `listBlobs`.

## Acceptance gate

Behavioural, end to end:

- An uploaded blob is **not** retrievable by CID and **not** listed.
- After a record referencing it is created, it is retrievable and listed.
- Deleting that record deletes the blob — but not while another record in the
  same repository still references it.
- A never-referenced blob survives inside the grace window and is swept after
  it.
- An upload that exceeds quota is rejected with a quota error and leaves no
  provider bytes.
- A blob request with a nil `did`, and one where the store lookup fails, are
  both denied rather than served.
- `account_usage` reflects real bytes and counts after upload, delete, and
  backfill.

Every schema change needs apply/rollback/re-apply migration coverage that
retains rows, indexes, foreign keys, and defaults.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently run
zero tests. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`). Confirm free disk before a gated
run — they flake with `SQLITE_FULL` near capacity, which is the same disk
pressure this phase exists to bound.

## Rollback

Each slice is a single-commit revert. Slice 6 is the visible behaviour change:
blobs that are readable today become unreadable until referenced. It lands
last, after the slice 2 backfill, and must be exercised against a real client
upload→reference→fetch flow before release. If a real client regresses,
revert slice 6 and capture its actual flow as a test case rather than
loosening the check. Schema slices roll back via their migration down path.

## On completion

Write the ADR recording the blob lifecycle implementation: the two
reclamation mechanisms and why both are required, the grace-period default and
floor, the quota default, and the read-path restriction's compatibility
impact. Update S9 status in workstream 01 with commit hashes, then set
`status: complete` here.
