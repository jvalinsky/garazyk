---
title: Repository Service
---

# Repository Service

`PDSRepositoryService` manages repository exports, inspections, and initialization. It is the application-layer authority for the Merkle Search Tree (MST) and Content-Addressable Archive (CAR) operations.

## Current Capabilities

The service provides the following repository operations:

- **MST Reconstruction**: Rebuilds an MST from stored records for a specific DID.
- **Root Inspection**: Reads the current repository root and latest commit metadata.
- **Data Export**: Exports repository contents as CAR data (streaming or file-backed).
- **Block Management**: Fetches specific blocks by CID.
- **Lifecycle**: Initializes new repositories and provides a force-reinitialize path for recovery.

## MST Materialization

When loading repository state, the service rebuilds the MST from stored records rather than relying on a persistent, opaque tree structure. This approach prioritizes data integrity and recoverability:

- Record storage remains the primary source of truth.
- Export code can re-materialize blocks deterministically.
- Repository repair is an explicit, observable process.

Contributors should understand the relationship between record storage and MST materialization when working with this service.

## Export Architecture

The most mature component of this service is the export pipeline. It can produce full CAR payloads and provides a chunk producer for streaming exports.

When debugging repository issues, verify the exported CAR state before investigating the transport layers (e.g., sync handlers).

## Repository Initialization and Repair

New repositories start with an explicit, signed empty commit. The service also provides a force-reinitialize path that clears stored root state and writes a fresh initial commit. This is the primary mechanism for recovering from corrupted repository state.

## Implementation Map

- `Garazyk/Sources/Services/PDS/PDSRepositoryService.h`
- `Garazyk/Sources/Services/PDS/PDSRepositoryService.m`
- `Garazyk/Sources/Repository/MST.m`
- `Garazyk/Sources/Repository/CAR.m`
- `Garazyk/Sources/Network/XrpcRepoMethods.m`
- `Garazyk/Sources/Network/XrpcSyncMethods.m`

## Related

- [Services Overview](./services-overview)
- [Relay Service](./relay-service)
- [Blob Service](./blob-service)
- [Record Service](./record-service)
- [ATProto Basics](../02-core-concepts/atproto-basics)
- [MST Trees](../02-core-concepts/mst-trees)
- [CAR Files](../02-core-concepts/car-files)
- [Documentation Map](../11-reference/documentation-map.md)

