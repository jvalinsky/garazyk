# XRPC Dispatch

XRPC dispatch is the adapter between transport-level requests and domain logic. Once a request matches the `/xrpc/*` prefix, this layer resolves the NSID and invokes the registered handler.

## Responsibilities
- **NSID Resolution**: Mapping request paths to specific AT Protocol methods.
- **Registration Verification**: Ensuring the requested method is registered in the runtime.
- **Glue Logic**: Applying authentication policies, lexicon validation, and standardizing error shapes.
- **Result Translation**: Converting service or handler results into HTTP response payloads.

The dispatch layer does not define repository mutations, blob policies, or identity resolution rules; these are delegated to the underlying services and identity modules.

## Implementation Boundary
`XrpcDispatcher` represents the boundary between request arrival and service execution. 
- **Method exists, wrong behavior**: The bug likely resides in the service layer or domain handler.
- **Method not found (404/501)**: The bug resides in the registration or dispatch mapping.
- **Auth/Validation failure**: The failure occurs within the dispatch glue logic before service code executes.

## Investigation Points
Investigate the XRPC dispatch layer when:
- An endpoint returns a "method not found" or "invalid request" error.
- Authentication fails before domain services are invoked.
- The response structure suggests a protocol-level serialization error.
- Multiple handlers appear to conflict for the same NSID.

## Related
- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)
- [Method Registry](./method-registry)
- [Domain Methods](./domain-methods)
- [Auth Helpers](./auth-helpers)
- [Request Lifecycle](../01-getting-started/request-lifecycle)

