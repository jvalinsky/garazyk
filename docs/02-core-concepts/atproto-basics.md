# ATProto Basics

Garazyk implements AT Protocol primitives with a focus on:
- **Identity**: DID-anchored accounts with handle aliases.
- **Repositories**: Content-addressed user data stores.
- **Records**: Namespaced entries within repositories (e.g., `app.bsky.feed.post`).
- **Blobs**: Binary objects referenced by CID, stored outside the repository.
- **XRPC**: The protocol's primary method-dispatch interface.

## Identity
Accounts are identified by DIDs. Handles are human-friendly aliases that resolve to these DIDs. Garazyk supports:
- `did:plc`
- `did:web`

## Repositories and Records
Each account owns a single repository. Records are grouped by collection NSIDs. Implementation in this repository covers:
- Record CRUD operations.
- Repository state materialization via MST and CAR machinery.
- Sync and firehose event streams.

## Blobs
Binary objects are stored separately from records and referenced by CID. This separation decouples binary storage from repository integrity and lifecycle management.

## XRPC Interface
ATProto methods are grouped into namespaces:
- `com.atproto.server.*`
- `com.atproto.repo.*`
- `com.atproto.sync.*`
- `com.atproto.identity.*`

To trace a request:
1. Identify the XRPC method.
2. Review the authentication and validation path.
3. Follow the method to its owning service.
4. Inspect the underlying repository, database, or identity logic.

## Sync and Relays
Garazyk handles synchronization and relay notifications through:
- Repository export and block retrieval.
- `subscribeRepos` event delivery.
- Relay crawl notifications.

## Implementation Mapping
Garazyk maps protocol concepts to specific architectural layers:
- **Auth**: Token and DPoP verification.
- **Services**: Application behavior and coordination.
- **Repository/Blob**: Persistence and content addressing.
- **Identity/PLC**: DID resolution and updates.

## Related

- [Codebase Map](../01-getting-started/codebase-map)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [IPLD Foundations](./ipld-foundations/)
- [Protocol Flow Walkthrough](./protocol-flow-walkthrough)
- [PLC Directory](./plc-directory)
- [Cryptography](./cryptography)
- [Documentation Map](../11-reference/documentation-map.md)

