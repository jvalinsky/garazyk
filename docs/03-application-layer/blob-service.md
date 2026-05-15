---
title: Blob Service
---

# Blob Service

`PDSBlobService` is the application-layer facade for blob storage. It translates between protocol callers and the storage primitives managed by `BlobStorage`.

This separation ensures that high-level callers receive AT Protocol-compliant responses while the storage layer focuses on CIDs, metadata, and provider operations.

## Core Operations

The service manages several application-facing operations:

- **Upload**: Accepts a raw data stream and returns an AT Protocol blob object.
- **Retrieve**: Fetches blob bytes or a file-backed stream description.
- **List**: Enumerates blobs associated with a specific DID.
- **Delete**: Removes a blob and its associated metadata.

Handlers should depend on these operations rather than accessing `BlobStorage` directly.

## Protocol Translation

While `BlobStorage` handles validation, CID computation, and persistence, `PDSBlobService` shapes results for the AT Protocol. For example, an upload returns the expected JSON structure:

- `$type: "blob"`
- `ref.$link`: The CID of the blob.
- `mimeType`: The media type.
- `size`: The size in bytes.

## Read Paths

The service supports two read styles to accommodate different handler needs:

- **Buffered Reads**: For callers that need the complete blob data immediately.
- **File-backed Reads**: Allows handlers to serve a provider path directly, optimizing for large files.

## Access Points

Callers typically reach the service through:

- **XRPC Methods**: Handlers in `com.atproto.repo.*` and `com.atproto.sync.*`.
- **Method Registry**: The centralized [XrpcMethodRegistry](../04-network-layer/method-registry).
- **Controller Facade**: The legacy `PDSController` (new code should prefer the service directly).

## Scope and Limitations

`PDSBlobService` focuses on data transport and translation. It does not currently implement:

- Quota accounting (managed at the handler or dedicated quota layer).
- Automatic garbage collection.
- Background verification or repair jobs.
- Record-reference tracking beyond the immediate storage flow.

## Implementation Reference

- `Garazyk/Sources/Services/PDS/PDSBlobService.h`
- `Garazyk/Sources/Services/PDS/PDSBlobService.m`
- `Garazyk/Sources/Blob/BlobStorage.m`
- `Garazyk/Sources/Network/XrpcRepoMethods.m`
- `Garazyk/Sources/Network/XrpcSyncMethods.m`

## Related

- [Blob Storage](../07-repository-protocol/blob-storage)
- [Blob Lifecycle](../07-repository-protocol/blob-lifecycle)
- [Services Overview](./services-overview)
- [Account Service](./account-service)
- [Record Service](./record-service)
- [Documentation Map](../11-reference/documentation-map.md)

