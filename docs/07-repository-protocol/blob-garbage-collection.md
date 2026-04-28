---
title: Blob Garbage Collection
---

# Blob Garbage Collection

## Overview

Garazyk PDS does not include an automated garbage collector for orphaned blobs. The blob lifecycle is:
- uploads store blob data plus metadata
- sync and service surfaces can list blobs for a DID
- explicit delete flows remove a blob on purpose

Mark-and-sweep jobs, dry-run GC commands, grace-period retention, and repair tooling are not implemented.

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

The codebase relies on direct delete requests rather than background jobs that guess blob reachability.

### Enumeration Exists Without GC

The server can already enumerate blobs through `com.atproto.sync.listBlobs` and
the blob service list methods. This allows operators and sync consumers to inspect blob ownership without a safe sweep phase.

## Why Automated GC Is Not Shipped Yet

A correct blob GC is an invariants problem, not a loop-over-records problem.

Before a background collector can safely delete anything, the implementation has
to answer:
- whether provider storage is shared or deduplicated across DIDs
- how record updates, deletes, imports, and blob writes interact in flight
- which repository state is authoritative for reference scanning
- how operators will inspect and dry-run the cleanup before anything destructive
  happens

The codebase does not fully answer these questions and does not ship a collector.

## What Operators Can Use Today

The current operational toolbox is smaller but real:
- `com.atproto.sync.listBlobs` for inspection
- `com.atproto.repo.deleteBlob` for intentional cleanup
- `pds_blob_count` and `pds_blob_storage_bytes` metrics for overall capacity
- the admin metrics handler for dashboard-friendly summaries

```bash
curl -s http://localhost:2583/metrics | rg '^pds_blob_(count|storage_bytes)'
```

To reduce blob pressure for a specific DID, use listing and explicit deletion. Commands like `kaszlak gc blobs`, `kaszlak verify blobs`, or `kaszlak repair blobs` are not implemented.

## Why This Simpler Model Is Still Useful

The lack of automated GC clarifies the operational story:
- blob deletion is intentional rather than heuristic
- metrics describe what the server has actually stored
- future GC work can be designed around real invariants instead of retrofitting
  a speculative CLI

This avoids shipping a destructive background operation with unclear ownership semantics.

## Design Notes For Future GC Work

Implementing blob garbage collection requires defining storage semantics first.

The minimum checklist is:
- define whether provider blobs need reference counting across DIDs
- add a trustworthy record-reference scan over persisted repository state
- make dry-run output mandatory before destructive cleanup
- ensure metadata deletion and provider deletion cannot silently diverge
- add observability for reclaimed bytes, skipped blobs, and repair conditions

These pieces must exist before documenting a GC workflow.

## Summary

The current model requires explicit deletion with no automatic sweep. Older references to `PDSCLIGCCommand.m` or `kaszlak gc blobs` are historical design notes.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

