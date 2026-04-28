---
title: Record Write to Commit Walkthrough
---

# Record Write to Commit Walkthrough

## Goal

This page details the repository mutation path for a normal write: endpoint input, record validation, CBOR and CID generation, actor-store persistence, signed commit creation, and the resulting sync side effects.

## Full Flow

```mermaid
flowchart TD
    Request["createRecord or applyWrites request"]
    Validate["Record validation and write normalization"]
    Encode["CBOR encode record and compute CID"]
    ActorTx["Actor store transaction"]
    RepoRoot["Update repo root and revision"]
    Commit["Create and sign RepoCommit block"]
    Result["Return commit metadata"]
    Sync["Persist event and feed firehose consumers"]

    Request --> Validate
    Validate --> Encode
    Encode --> ActorTx
    ActorTx --> RepoRoot
    RepoRoot --> Commit
    Commit --> Result
    Commit --> Sync
```

## Why This Flow Is Easy To Misread

Record writes do not go through a single repository entry point:

- `PDSRecordService` owns most endpoint-facing record mutation work,
- the actor store owns the low-level transaction boundary,
- commit objects are created and signed after the record mutation is staged,
- sync and firehose surfaces depend on that stored commit block existing later.

A record write bug can appear correct at the endpoint level but fail during commit persistence or event publication.

## Walkthrough: A Normal Record Write

The primary implementation path is the `putRecord` and `applyWrites` logic in `Garazyk/Sources/App/Services/PDSRecordService.m`.

1. The handler normalizes the write request and checks required fields such as repo, collection, and record value.
2. The service validates the record shape and writes policy before persistence.
3. The record is encoded to CBOR and assigned a CID.
4. The actor store transaction creates or replaces the record row and updates repository metadata.
5. The service refreshes repository root metadata so it can compute the new commit context.
6. A `RepoCommit` is created, signed through the actor store key path, and serialized as a signed block.
7. The commit block is stored and the repo root revision is updated.
8. The response returns URI, CID, and commit metadata.

Missing any stage causes the repo to look correct in reads but fail during export or firehose delivery.

## Where Firehose Side Effects Enter

The write path and the firehose path are coupled by stored commit material, not by an in-memory callback chain.

`Garazyk/Sources/Sync/SubscribeReposHandler.m` later loads the signed commit block, builds CAR bytes, persists the event sequence, and broadcasts the result to WebSocket consumers. If the record write succeeds but the firehose looks wrong, the issue is likely in commit storage or event persistence, not the request handler.

## Where To Debug When This Breaks

- Start in `Garazyk/Sources/App/Services/PDSRecordService.m` for input normalization, write validation, and commit metadata generation.
- Start in `Garazyk/Sources/Database/ActorStore/ActorStore.m` for transaction ordering, block persistence, and repo-root updates.
- Start in `Garazyk/Sources/App/Services/PDSRepositoryService.m` when the failure shows up in export, import, or repository-level read behavior.
- Start in `Garazyk/Sources/Sync/SubscribeReposHandler.m` when commit state looks correct locally but the sync surface is wrong.

## Tests That Should Fail If This Changes

- `Garazyk/Tests/App/Services/PDSRecordServiceTests.m`
- `Garazyk/Tests/App/Services/PDSRepositoryServiceTests.m`
- `Garazyk/Tests/Integration/CommitChainTests.m`
- `Garazyk/Tests/Sync/SubscribeReposHandlerTests.m`

## Appendix

### Artifacts worth inspecting

- record URI
- record CID
- commit CID
- repo revision
- stored commit block in the actor database

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

