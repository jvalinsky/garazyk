---
title: Merkle Search Trees
---

# Merkle Search Trees

[Merkle Search Trees (MST)](../GLOSSARY.md#mst) provide an ordered, verifiable index for repositories. They enable record lookup by repository key, deterministic repository roots, and proof-friendly block structures for synchronization. Without the MST layer, a [PDS](../GLOSSARY.md#pds) could store records but would lack the portable cryptographic shape required by the [AT Protocol](../GLOSSARY.md#at-protocol).

## Tree Contents

The tree maps repository paths (e.g., `app.bsky.feed.post/<rkey>`) to record [CIDs](../GLOSSARY.md#cid). This mapping provides:
- The current record for any given path.
- A root CID that proves the state of the entire repository.

The MST serves as both a primary index and a cryptographic proof structure.

## Synchronization and Proofs

Sync interfaces require more than raw record bytes; they need enough structure to verify that a record belongs to a specific repository state. The MST facilitates:
- Root CIDs that summarize repository state.
- Proof nodes that justify a record's position in the tree.
- Diffs expressed as changes between CID-addressed nodes.

The [firehose](../GLOSSARY.md#firehose), repository export, and `getRecord` paths all rely on these primitives.

## Implementation Details

The `MST` implementation handles:
- Hashed key depth to place entries in tree levels.
- Deterministic node serialization to [DAG-CBOR](../GLOSSARY.md#dag-cbor).
- CID computation from serialized node bytes.
- Proof path collection for sync responses.

MST behavior is tightly coupled to both hashing and serialization logic.

## Key Concepts

The MST is a persistent proof structure, not just an in-memory index. While a [commit](../GLOSSARY.md#commit) points to the repository state, the underlying tree defines the actual content.

Implementation involves:
- `MST` and `MSTNode`: Insertion, lookup, diffing, and proof paths.
- `CID` and DAG-CBOR serialization: Node identity.
- Sync code: Packaging MST proof nodes into [CAR](../GLOSSARY.md#car) responses.

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

