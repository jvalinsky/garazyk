---
title: Blob Garbage Collection
---

# Blob Garbage Collection

## Overview

Garazyk PDS does not currently ship an automated garbage collector for
orphaned blobs. The implemented blob lifecycle is simpler:
- uploads store blob data plus metadata
- sync and service surfaces can list blobs for a DID
- explicit delete flows remove a blob on purpose

Everything beyond that, such as mark-and-sweep jobs, dry-run GC commands,
grace-period retention, or repair tooling, is still design work rather than
current behavior.

## What The Current Implementation Actually Does

### Uploads Persist Two Things

`BlobStorage` computes a CID, stores provider data if needed, and writes blob
metadata into the actor store. This is enough to make the blob retrievable and
listable, but it is not enough to infer whether the blob is still referenced by
records later.

### Deletion Is Explicit

`com.atproto.repo.deleteBlob` routes through `PDSBlobService` and `BlobStorage`.
The current path removes actor-store metadata first and then asks the provider
to delete the blob data.

That is an intentional design choice: the current codebase trusts a direct
delete request more than it trusts a background job trying to guess whether a
blob is still reachable.

### Enumeration Exists Without GC

The server can already enumerate blobs through `com.atproto.sync.listBlobs` and
the blob service list methods. That gives operators and sync consumers a way to
inspect blob ownership today without pretending that a safe sweep phase exists.

## Why Automated GC Is Not Shipped Yet

A correct blob GC is mostly an invariants problem, not a loop-over-records
problem.

Before a background collector can safely delete anything, the implementation has
to answer:
- whether provider storage is shared or deduplicated across DIDs
- how record updates, deletes, imports, and blob writes interact in flight
- which repository state is authoritative for reference scanning
- how operators will inspect and dry-run the cleanup before anything destructive
  happens

The current tree does not answer those questions completely, so it should not
document a shipped collector.

## What Operators Can Use Today

The current operational toolbox is smaller but real:
- `com.atproto.sync.listBlobs` for inspection
- `com.atproto.repo.deleteBlob` for intentional cleanup
- `pds_blob_count` and `pds_blob_storage_bytes` metrics for overall capacity
- the admin metrics handler for dashboard-friendly summaries

```bash
curl -s http://localhost:2583/metrics | rg '^pds_blob_(count|storage_bytes)'
```

If you need to reduce blob pressure for a specific DID today, use listing plus
explicit deletion. Do not look for `kaszlak gc blobs`, `kaszlak verify blobs`,
or `kaszlak repair blobs`; those command surfaces are not implemented.

## Why This Simpler Model Is Still Useful

The absence of automated GC is a limitation, but it also keeps the operational
story honest:
- blob deletion is intentional rather than heuristic
- metrics describe what the server has actually stored
- future GC work can be designed around real invariants instead of retrofitting
  a speculative CLI

That is a better trade-off than shipping a destructive background operation with
unclear ownership semantics.

## Design Notes For Future GC Work

If blob garbage collection becomes a roadmap item, the implementation should
start with storage semantics, not a command name.

The minimum checklist is:
- define whether provider blobs need reference counting across DIDs
- add a trustworthy record-reference scan over persisted repository state
- make dry-run output mandatory before destructive cleanup
- ensure metadata deletion and provider deletion cannot silently diverge
- add observability for reclaimed bytes, skipped blobs, and repair conditions

Only after those pieces exist should the docs describe a GC workflow as
something operators can actually run.

## Summary

Today the safe mental model is simple: explicit delete, no automatic sweep.
Treat older references to `PDSCLIGCCommand.m` or `kaszlak gc blobs` as
historical design notes, not part of the shipped Garazyk PDS toolchain.\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n