---
title: Blob Storage
---

# Blob Storage

## Overview

Blob storage in Garazyk is intentionally smaller than the surrounding
repository protocol. The server needs a reliable way to accept binary data,
address it by CID, and hand it back to sync and explorer surfaces. It does not
yet try to solve every long-term lifecycle problem such as quotas, garbage
collection, or tiered object storage.

The important contributor question is not "where are the bytes?" It is "which
layer owns correctness for those bytes?"

## Why The Storage Layer Is Split

The blob path is divided into three concerns:

- `BlobStorage` owns validation, CID computation, metadata lookups, and delete
  coordination.
- The blob provider owns the raw bytes on disk or in another backing store.
- Actor databases own the metadata that lets the rest of the application find a
  blob for a DID.

That split keeps the protocol layer simple. XRPC handlers do not need to know
how bytes are laid out on disk, and storage backends do not need to understand
ATProto response shapes.

## Content Addressing

Garazyk stores blobs by CID rather than by user-chosen filename. The storage
layer computes a CIDv1 using the raw codec and SHA-256. That gives the server a
stable identity for the content before it writes metadata or returns a blob
reference to the client.

This matters for two reasons:

- the returned blob reference is derived from the bytes, not from request
  metadata
- the read path can recompute the CID later and reject corrupted provider data

## Write Path

The current write path is conservative:

1. validate the upload against MIME and size rules
2. compute the CID from the payload
3. ask the provider whether the bytes already exist for that CID
4. store bytes when needed
5. persist blob metadata for the DID

This ordering is deliberate. The server does not want provider bytes that never
become visible to the application, and it does not want to trust transport
metadata without revalidating it at the storage boundary.

For the request-layer guardrails that happen before `BlobStorage` runs, see
[Blob Lifecycle](./blob-lifecycle) and [Blob Quotas](./blob-quotas).

## Read Path

Blob reads happen in two forms:

- a full in-memory read when a handler needs blob bytes directly
- a file-backed path when the provider can expose a real file location

`BlobStorage` verifies that the provider still has the bytes for the requested
CID, retrieves them or their file path, and re-checks the content hash on the
buffered read path. `PDSBlobService` then turns that result into the response
shape the sync or explorer layer expects.

The file-path path is important because it lets higher layers stream or serve
blob content without always copying the entire payload through another JSON or
service abstraction.

## Listing And Deletion

The shipped lifecycle controls are explicit:

- list blobs for a DID
- fetch metadata for a CID
- delete a blob for a DID

That means operators and contributors should think in terms of visible,
requested actions rather than background cleanup. If a blob is removed today,
it is because an implemented code path asked for that removal.

## What This Layer Does Not Promise

The current blob storage design does not promise:

- automatic garbage collection
- a byte-accurate per-account quota ledger
- background compaction or tier migration
- user-facing quota status or repair commands

Those features all require stronger accounting rules than the current storage
layer exposes. The docs should not describe them as if they already exist.

## Implementation Map

Start here when you change storage behavior:

- `Garazyk/Sources/Blob/BlobStorage.h`
- `Garazyk/Sources/Blob/BlobStorage.m`
- `Garazyk/Sources/Blob/PDSBlobProvider.h`
- `Garazyk/Sources/Blob/PDSDiskBlobProvider.m`
- `Garazyk/Sources/App/Services/PDSBlobService.m`

Read the service layer together with the provider interface. Most storage bugs
are really coordination bugs between those two layers.

## Related Deep Dives

- [Blob Flow Walkthrough](./blob-flow-walkthrough)
- [Record Write to Commit Walkthrough](./record-write-to-commit-walkthrough)

## Related Reading

- [Blob Lifecycle](./blob-lifecycle)
- [Blob Optimization](./blob-optimization)
- [Blob Quotas](./blob-quotas)
- [Blob Service](../03-application-layer/blob-service)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n