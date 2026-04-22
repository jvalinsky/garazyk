---
title: Repository Service
---

# Repository Service

## Overview

`PDSRepositoryService` is the application-layer owner of repository export,
inspection, and initialization work. It is also the easiest place for docs to
drift, because the service implements some important repository paths fully and
leaves others explicitly unfinished.

The most important contributor fact is this: repository export is implemented;
generic commit import is not.

## What The Service Does Today

The service currently provides the repository operations contributors use most:

- rebuild an MST from stored records for a DID
- read the current repo root and latest commit metadata
- export repository contents as CAR data
- write repository contents directly to a path
- expose a chunk producer for streaming repository export
- fetch specific blocks
- initialize an empty repository for a new account
- force reinitialize a damaged repository

These are real, implemented behaviors and they are the correct basis for docs.

## Why The Service Rebuilds From Records

When the service loads repository state, it rebuilds an MST from stored records
instead of treating one opaque in-memory tree as the only source of truth.

That choice prioritizes correctness and recoverability:

- record storage remains inspectable
- export code can re-materialize blocks as needed
- repository initialization and repair stay explicit

The tradeoff is that contributors need to understand both record storage and MST
materialization, not just one cached tree structure.

## Export Is The Strong Path

The most mature path in this service is export. The service can produce full CAR
payloads, write them to disk, or hand back a chunk producer for streaming.

That is why sync and repository inspection work should start here. If a repo
surface looks wrong, first ask whether the export state is wrong before
debugging the transport layer.

## Initialization And Repair

New repositories are initialized with an explicit empty signed commit. The
service also exposes a force-reinitialize path that clears stored repo-root
state and writes a fresh initial commit.

This matters for operations because repair is implemented as a clear, visible
workflow. It is not a hidden self-healing background task.

## The Important Gap: Commit Import

`updateRepo:commit:error:` currently returns `NO`.

That means the generic "apply this commit blob and update the repository"
workflow is not implemented in the way older docs implied. Contributors working
on sync or import behavior need to know this before they spend time debugging a
path the service does not actually support.

This is not a minor detail. It changes which repository stories are real today.

## What To Verify First

If repository behavior looks wrong, inspect in this order:

1. stored records for the DID
2. MST reconstruction for that DID
3. exported commit and CAR contents
4. the handler or sync surface presenting that data

That order is faster than starting at the HTTP edge because repository bugs are
usually lower in the stack.

## Implementation Map

Start here when you change repository, MST, or CAR behavior:

- `Garazyk/Sources/Services/PDS/PDSRepositoryService.h`
- `Garazyk/Sources/Services/PDS/PDSRepositoryService.m`
- `Garazyk/Sources/Repository/MST.m`
- `Garazyk/Sources/Repository/CAR.m`
- `Garazyk/Sources/Network/XrpcRepoMethods.m`
- `Garazyk/Sources/Network/XrpcSyncMethods.m`

## Related Reading

- [Services Overview](./services-overview)
- [Relay Service](./relay-service)
- [Blob Service](./blob-service)
- [ATProto Basics](../02-core-concepts/atproto-basics)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n