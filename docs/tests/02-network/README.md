---
title: Network Tests
---

# Network Tests

Tests for HTTP server, XRPC protocol, WebSocket/firehose, and network transport layer.

## Files

| File | Description |
|------|-------------|
| [http-stack.md](http-stack) | HTTP server lifecycle, routing, chunked streaming, rate limiting |
| [xrpc.md](xrpc) | XRPC method handling, input validation, error responses, lexicon validation |
| [websocket.md](websocket) | WebSocket server, firehose event streaming, subscribeRepos handler |
| [transport.md](transport) | Network transport, SSL pinning, Linux socket operations |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| HttpServerTests | Tests/Network/HttpServerTests.m | HTTP server lifecycle |
| HttpRouterTests | Tests/Network/HttpRouterTests.m | Route matching |
| HttpBufferPoolTests | Tests/Network/HttpBufferPoolTests.m | Buffer pool management |
| HttpChunkedBodyParserTests | Tests/Network/HttpChunkedBodyParserTests.m | Chunked transfer encoding |
| HttpRequestParsingTests | Tests/Network/HttpRequestParsingTests.m | HTTP request parsing |
| HttpResponseTests | Tests/Network/HttpResponseTests.m | HTTP response handling |
| HttpRouteTrieTests | Tests/Network/HttpRouteTrieTests.m | Route trie data structure |
| HttpStreamingBodyTests | Tests/Network/HttpStreamingBodyTests.m | Streaming body handling |
| ATProtoHttpServerBuilderTests | Tests/Network/ATProtoHttpServerBuilderTests.m | Server builder configuration |
| RateLimiterTests | Tests/Network/RateLimiterTests.m | Token-bucket limiting |
| RateLimitingTests | Tests/Network/RateLimitingTests.m | Rate limiting integration |
| ATProtoNetworkTransportTests | Tests/Network/ATProtoNetworkTransportTests.m | Network transport layer |
| ATProtoNetworkTransportLinuxTests | Tests/Network/ATProtoNetworkTransportLinuxTests.m | Linux sockets |
| SSLPinningTests | Tests/Network/SSLPinningTests.m | Certificate pinning |
| XrpcHandlerTests | Tests/XRPC/XrpcHandlerTests.m | XRPC dispatch |
| XrpcInputValidationTests | Tests/XRPC/XrpcInputValidationTests.m | Input validation |
| LexiconValidationTests | Tests/Lexicon/LexiconValidationTests.m | Schema validation |
| LexiconResolveXrpcTests | Tests/Network/LexiconResolveXrpcTests.m | Lexicon XRPC resolution |
| XrpcIntegrationTests | Tests/Network/XrpcIntegrationTests.m | XRPC integration |
| XrpcMethodRegistryTests | Tests/Network/XrpcMethodRegistryTests.m | Method registry |
| XrpcProxyTests | Tests/Network/XrpcProxyTests.m | XRPC proxy handling |
| XRPCErrorTests | Tests/Network/XRPCErrorTests.m | XRPC error responses |
| WebSocketServerTests | Tests/Sync/WebSocketServerTests.m | WebSocket protocol |
| WebSocketUpgradeHandlerTests | Tests/Network/WebSocketUpgradeHandlerTests.m | WebSocket upgrade |
| SubscribeReposHandlerTests | Tests/Sync/SubscribeReposHandlerTests.m | Firehose streaming |
| AdminAuthModerationTests | Tests/Network/AdminAuthModerationTests.m | Admin moderation auth |
| AdminAuthSyncTests | Tests/Network/AdminAuthSyncTests.m | Admin sync auth |
| AdminAuthXrpcTests | Tests/Network/AdminAuthXrpcTests.m | Admin XRPC auth |
| RepoAuthIdentityTests | Tests/Network/RepoAuthIdentityTests.m | Repo identity auth |
| RepoAuthRepoTests | Tests/Network/RepoAuthRepoTests.m | Repo operations auth |
| RepoAuthServerTests | Tests/Network/RepoAuthServerTests.m | Repo server auth |
| RepoAuthTempTests | Tests/Network/RepoAuthTempTests.m | Temp repo auth |
| SecurityHardeningTests | Tests/Network/SecurityHardeningTests.m | Security hardening |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/HttpServerTests
./build/tests/AllTests -only-testing:AllTests/XrpcHandlerTests
./build/tests/AllTests -only-testing:AllTests/WebSocketServerTests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [XRPC Protocol Reference](../../architecture/XRPC_PROTOCOL_REFERENCE) - XRPC specification
- [Architecture Diagrams](../../architecture/ARCHITECTURE_DIAGRAMS) - System diagrams
- [Security Tests](../05-security/README) - Authorization and validation
- [Integration Tests](../06-integration/README) - E2E network flows
- [SSRF Protection](../../security/SSRF_PROTECTION) - Network security
