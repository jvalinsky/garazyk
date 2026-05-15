# Method Registry

`XrpcMethodRegistry` defines the public XRPC interface and manages service dependency injection for domain-specific handlers.

## Core Responsibilities

The registry coordinates the wiring of the protocol layer:
- **NSID Mapping**: Associates NSIDs (e.g., `com.atproto.repo.createRecord`) with their implementation handlers.
- **Domain Delegation**: Distributes method registration to domain modules (Server, Identity, Repo, etc.).
- **Dependency Injection**: Injects required [Services](../03-application-layer/services-overview) into handlers during the server boot sequence.

The registry is a critical part of the [Startup and Boot Sequence](../01-getting-started/startup-and-boot-sequence), ensuring all methods are functional before the HTTP server begins accepting requests.

## Registration Order

The order of registration determines method availability. `XrpcMethodRegistry.m` initializes domain modules in the following sequence:

1. **Server**: `com.atproto.server.*`
2. **Identity**: `com.atproto.identity.*`
3. **Repo**: `com.atproto.repo.*`
4. **Sync**: `com.atproto.sync.*`
5. **AppView**: `app.bsky.*`
6. **Admin**: `com.atproto.admin.*`
7. **Label & Moderation**: `com.atproto.label.*`, `com.atproto.moderation.*`

## Troubleshooting

The registry is strictly a wiring layer and does not contain endpoint logic.

- **Method Not Found (404/501)**: Verify the NSID is included in the registration sequence.
- **Dependency Error**: Check the service injection within the relevant domain module registration.
- **Logic Bug**: Investigate the domain handler or the underlying service; the registry is likely not the cause of runtime execution errors.

## Related
- [XRPC Dispatch](./xrpc-dispatch)
- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [Domain Methods](./domain-methods)
- [Services Overview](../03-application-layer/services-overview)
- [Startup and Boot Sequence](../01-getting-started/startup-and-boot-sequence)
- [Documentation Map](../11-reference/documentation-map.md)

