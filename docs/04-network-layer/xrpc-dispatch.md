# XRPC Dispatch

XRPC dispatch bridges transport-level HTTP requests and domain logic. When a request matches the `/xrpc/*` prefix, the dispatch layer resolves the [NSID](../GLOSSARY.md#nsid) and invokes the registered handler.

The `XrpcDispatcher` handles:
- **NSID Resolution**: Mapping request paths to AT Protocol methods.
- **Registration**: Matching methods against those defined in the `XrpcMethodRegistry`.
- **Glue Logic**: Enforcing authentication policies (via `XrpcAuthHelper`), performing lexicon validation, and standardizing error formats.
- **Result Translation**: Converting service results into JSON or blob HTTP response payloads.

This layer delegates repository mutations, blob storage, and identity resolution to specialized [services](../03-application-layer/services-overview).

## Dispatch Ordering

The `XrpcHandler` dispatches requests through a strict priority pipeline (`XrpcHandler.m:244-360`):

1. **Protected methods** (`com.atproto.*` and server session methods): Always execute locally, bypassing any proxy interceptor entirely. This prevents header-injection attacks that could redirect auth sessions.
2. **Request interceptor** (if installed): The `XrpcProxyInterceptor` can intercept before further dispatch. It handles explicit `atproto-proxy` headers and AppView fallback routing.
3. **`atproto-proxy` header** (Industry standard): Honored only for non-protected, proxiable methods (`app.bsky.*`, `chat.bsky.*`, `tools.ozone.*`). Resolves the DID from the header value (e.g., `did:web:api.bsky.chat#bsky_chat`) via DID document lookup.
4. **Built-in fallbacks**: `app.bsky.*` → AppView, `tools.ozone.*` → Ozone, `chat.bsky.*` → Chat service. Each can be configured with direct URL/DID or resolved dynamically.
5. **Local handler**: If no proxy match, executes the registered local handler.

## Proxy Dispatch

The `atproto-proxy` header enables service-to-service routing through the PDS. The format is:

```
did:web:<domain>#<service-id>
```

For example, a chat request uses `did:web:localhost:2585#bsky_chat`. The PDS:
1. Parses the DID and service fragment from the header
2. Resolves the DID document for `did:web:<domain>` (fetches `https://<domain>/.well-known/did.json`)
3. Finds the service entry matching `#<service-id>` in the DID document
4. Extracts the `serviceEndpoint` URL
5. Proxies the XRPC request to that URL with a service JWT

Protected methods (`com.atproto.*`) are never proxied — they always execute locally regardless of the header.

## Implementation Boundary

`XrpcDispatcher` and its associated route packs (e.g., `ATProtoHttpXrpcRoutePack`) define the boundary between the network and the application.

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

