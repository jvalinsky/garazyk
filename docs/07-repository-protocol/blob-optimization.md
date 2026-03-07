---
title: Blob Optimization
---

# Blob Optimization

## Overview

The old version of this page mixed real optimizations with design ideas that
had not shipped. For contributors, that is worse than having no page at all.

This rewrite keeps a narrower question in view: which blob optimizations are
already present in the code, and why were they chosen?

## Optimization In The Current Tree

September currently optimizes blob handling in four practical ways:

- reject obviously bad requests early
- avoid rewriting provider data when the same CID already exists
- serve blobs from file-backed paths when possible
- expose blob pressure through metrics instead of guessing

None of those are glamorous, but they are the right first optimizations because
they reduce waste without inventing new consistency rules.

## Early Rejection Is A Performance Feature

Blob performance starts before storage. The upload path rejects oversized or
otherwise invalid requests before the server spends time computing CIDs or
writing provider bytes.

That matters more than it sounds. An early rejection protects CPU, memory,
disk, and request concurrency at the same time. It is both a correctness rule
and a capacity optimization.

## Content Addressing Avoids Redundant Writes

Because blobs are addressed by CID, the provider can skip writing bytes it
already has for that CID. That is the most important storage-side optimization
in the current implementation.

The point is not global deduplication policy. The point is that content
addressing lets the storage layer avoid doing obviously redundant work.

## File-Backed Reads Reduce Copying

`PDSBlobService` has a streaming-oriented path that asks `BlobStorage` for a
provider-backed file location. When that path is available, higher layers can
serve the blob without first forcing the entire payload through another in
memory buffer.

This is the clearest example of a useful optimization that does not complicate
the protocol contract. The XRPC surface still sees "return this blob", but the
service layer is free to choose a cheaper transport.

## Rate Limiting Is Also An Optimization

Blob upload rate limiting is usually described as abuse protection, but it is
also a performance optimization. It bounds how quickly one DID can force the
server to hash, validate, and persist blob data.

That is why blob protection docs and performance docs overlap here. Capacity
work and abuse work are not separate concerns at this layer.

## Metrics Beat Guesswork

The current server exports the aggregate signals operators actually need:

- blob count
- blob storage bytes
- request rates and latency
- rate-limit rejection counts

That is a better optimization strategy than inventing speculative cleanup jobs.
If the metrics do not show sustained blob pressure, adding a more complex blob
subsystem is usually premature.

## What Is Not Implemented

This repository does not currently implement:

- automatic blob compaction
- background blob transcoding
- scheduled garbage collection
- a quota-aware optimizer
- a blob repair CLI

If you need one of those, start by defining the invariants first. The danger is
not that the optimization is hard. The danger is that an optimization silently
changes blob retention semantics.

## When To Extend This Area

A new blob optimization is worth adding when all three of these are true:

- metrics show real pressure on the current path
- the new behavior has a clear ownership boundary
- the docs can explain the retention and visibility rules without guessing

That bar is deliberate. Blob systems become unreliable when "optimization" is
used as a reason to hide lifecycle behavior.

## Related Reading

- [Blob Storage](./blob-storage)
- [Blob Lifecycle](./blob-lifecycle)
- [Blob Quotas](./blob-quotas)
- [Performance Monitoring](../11-reference/performance-monitoring)
