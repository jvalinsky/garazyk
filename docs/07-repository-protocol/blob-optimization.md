---
title: Blob Optimization
---

# Blob Optimization

## Overview

The old version mixed actual optimizations with unshipped design ideas.

This section details the blob optimizations currently in the code and why they were chosen.

## Optimization In The Current Tree

Garazyk currently optimizes blob handling in four practical ways:

- reject obviously bad requests early
- avoid rewriting provider data when the same CID already exists
- serve blobs from file-backed paths when possible
- expose blob pressure through metrics instead of guessing

These optimizations reduce waste without adding complex consistency rules.

## Early Rejection Is A Performance Feature

Blob performance starts before storage. The upload path rejects oversized or
otherwise invalid requests before the server spends time computing CIDs or
writing provider bytes.

Early rejection protects CPU, memory, disk, and request concurrency. It serves as both a correctness rule and a capacity optimization.

## Content Addressing Avoids Redundant Writes

Because blobs are addressed by CID, the provider can skip writing bytes it
already has for that CID. That is the most important storage-side optimization
in the current implementation.

Content addressing allows the storage layer to avoid redundant work.

## File-Backed Reads Reduce Copying

`PDSBlobService` has a streaming-oriented path that asks `BlobStorage` for a
provider-backed file location. When that path is available, higher layers can
serve the blob without first forcing the entire payload through another in
memory buffer.

This optimization does not complicate the protocol contract. The XRPC surface still sees "return this blob", but the
service layer is free to choose a cheaper transport.

## Rate Limiting Is Also An Optimization

Blob upload rate limiting serves as both abuse protection and a performance optimization. It bounds how quickly one DID can force the server to hash, validate, and persist data.

Capacity work and abuse work overlap at this layer.

## Metrics Beat Guesswork

The current server exports the aggregate signals operators actually need:

- blob count
- blob storage bytes
- request rates and latency
- rate-limit rejection counts

Monitoring these metrics is more effective than inventing speculative cleanup jobs. Without sustained blob pressure, a complex subsystem is premature.

## What Is Not Implemented

This repository does not currently implement:

- automatic blob compaction
- background blob transcoding
- scheduled garbage collection
- a quota-aware optimizer
- a blob repair CLI

To add these features, define the invariants first. A poorly designed optimization can silently alter blob retention semantics.

## When To Extend This Area

A new blob optimization is worth adding when all three of these are true:

- metrics show real pressure on the current path
- the new behavior has a clear ownership boundary
- the docs can explain the retention and visibility rules without guessing

This high bar prevents optimizations from hiding lifecycle behavior.

## Related Reading

- [Blob Storage](./blob-storage)
- [Blob Lifecycle](./blob-lifecycle)
- [Blob Quotas](./blob-quotas)
- [Performance Monitoring](../11-reference/performance-monitoring)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

