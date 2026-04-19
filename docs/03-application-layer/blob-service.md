---
title: Blob Service
---

# Blob Service

## Overview

`PDSBlobService` is the application-layer facade over blob storage. Its job is
not to invent a second storage model. Its job is to translate between protocol
or explorer callers and the storage primitives that `BlobStorage` already owns.

That separation matters because blob callers want ATProto-friendly shapes, while
the storage layer wants CIDs, metadata, and provider operations.

## What The Service Owns

The blob service currently owns five application-facing operations:

- upload a blob for a DID
- retrieve blob bytes for a DID
- retrieve a file-backed blob stream description for a DID
- list blobs for a DID
- delete a blob for a DID

These are the operations handlers should depend on. New route code should not
reach straight into `BlobStorage` unless it is deliberately extending the
storage contract.

## Why The Service Exists

`BlobStorage` is concerned with validation, CID computation, provider access,
and metadata persistence. `PDSBlobService` is concerned with shaping those
results for the rest of the application.

The most visible example is upload. The service returns the ATProto blob object
that record-writing code expects:

- `$type: "blob"`
- `ref.$link`
- `mimeType`
- `size`

That is exactly the kind of translation that belongs in the application layer.

## Read Paths

The service supports two read styles:

- buffered reads for callers that need the blob data immediately
- file-backed reads for handlers that can serve a provider path directly

This design is small but useful. Higher layers do not have to understand the
provider implementation, and lower layers do not have to know anything about
HTTP response construction.

## Where Callers Enter

Blob-related handlers and compatibility surfaces currently reach the service
through:

- XRPC repo and sync methods
- the generated method registry
- the legacy `PDSController` facade

The compatibility point matters because older code still routes through
`PDSController`, but new code should prefer the service directly.

## What The Service Does Not Do

`PDSBlobService` does not currently implement:

- quota accounting
- automatic garbage collection
- background verification or repair jobs
- record-reference tracking beyond the storage and protocol flows that already
  exist

That is why blob lifecycle docs must stay explicit. The service is honest about
what it does, and the docs should be too.

## Implementation Map

Start here when you change blob application behavior:

- `Garazyk/Sources/App/Services/PDSBlobService.h`
- `Garazyk/Sources/App/Services/PDSBlobService.m`
- `Garazyk/Sources/Blob/BlobStorage.m`
- `Garazyk/Sources/Network/XrpcRepoMethods.m`
- `Garazyk/Sources/Network/XrpcSyncMethods.m`

## Related Reading

- [Blob Storage](../07-repository-protocol/blob-storage)
- [Blob Lifecycle](../07-repository-protocol/blob-lifecycle)
- [Blob Optimization](../07-repository-protocol/blob-optimization)
- [Services Overview](./services-overview)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n