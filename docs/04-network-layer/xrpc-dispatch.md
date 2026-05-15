# XRPC Dispatch

XRPC dispatch bridges transport-level HTTP requests and domain logic. When a request matches the `/xrpc/*` prefix, the dispatch layer resolves the [NSID](../GLOSSARY.md#nsid) and invokes the registered handler.

The `XrpcDispatcher` handles:
- **NSID Resolution**: Mapping request paths to AT Protocol methods.
- **Registration**: Matching methods against those defined in the `XrpcMethodRegistry`.
- **Glue Logic**: Enforcing authentication policies (via `XrpcAuthHelper`), performing lexicon validation, and standardizing error formats.
- **Result Translation**: Converting service results into JSON or blob HTTP response payloads.

This layer delegates repository mutations, blob storage, and identity resolution to specialized [services](../03-application-layer/services-overview).

## Implementation Boundary

`XrpcDispatcher` and its associated route packs (e.g., `PDSHttpXrpcRoutePack`) define the boundary between the network and the application.

If an endpoint returns a `404 Not Found` or `501 Not Implemented`, the method is likely missing from the `XrpcMethodRegistry`. If authentication fails before the service code executes, the issue typically lies in the `XrpcAuthHelper` or the dispatcher's middleware stack.

## Debugging Dispatch

Investigate the XRPC dispatch layer if:
- A registered NSID fails to resolve or returns unexpected routing errors.
- Authentication fails globally or for specific authenticated methods. See [Auth Helpers](./auth-helpers).
- The response structure violates AT Protocol expectations (e.g., incorrect error field names).
- You need to add middleware that affects all XRPC calls, such as global logging or rate limiting.

## Related
- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)
- [Method Registry](./method-registry)
- [Domain Methods](./domain-methods)
- [Auth Helpers](./auth-helpers)
- [Request Lifecycle](../01-getting-started/request-lifecycle)

