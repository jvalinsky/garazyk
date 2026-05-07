# Group 02-network-core: Network Core

## Directories

Network/ (Http*, RateLimiter, SSL*, SSRF*, WebSocketUpgrade)

## Audit Status

- [x] Audit complete
- [ ] Rewrite complete

## Classification Notes

- **A** = comprehensive HeaderDoc coverage for the public API.
- **B** = partial or inconsistent HeaderDoc coverage; some declarations are still undocumented or rely on inline comments.
- **C** = inline comments only; no structured HeaderDoc.
- **D** = no comments at all.

## Findings Summary

The strongest documentation is concentrated in the server/router/transport headers. The main gaps are:

- parser and pipeline helper files that use only inline comments or none at all,
- route-pack headers that document the type but not the route-registration method,
- implementation files that have a file banner but no method/helper documentation,
- comments that restate code flow instead of explaining why,
- a few LLM-like or self-referential comments in implementation code.

## File Inventory

| File | Quality | Issues |
|------|---------|--------|
| Http1Parser.h | C | Inline comments only; no HeaderDoc, no file/class block, and comments mostly restate control flow. |
| Http1Parser.m | C | Inline implementation comments/banners only; no HeaderDoc. |
| Http1PipelinePolicy.h | C | Inline comments only; no HeaderDoc. |
| Http1PipelinePolicy.m | D | No comments at all. |
| HttpBufferPool.h | B | Strong method docs, but no top-level `@file` block and no `@see` links. |
| HttpBufferPool.m | C | Single inline note only; no HeaderDoc. |
| HttpChunkedBodyParser.h | B | Strong API docs, but no top-level `@file` block and no `@see` links. |
| HttpChunkedBodyParser.m | C | Inline parsing notes only; no HeaderDoc. |
| HttpConnectionDriver.h | D | No comments at all. |
| HttpConnectionDriver.m | D | No comments at all. |
| HttpConnectionIOCoordinator.h | A | Comprehensive HeaderDoc; only minor gap is limited `@see` cross-references. |
| HttpConnectionIOCoordinator.m | B | File doc only; private helper methods are undocumented. |
| HttpParsing.h | D | No comments at all. |
| HttpParsing.m | D | No comments at all. |
| HttpProtocolDriver.h | B | File docs are good, but one public method is undocumented and `@see` links are absent. |
| HttpProtocolDriver.m | B | File doc plus inline implementation notes; helper behavior is not documented as API rationale. |
| HttpProtocolSession.h | B | Strong state-machine docs, but no file-level block and no `@see` links. |
| HttpProtocolSession.m | C | Inline comments only; no HeaderDoc. |
| HttpRequest.h | B | Good file doc, but several methods/properties use inline comments instead of block docs. |
| HttpRequest.m | C | Inline comments only; no HeaderDoc. |
| HttpRequestDispatcher.h | D | No comments at all. |
| HttpRequestDispatcher.m | D | No comments at all. |
| HttpResponse.h | A | Comprehensive HeaderDoc; property docs still rely on inline comments instead of block docs. |
| HttpResponse.m | C | Inline comments only; no HeaderDoc. |
| HttpResponseSender.h | A | Strong docs; missing richer `@see` links and the forward-declare note is inline. |
| HttpResponseSender.m | C | Single inline comment only; no HeaderDoc. |
| HttpRetryPolicy.h | C | Inline comments only; no HeaderDoc. |
| HttpRetryPolicy.m | C | Inline comments only; no HeaderDoc. |
| HttpRouteTrie.h | B | Strong API docs, but no top-level `@file` block and no `@see` links. |
| HttpRouteTrie.m | C | Inline comment only; no HeaderDoc. |
| HttpRouter.h | A | Strong docs; could use more `@see` links for trie/security helpers. |
| HttpRouter.m | C | Inline comments only; several restate control flow instead of explaining rationale. |
| HttpServer.h | A | Strong docs; could use more `@see` links and richer property cross-references. |
| HttpServer.m | B | File doc plus inline notes only; private/implementation helpers are undocumented. |
| HttpStreamingBody.h | B | Strong docs, but no top-level `@file` block and no `@see` links. |
| HttpStreamingBody.m | C | Inline error comments only; no HeaderDoc. |
| RateLimiter.h | B | Rich docs, but several blocks use `@brief`/prose instead of consistent HeaderDoc `@abstract`. |
| RateLimiter.m | C | Inline comments only; includes LLM-ish self-talk (`Let's use a different name`). |
| SSLPinningManager.h | B | Strong docs, but no top-level `@file` block and no `@see` links. |
| SSLPinningManager.m | C | Inline comments only; no HeaderDoc. |
| SSRFValidator.h | D | No comments at all. |
| SSRFValidator.m | C | Inline comments only; no HeaderDoc. |
| WebSocketUpgradeHandler.h | B | Strong docs, but no top-level `@file` block and no `@see` links. |
| WebSocketUpgradeHandler.m | D | No comments at all. |
| XRPCError.h | A | Strong docs; missing richer `@see` links to HTTP/XRPC helpers. |
| XRPCError.m | D | No comments at all. |
| PDSHttpServerBuilder.h | A | Strong docs; missing `@see` links to the route packs it wires together. |
| PDSHttpServerBuilder.m | B | File doc plus inline notes only; route registration flow is explained mostly in implementation comments. |
| PDSHttpMetricsRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpMetricsRoutePack.m | D | No comments at all. |
| PDSHttpNodeInfoRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpNodeInfoRoutePack.m | D | No comments at all. |
| PDSHttpOAuthDemoRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpOAuthDemoRoutePack.m | D | No comments at all. |
| PDSHttpOAuthRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpOAuthRoutePack.m | D | No comments at all. |
| PDSHttpPDSAdminRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpPDSAdminRoutePack.m | D | No comments at all. |
| PDSHttpRelayAPIRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpRelayAPIRoutePack.m | D | No comments at all. |
| PDSHttpWellKnownRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpWellKnownRoutePack.m | D | No comments at all. |
| PDSHttpXrpcRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpXrpcRoutePack.m | C | Inline route-registration comments only; no HeaderDoc. |
| PDSHttpMSTViewerRoutePack.h | B | Only a stub-level class doc; the route-registration method is undocumented. |
| PDSHttpMSTViewerRoutePack.m | D | No comments at all. |
| PDSNetworkTransportLinux.h | A | Strong docs; would benefit from an `@see` link to the macOS transport counterpart. |
| PDSNetworkTransportLinux.m | C | Inline comments only; no HeaderDoc. |
| PDSNetworkTransportMac.h | A | Strong docs; would benefit from an `@see` link to the Linux transport counterpart. |
| PDSNetworkTransportMac.m | C | Single inline transport-selection note only; no HeaderDoc. |

## Rewrite Decisions

_(read-only audit; no source files were modified)_

## Before/After Samples

_(not applicable in this audit pass)_
