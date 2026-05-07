# Node #965 — File Role Map and Semantic Header Templates

This plan maps each #965 file to a semantic role and provides role-specific HeaderDoc templates.

## Role taxonomy
- **PARSER**: protocol grammar/state parsing and parse error semantics
- **TRANSPORT**: connection/session I/O and request lifecycle
- **ROUTING**: route matching, dispatch, and response flow control
- **POLICY_SECURITY**: retry policy, rate limiting, SSRF, TLS pinning
- **ROUTE_PACK**: endpoint registration/wiring for HTTP route namespaces
- **INFRA**: supporting network utilities (buffers/chunked body processing)

## File role map (36 files)

### PARSER
- `Garazyk/Sources/Network/Http1Parser.h`
- `Garazyk/Sources/Network/Http1Parser.m`
- `Garazyk/Sources/Network/Http1PipelinePolicy.h`
- `Garazyk/Sources/Network/Http1PipelinePolicy.m`
- `Garazyk/Sources/Network/HttpParsing.h`
- `Garazyk/Sources/Network/HttpParsing.m`

### TRANSPORT
- `Garazyk/Sources/Network/HttpConnectionDriver.h`
- `Garazyk/Sources/Network/HttpConnectionDriver.m`
- `Garazyk/Sources/Network/HttpProtocolSession.h`
- `Garazyk/Sources/Network/HttpProtocolSession.m`
- `Garazyk/Sources/Network/HttpRequest.m`
- `Garazyk/Sources/Network/PDSNetworkTransportLinux.m`
- `Garazyk/Sources/Network/PDSNetworkTransportMac.m`
- `Garazyk/Sources/Network/WebSocketUpgradeHandler.m`

### ROUTING
- `Garazyk/Sources/Network/HttpRequestDispatcher.h`
- `Garazyk/Sources/Network/HttpRequestDispatcher.m`
- `Garazyk/Sources/Network/HttpResponseSender.m`
- `Garazyk/Sources/Network/HttpRouteTrie.m`
- `Garazyk/Sources/Network/HttpRouter.m`
- `Garazyk/Sources/Network/HttpStreamingBody.m`

### POLICY_SECURITY
- `Garazyk/Sources/Network/HttpRetryPolicy.h`
- `Garazyk/Sources/Network/HttpRetryPolicy.m`
- `Garazyk/Sources/Network/RateLimiter.m`
- `Garazyk/Sources/Network/SSRFValidator.h`
- `Garazyk/Sources/Network/SSRFValidator.m`
- `Garazyk/Sources/Network/SSLPinningManager.m`

### ROUTE_PACK
- `Garazyk/Sources/Network/PDSHttpMSTViewerRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpMetricsRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpNodeInfoRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpOAuthDemoRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpOAuthRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpPDSAdminRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpRelayAPIRoutePack.m`
- `Garazyk/Sources/Network/PDSHttpWellKnownRoutePack.m`

### INFRA
- `Garazyk/Sources/Network/HttpBufferPool.m`
- `Garazyk/Sources/Network/HttpChunkedBodyParser.m`

---

## Role-specific semantic templates

## PARSER template
```objc
/*!
 @file <FileName>

 @abstract Parses <protocol/structure> into <internal representation>.

 @discussion Implements <state machine/grammar> for <scope>. Produces
 deterministic parse errors for malformed input and leaves transport ownership
 to connection/session layers.
 */
```

## TRANSPORT template
```objc
/*!
 @file <FileName>

 @abstract Coordinates <connection/session/request> lifecycle for network I/O.

 @discussion Handles <read/write/timeout/backpressure> flow between socket and
 higher-level dispatch layers. Does not own application auth or business logic.
 */
```

## ROUTING template
```objc
/*!
 @file <FileName>

 @abstract Routes incoming HTTP requests to registered handlers.

 @discussion Applies <matching/precedence> rules and dispatches to route
 handlers, then normalizes response emission semantics. Does not implement
 endpoint-specific domain logic.
 */
```

## POLICY_SECURITY template
```objc
/*!
 @file <FileName>

 @abstract Enforces <retry/rate/SSRF/TLS> policy for network safety.

 @discussion Encapsulates policy decisions for <specific risk/control>,
 including decision criteria and failure behavior. Integrates with network
 pipeline without owning endpoint routing.
 */
```

## ROUTE_PACK template
```objc
/*!
 @file <FileName>

 @abstract Registers HTTP routes for the <namespace/feature> surface.

 @discussion Wires endpoints into the server router and delegates handling to
 runtime/service components. Defines route exposure, not business execution.
 */
```

## INFRA template
```objc
/*!
 @file <FileName>

 @abstract Provides supporting network utility for <buffering/chunk parsing>.

 @discussion Supplies low-level helper behavior used by transport and parser
 layers, with predictable memory/streaming semantics.
 */
```
