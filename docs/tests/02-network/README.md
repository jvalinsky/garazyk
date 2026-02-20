# Network Tests

Tests for HTTP server, XRPC protocol, WebSocket/firehose, and network transport layer.

## Files

| File | Description |
|------|-------------|
| [http-stack.md](http-stack.md) | HTTP server lifecycle, routing, chunked streaming, rate limiting |
| [xrpc.md](xrpc.md) | XRPC method handling, input validation, error responses, lexicon validation |
| [websocket.md](websocket.md) | WebSocket server, firehose event streaming, subscribeRepos handler |
| [transport.md](transport.md) | Network transport, SSL pinning, Linux socket operations |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| HttpServerTests | Tests/Network/HttpServerTests.m | HTTP server lifecycle |
| HttpRouterTests | Tests/Network/HttpRouterTests.m | Route matching |
| RateLimiterTests | Tests/Network/RateLimiterTests.m | Token-bucket limiting |
| XrpcHandlerTests | Tests/XRPC/XrpcHandlerTests.m | XRPC dispatch |
| XrpcInputValidationTests | Tests/XRPC/XrpcInputValidationTests.m | Input validation |
| LexiconValidationTests | Tests/Lexicon/LexiconValidationTests.m | Schema validation |
| WebSocketServerTests | Tests/Sync/WebSocketServerTests.m | WebSocket protocol |
| SubscribeReposHandlerTests | Tests/Sync/SubscribeReposHandlerTests.m | Firehose streaming |
| PDSNetworkTransportLinuxTests | Tests/Network/PDSNetworkTransportLinuxTests.m | Linux sockets |
| SSLPinningTests | Tests/Network/SSLPinningTests.m | Certificate pinning |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/HttpServerTests
./build/tests/AllTests -only-testing:AllTests/XrpcHandlerTests
./build/tests/AllTests -only-testing:AllTests/WebSocketServerTests
```
