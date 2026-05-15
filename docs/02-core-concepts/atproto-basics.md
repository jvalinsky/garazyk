# ATProto Basics

Garazyk implements [AT Protocol](../GLOSSARY.md#at-protocol) primitives:
- **Identity**: [DID](../GLOSSARY.md#did)-anchored accounts with [handle](../GLOSSARY.md#handle) aliases.
- **Repositories**: Content-addressed user data stores.
- **Records**: Namespaced entries within [repositories](../GLOSSARY.md#repository) (e.g., `app.bsky.feed.post`).
- **Blobs**: Binary objects referenced by [CID](../GLOSSARY.md#cid), stored outside the repository.
- **XRPC**: The protocol's primary method-dispatch interface.

## Identity
Accounts are identified by DIDs. Handles are human-friendly aliases that resolve to these DIDs. Garazyk supports:
- `did:plc`: Resolution through the [PLC Directory](./plc-directory).
- `did:web`: Resolution through standard web paths.

## Repositories and Records
Each account owns one repository. Records are grouped by collection [NSIDs](../GLOSSARY.md#nsid). Garazyk manages:
- Record CRUD operations.
- Repository state materialization using [MST](./mst-trees) and [CAR](./cbor-and-car) machinery.
- Sync and firehose event streams.

## Blobs
Binary objects are stored separately from records and referenced by CID. This separation decouples binary storage from repository integrity and lifecycle management. See the [Blob Service](../03-application-layer/blob-service) for implementation details.

## XRPC Interface
ATProto methods are grouped into namespaces:
- `com.atproto.server.*`
- `com.atproto.repo.*`
- `com.atproto.sync.*`
- `com.atproto.identity.*`

Requests follow a standard flow: identify the [XRPC](../GLOSSARY.md#xrpc) method, validate authentication, and route to the owning service.

## Sync and Relays
Garazyk handles synchronization and relay notifications:
- Repository export and block retrieval.
- `subscribeRepos` event delivery via the [firehose](../GLOSSARY.md#firehose).
- Relay crawl notifications.

## Implementation Mapping
Protocol concepts map to these architectural layers:
- **Auth**: Token and [DPoP](../GLOSSARY.md#dpop) verification.
- **Services**: Application behavior and coordination. See [Services Overview](../03-application-layer/services-overview).
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

