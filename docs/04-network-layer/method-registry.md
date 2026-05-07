# Method Registry

`XrpcMethodRegistry` defines the public XRPC interface and manages service dependency injection for domain handlers.

## Responsibilities
The registry manages:
- **NSID Mapping**: Associating NSIDs with specific handler implementations.
- **Domain Delegation**: Distributing method registration to domain-specific modules.
- **Dependency Management**: Injecting required services into domain handlers during the boot sequence.

The registry operates as a functional component of the application startup path, ensuring all protocol methods are correctly wired before the HTTP server begins accepting requests.

## Registration Sequence
The order of registration determines method availability and handling priority for overlapping NSIDs. `XrpcMethodRegistry.m` initializes domain modules in this order:
1. **Server Methods**: `com.atproto.server.*`
2. **Identity Methods**: `com.atproto.identity.*`
3. **Repo Methods**: `com.atproto.repo.*`
4. **Sync Methods**: `com.atproto.sync.*`
5. **AppView Methods**: `app.bsky.*`
6. **Admin Methods**: `com.atproto.admin.*`
7. **Label Methods**: `com.atproto.label.*`
8. **Moderation Methods**: `com.atproto.moderation.*`

## Implementation Boundary
The registry does not define endpoint logic or protocol semantics. It serves strictly as a wiring layer.
- **Missing Method**: Verify the NSID is included in the registration sequence.
- **Miswired Service**: Check the dependency injection within the relevant domain module registration.
- **Logic Error**: Investigate the domain handler or service layer; the registry is not responsible for runtime execution behavior.

## Related
- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)
- [XRPC Dispatch](./xrpc-dispatch)
- [Domain Methods](./domain-methods)
- [Services Overview](../03-application-layer/services-overview)
- [Startup and Boot Sequence](../01-getting-started/startup-and-boot-sequence)

