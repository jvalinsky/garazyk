---
title: Merkle Search Trees
---

# Merkle Search Trees

## Overview

The Merkle Search Tree, or MST, is the repository index that lets Garazyk be
both ordered and verifiable at the same time.

It solves three problems together:

- record lookup by repository key
- deterministic repository roots
- proof-friendly block structure for sync responses

Without the MST layer, the PDS could still store records, but it would lose the
portable cryptographic shape that ATProto expects.

## What The Tree Actually Stores

At a practical level, the tree maps repository paths such as
`app.bsky.feed.post/<rkey>` to record CIDs.

That gives the repo a stable answer to two different questions:

- where is the current record for this path?
- what root CID proves the current state of the whole repository?

This is why contributors should think of the MST as both an index and a proof
structure.

## Why The Tree Matters To Sync

The sync surfaces do not just need record bytes. They need enough structure for
other implementations to verify that a record belongs to a particular repo
state.

That is where the MST earns its keep:

- root CIDs summarize repository state
- proof nodes let sync responses justify a record's position in the tree
- diffs can be expressed as changes between CID-addressed nodes

The firehose, export, and `getRecord` paths all depend on this idea, even when
they are not explicitly named "MST" in the calling code.

## How Garazyk Implements The Shape

The current `MST` implementation in this repo is built around:

- hashed key depth to place entries in tree levels
- deterministic node serialization to DAG-CBOR
- CID computation from serialized node bytes
- proof path collection for targeted sync responses

That means MST behavior is tightly coupled to both hashing and serialization.
You usually cannot fix one of those layers in isolation.

## Common Contributor Confusions

Two misunderstandings cause a lot of wasted time:

- the MST is not just an in-memory convenience index
- the repository root is not just "the latest commit CID"

The commit points at repository state, but the underlying tree is what defines
the ordered content being committed.

## Where To Look In The Code

The main implementation seams are:

- `MST` and `MSTNode` for insertion, lookup, diffing, and proof paths
- `CID` and DAG-CBOR serialization for node identity
- sync code that packages MST proof nodes into CAR responses

If a bug touches repo correctness, there is a good chance it crosses all three.

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

