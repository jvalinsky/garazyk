# CBOR and CAR

Garazyk uses DAG-CBOR and CAR to ensure repository data is portable and verifiable.

## DAG-CBOR
Garazyk requires a stable byte representation to hash Objective-C objects. DAG-CBOR provides:
- **Deterministic Encoding**: Record values are encoded before CID calculation.
- **Type Conversion**: ATProto-specific wrappers (`$link`, `$bytes`) are converted to DAG-CBOR forms.
- **Canonical Sorting**: Map keys are sorted by byte length, then lexicographical order, ensuring consistent byte output for identical objects.

## CAR (Content Addressable Archive)
CAR is the transport and archive format for content-addressed blocks:
- **Transport**: Sync endpoints return slices of repository state as CAR files.
- **Archiving**: Export paths package a root plus all reachable blocks.
- **Verification**: Consumers verify blocks against the CIDs included in the archive.

## Data Flow
1. Encode a structured value as DAG-CBOR.
2. Hash the bytes to generate a CID.
3. Reference the CID from MST or commit structures.
4. Package the blocks into a CAR response for synchronization.

## Implementation Boundaries
- `ATProtoCBORSerialization`: JSON-compatible bridge for handlers and services.
- `RepoCommit`, `MST`, and `CID`: Repository block identity.
- `CARReader` and `CARWriter`: Portable block archive parsing and production.
- `XrpcSyncPack`: Sync responses (e.g., `getRecord`).

## Debugging Points
- **Encoding**: Does the structured value encode to the expected bytes?
- **Identity**: Did the CID change due to a CBOR representation shift?
- **Transport**: Is the CAR rooted at the correct CID, or is a specific block missing?
- **Integrity**: Is a consumer missing proof nodes from the underlying MST?

## Related

- [IPLD Foundations](./ipld-foundations/)
- [Merkle Search Trees](./mst-trees)
- [Repository Data Structures](./repository-data-structures-walkthrough)
- [CID and Hashing](../07-repository-protocol/cid-and-hashing)
- [Repository Basics](../07-repository-protocol/repository-basics)
- [Documentation Map](../11-reference/documentation-map.md)

