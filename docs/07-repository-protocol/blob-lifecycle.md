---
title: Blob Lifecycle
---

# Blob Lifecycle

## Overview

The blob lifecycle in Garazyk is explicit and short:

1. upload bytes
2. receive a blob reference
3. attach that reference to a record when needed
4. read or list blobs through implemented sync and explorer flows
5. delete a blob explicitly if it should no longer be retained

This is the actual lifecycle. No hidden background collector finishes the job later.

## Why The Lifecycle Starts With Upload

ATProto records refer to blobs by CID-based references. The server must stabilize the binary object before a record points at it. The upload endpoint turns raw bytes into a validated, addressable blob.

In Garazyk, `com.atproto.repo.uploadBlob` is the main entry point for this
step. The request path applies basic payload guardrails, then `PDSBlobService`
and `BlobStorage` compute the CID and store the metadata needed for later
lookup.

## Upload To Reference

The service layer returns a blob object rather than a private storage record.
The next consumer is usually record-writing code.

In practice the workflow is:

- upload bytes with `com.atproto.repo.uploadBlob`
- receive a blob description containing the CID link, MIME type, and size
- include that blob object in the record payload you later create or update

This keeps the storage contract aligned with the ATProto record contract.

## Read Paths

The current tree exposes two main read surfaces:

- `com.atproto.sync.getBlob` for retrieving blob contents
- `com.atproto.sync.listBlobs` for enumerating a DID's blobs

`PDSBlobService` also exposes a file-backed streaming helper when the provider
can return a real file path. Higher layers use that to avoid unnecessary copies
for larger responses.

Sync reads are service-backed; handlers do not reach straight into the provider.

## Delete Path

Deletion is implemented as an explicit API action, not as a derived side effect
from record updates. `com.atproto.repo.deleteBlob` is the explicit delete path.

This explicit design clarifies behavior:

- a delete either succeeds or fails as a requested operation
- there is no separate repair process required to "finish" the lifecycle
- operators can audit the result through the existing blob list and metrics
  surfaces

## What Does Not Happen Automatically

The current blob lifecycle does not include:

- automatic reclamation of unreferenced blobs
- quota enforcement based on retained bytes
- scheduled blob repair or verification jobs
- a dedicated blob maintenance CLI

These are not part of the current lifecycle.

## Failure Modes To Keep In Mind

When blob behavior looks wrong, the failure is usually in one of four places:

- request-layer limits reject the upload before storage runs
- MIME validation rejects the payload at the storage layer
- the provider cannot persist or retrieve bytes for a CID
- the caller is assuming automatic cleanup that the current code does not do

Using this model is faster than searching for a nonexistent background maintenance system.

## Related Deep Dives

- [Blob Flow Walkthrough](./blob-flow-walkthrough)
- [Record Write to Commit Walkthrough](./record-write-to-commit-walkthrough)

## Related Reading

- [Blob Storage](./blob-storage)
- [Blob Optimization](./blob-optimization)
- [Blob Quotas](./blob-quotas)
- [Blob Service](../03-application-layer/blob-service)

## Appendix

### Minimal lifecycle smoke check

```bash
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: image/png" \
  --data-binary @avatar.png \
  http://127.0.0.1:2583/xrpc/com.atproto.repo.uploadBlob | jq .
```

```bash
curl -sS \
  "http://127.0.0.1:2583/xrpc/com.atproto.sync.listBlobs?did=$DID" | jq .
```

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)

