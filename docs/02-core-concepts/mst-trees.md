---
title: Merkle Search Trees
---

# Merkle Search Trees

## Overview

Merkle Search Trees (MST) provide an ordered, verifiable index for repositories. They solve three problems:

- record lookup by repository key
- deterministic repository roots
- proof-friendly block structure for sync responses

Without the MST layer, the PDS could store records but would lose the portable cryptographic shape ATProto requires.

## Tree Contents

The tree maps repository paths like `app.bsky.feed.post/<rkey>` to record CIDs. This gives the repository:

- the current record for a path.
- a root CID that proves the current state of the whole repository.

The MST serves as both an index and a proof structure.

## Sync Integration

Sync surfaces require more than just record bytes; they need enough structure to verify that a record belongs to a specific repository state. The MST enables:

- root CIDs that summarize repository state.
- proof nodes that justify a record's position in the tree.
- diffs expressed as changes between CID-addressed nodes.

Firehose, export, and `getRecord` paths all depend on these concepts.

## Implementation

The `MST` implementation uses:

- hashed key depth to place entries in tree levels.
- deterministic node serialization to DAG-CBOR.
- CID computation from serialized node bytes.
- proof path collection for sync responses.

MST behavior is coupled to both hashing and serialization.

## Common Misunderstandings

Two points often cause confusion:

- The MST is a persistent proof structure, not just an in-memory index.
- The repository root differs from the latest commit CID.

The commit points to the repository state, but the underlying tree defines the content.

## Implementation Seams

- `MST` and `MSTNode`: insertion, lookup, diffing, and proof paths.
- `CID` and DAG-CBOR serialization: node identity.
- Sync code: packaging MST proof nodes into CAR responses.

Repository correctness bugs often involve all three areas.

## Related Reading

- [IPLD and Multiformats Series](./ipld-foundations/)
- [IPLD Data Model and Merkle DAGs](./ipld-foundations/ipld-data-model-and-merkle-dags)
- [CBOR and CAR](./cbor-and-car)
- [Deep Dive: Repository Data Structures](./repository-data-structures-walkthrough)
- [Repository Service](../03-application-layer/repository-service)
- [Repository Basics](../07-repository-protocol/repository-basics)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

