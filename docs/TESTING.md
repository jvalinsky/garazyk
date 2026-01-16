## Network & Synchronization

The networking layer is the backbone of the PDS, handling HTTP/1.1 requests, XRPC commands, and WebSocket-based synchronization (Firehose).

### Core Networking
Tests in `Tests/Network` validate the custom HTTP stack implementation, ensuring it is robust enough to replace standard frameworks where necessary for portability (Linux/BSD).

- **HTTP Stack**: `HttpServerTests`, `HttpRequestParsingTests`, and `HttpResponseTests` verify compliance with HTTP/1.1, including:
  - **Parsing**: GET query parameters, POST JSON bodies, Multipart forms, and `Transfer-Encoding: chunked`.
  - **Routing**: `HttpRouterTests` and `HttpRouteTrieTests` validate performant O(k) routing with support for parameterized (`/users/:id`) and wildcard (`/files/*`) paths.
  - **Memory Management**: `HttpBufferPoolTests` ensures high-throughput scenarios do not cause excessive GC pressure by recycling data buffers.
  - **Transport**: `PDSNetworkTransportLinuxTests` verifies BSD socket operations (recv/send, buffering) for non-Apple platforms.

### XRPC Protocol
Tests in `Tests/XRPC` ensure the PDS strictly adheres to the [XRPC specification](https://atproto.com/specs/xrpc).

- **Input Validation**: `XrpcInputValidationTests` ensures strict type checking:
  - **Query Params**: Validates Booleans (`true`/`false`), Integers, and Arrays (`?tag=a&tag=b`).
  - **Content-Type**: Enforces `application/json` for RPC bodies.
  - **Limits**: Checks rejection of oversized payloads and malformed query strings.
- **Error Mapping**: `XrpcErrorResponseTests` validates that internal errors map to correct XRPC error codes and HTTP statuses:
  - `InvalidToken` / `ExpiredToken` -> 401 Unauthorized
  - `RateLimitExceeded` -> 429 Too Many Requests
  - `RecordNotFound` -> 404 Not Found
- **Integration**: `XrpcIntegrationTests` mocks external services (PLC Directory, Handle Resolver) to verify the PDS acts correctly as both an XRPC client and server.

### Synchronization (Firehose)
Tests in `Tests/Sync` cover the real-time event stream used to replicate data across the AT Protocol network.

- **WebSocket Layer**: `WebSocketServerTests` and `WebSocketUpgradeHandlerTests` verify the HTTP-to-WebSocket upgrade handshake (RFC 6455), subprotocol negotiation, and connection lifecycle.
- **Event Formatting**: `EventFormatterTests` verifies **DAG-CBOR** encoding/decoding compliance:
  - Roundtrip tests for primitive types and nested structures.
  - Specific encoding for `#commit`, `#identity`, and `#error` event frames.
- **Broadcasting**: `SubscribeReposHandlerTests` ensures that:
  - Repository commits (`RepoCommit`) are correctly translated into stream events.
  - Operations (creates, updates, deletes) are broadcast to all active subscribers.
  - Cursors and filters are respected.

### Security & Reliability
- **Rate Limiting**: `RateLimiterTests` verifies token bucket implementation for DID-based (5000/hr) and IP-based (100/min) limits, ensuring headers (`X-RateLimit-Remaining`) are set correctly.
- **SSL Pinning**: `SSLPinningTests` validates configuration for secure server-to-server communication.
