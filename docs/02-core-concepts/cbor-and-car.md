---
title: CBOR and CAR
---

# CBOR and CAR

## Overview

CBOR and CAR are the two data formats that make Garazyk's repository story
portable and verifiable.

- DAG-CBOR gives records, commits, and other structured values deterministic
  bytes
- CAR packages content-addressed blocks into a transport format for sync and
  export

CBOR and CAR preserve data identity in motion.

## Why CBOR Exists In This Repo

Garazyk requires a stable byte representation to hash Objective-C objects.

That is the job of DAG-CBOR in this tree:

- record values are encoded before CID calculation
- special ATProto wrappers such as `{"$link": ...}` and `{"$bytes": ...}` are
  converted into DAG-CBOR forms
- map keys are sorted canonically (byte-length first, then lexicographical byte-order) so the same logical object produces the same bytes.

Serialization details ensure repository correctness.

## Why CAR Exists In This Repo

Once the repository has content-addressed blocks, the server still needs a way
to ship them across process and network boundaries.

CAR is the transport and archive format for that job:

- sync endpoints can return narrow slices of repo state
- export paths can package a root plus reachable blocks
- consumers can verify every block against the CID included in the archive

CAR preserves the content-addressed structure while data is in motion.

## How Garazyk Uses Both Together

The common flow is:

1. encode a structured value as DAG-CBOR
2. hash those bytes into a CID
3. reference that CID from MST or commit structures
4. package the relevant blocks into a CAR response when sync needs them

Repository bugs often cross multiple files. Serialization mismatches cause CID mismatches, missing proof blocks, or broken CAR responses.

## Implementation Boundaries

The main code paths to keep in mind are:

- `ATProtoCBORSerialization` for the JSON-compatible bridge used by handlers
  and services
- `RepoCommit`, `MST`, and `CID` for repository block identity
- `CARReader` and `CARWriter` for parsing and producing portable block archives
- `XrpcSyncMethods` for real sync responses such as `getRecord`

## What To Check When Something Looks Wrong

Start with the narrowest format question:

- did the structured value encode to the bytes you expected?
- did the CID change because the CBOR representation changed?
- is the wrong block missing from the CAR, or is the CAR rooted at the wrong
  CID?
- is a sync consumer missing proof nodes, or is the underlying MST state wrong?

## Related Reading

- [IPLD and Multiformats Series](./ipld-foundations/)
- [CBOR and DAG-CBOR](./ipld-foundations/cbor-and-dag-cbor)
- [CIDs and Multiformats](./ipld-foundations/cids-and-multiformats)
- [CAR Files](./ipld-foundations/car-files)
- [Merkle Search Trees](./mst-trees)
- [Deep Dive: Repository Data Structures](./repository-data-structures-walkthrough)
- [CID and Hashing](../07-repository-protocol/cid-and-hashing)
- [Repository Basics](../07-repository-protocol/repository-basics)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

