# HeaderDoc Plan: Node #965 (Network Core)

This checklist tracks Batch 1 execution for Deciduous node #965.

## Scope Rule
Include files under `Garazyk/Sources/Network` where basename does **not** contain `xrpc` (case-insensitive).

## Completion Criteria
- [ ] Every file listed below has HeaderDoc marker(s) (`/*!` and/or `///`)
- [ ] Public APIs and critical internals are documented concisely
- [ ] Stale/misleading comments removed
- [ ] Build/tests run for touched areas
- [ ] Deciduous node #965 updated with evidence

---

## Chunk 1 — HTTP parser/transport core

- [ ] `Garazyk/Sources/Network/Http1Parser.h`
- [ ] `Garazyk/Sources/Network/Http1Parser.m`
- [ ] `Garazyk/Sources/Network/Http1PipelinePolicy.h`
- [ ] `Garazyk/Sources/Network/Http1PipelinePolicy.m`
- [ ] `Garazyk/Sources/Network/HttpConnectionDriver.h`
- [ ] `Garazyk/Sources/Network/HttpConnectionDriver.m`
- [ ] `Garazyk/Sources/Network/HttpProtocolSession.h`
- [ ] `Garazyk/Sources/Network/HttpProtocolSession.m`
- [ ] `Garazyk/Sources/Network/HttpParsing.h`
- [ ] `Garazyk/Sources/Network/HttpParsing.m`
- [ ] `Garazyk/Sources/Network/HttpRequest.m`
- [ ] `Garazyk/Sources/Network/PDSNetworkTransportLinux.m`
- [ ] `Garazyk/Sources/Network/PDSNetworkTransportMac.m`

### Chunk 1 validation
- [ ] Build/tests pass for touched modules
- [ ] HeaderDoc marker scan clean for Chunk 1

---

## Chunk 2 — routing, retries, streaming, security helpers

- [ ] `Garazyk/Sources/Network/HttpRequestDispatcher.h`
- [ ] `Garazyk/Sources/Network/HttpRequestDispatcher.m`
- [ ] `Garazyk/Sources/Network/HttpResponseSender.m`
- [ ] `Garazyk/Sources/Network/HttpRetryPolicy.h`
- [ ] `Garazyk/Sources/Network/HttpRetryPolicy.m`
- [ ] `Garazyk/Sources/Network/HttpRouteTrie.m`
- [ ] `Garazyk/Sources/Network/HttpRouter.m`
- [ ] `Garazyk/Sources/Network/HttpStreamingBody.m`
- [ ] `Garazyk/Sources/Network/RateLimiter.m`
- [ ] `Garazyk/Sources/Network/SSRFValidator.h`
- [ ] `Garazyk/Sources/Network/SSRFValidator.m`
- [ ] `Garazyk/Sources/Network/SSLPinningManager.m`

### Chunk 2 validation
- [ ] Build/tests pass for touched modules
- [ ] HeaderDoc marker scan clean for Chunk 2

---

## Chunk 3 — route packs + remaining infra

- [ ] `Garazyk/Sources/Network/PDSHttpMSTViewerRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpMetricsRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpNodeInfoRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpOAuthDemoRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpOAuthRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpPDSAdminRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpRelayAPIRoutePack.m`
- [ ] `Garazyk/Sources/Network/PDSHttpWellKnownRoutePack.m`
- [ ] `Garazyk/Sources/Network/WebSocketUpgradeHandler.m`
- [ ] `Garazyk/Sources/Network/HttpBufferPool.m`
- [ ] `Garazyk/Sources/Network/HttpChunkedBodyParser.m`

### Chunk 3 validation
- [ ] Build/tests pass for touched modules
- [ ] HeaderDoc marker scan clean for Chunk 3

---

## Final close-out for node #965
- [ ] Missing list reduced from 36 -> 0
- [ ] Add Deciduous outcome node for Group 02 completion
- [ ] Link outcome to `#960`
- [ ] Set `#965` status to `completed`
