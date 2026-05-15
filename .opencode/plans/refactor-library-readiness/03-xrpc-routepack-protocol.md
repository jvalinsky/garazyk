# Refactor 3: XRPC Route Pack Protocol

## Evidence

**25+ `Xrpc*Pack` classes** with no shared base class, protocol, or formal contract:

- Each has a differently-shaped `+registerWithDispatcher:...:` signature — different parameter names, types, order, and nullability
- Auth boilerplate (`extractDIDFromAuthHeader:jwtMinter:adminController:request:response:`) is copy-pasted in every handler
- Error construction (`XrpcErrorHelper setValidationError:`) repeated in every handler
- Import list (XrpcHandler.h, XrpcAuthHelper.h, XrpcErrorHelper.h, etc.) duplicated across all 25+ files
- Registration in `XrpcMethodRegistry.m` is ~50 explicit manual calls
- Middleware insertion is nonexistent — each pack inlines auth checks instead

**File sizes of Xrpc packs (lines of .m):**

| File | Lines |
|------|-------|
| XrpcToolsOzonePack.m | 1226 |
| XrpcAppBskyGraphPack.m | 1045 |
| XrpcChatBskyConvoPack.m | 883 |
| XrpcAppBskyFeedPack.m | 579 |
| XrpcAppBskyUnspeccedPack.m | 436 |
| XrpcAppBskyActorPack.m | 257 |
| XrpcAppBskyContactPack.m | 285 |
| XrpcAppBskyDraftsPack.m | 187 |
| XrpcAppBskyAgeAssurancePack.m | 157 |
| XrpcChatBskyActorPack.m | 123 |
| XrpcAppBskyProxyMethodPack.m | 69 |

## Why It Matters

Adding a new XRPC method (which is how you extend AT Protocol services) requires:
1. Writing a new pack file from scratch
2. Learning the non-standard, non-documented signature convention
3. Remembering to add the explicit registration call to `XrpcMethodRegistry.m`
4. Copy-pasting auth boilerplate

This is the #1 barrier to extensibility and library adoption. A formal protocol reduces adding a new NSID to ~50 lines.

## Proposed Solution

### Phase 1: Define `@protocol XrpcRoutePack`

```objc
@protocol XrpcRoutePack <NSObject>

/// Every route pack registers its handlers via this single entry point.
/// The services bag provides everything a handler needs — no more threading
/// of individual dependencies.
+ (void)registerWithRouter:(HttpRouter *)router
                  services:(id<XrpcRoutePackServices>)services;

@end
```

### Phase 2: Define `@protocol XrpcRoutePackServices`

A dependency bag that captures everything packs currently receive as individual parameters:

```objc
@protocol XrpcRoutePackServices <NSObject>

@property (readonly) id<XrpcAuthContext> authContext;
@property (readonly) id<PDSServiceContainer> services;
@property (readonly) id<XrpcLexiconResolver> lexiconResolver;
// Rate limiter, metrics, etc.

@end
```

### Phase 3: Define `@interface XrpcHandlerContext`

A context object provided to each handler invocation, eliminating inline auth extraction:

```objc
@interface XrpcHandlerContext : NSObject
@property (readonly) NSString *authenticatedDID;
@property (readonly) HttpRequest *request;
@property (readonly) HttpResponse *response;
@property (readonly) id<XrpcRoutePackServices> services;
- (BOOL)requireAuth:(NSError **)error;
- (BOOL)requireRole:(NSString *)role error:(NSError **)error;
@end
```

### Phase 4: Middleware Layer

Add middleware support to `XrpcHandler` (or `HttpRouter`) for:
- Auth extraction (runs before every handler, populates `XrpcHandlerContext.authenticatedDID`)
- Rate limiting
- Request logging
- CORS headers

This eliminates the `extractDIDFromAuthHeader:` copy-paste from every handler.

### Phase 5: Automatic Discovery (Optional)

Replace the explicit registration list in `XrpcMethodRegistry.m`:

```objc
// Before: 50 explicit calls
[XrpcAppBskyActorPack registerWithDispatcher:dispatcher ...];
[XrpcAppBskyFeedPack registerWithDispatcher:dispatcher ...];
// ... 48 more

// After: automatic discovery
for (Class cls in [XrpcRoutePackDiscoverer allRoutePackClasses]) {
    [cls registerWithRouter:router services:services];
}
```

Using `NSClassFromString` with naming convention or a `__attribute__((constructor))` registration pattern.

## Staging

| Step | Description | Rollback |
|------|-------------|----------|
| 1 | Define `XrpcRoutePack` protocol + `XrpcRoutePackServices` protocol | Revert protocol definition |
| 2 | Migrate 2 smallest packs (XrpcAppBskyProxyMethodPack, XrpcChatBskyActorPack) to new pattern | Revert 2 files |
| 3 | Define `XrpcHandlerContext` + middleware for auth extraction | Revert middleware |
| 4 | Migrate 3 medium packs (AgeAssurance, Actor, Contact) | Revert 3 files |
| 5 | Migrate remaining packs in batches (Feed, Graph, Convo, Ozone last — largest) | Revert each batch |
| 6 | Update XrpcMethodRegistry to use protocol-based registration | Revert registry change |
| 7 | Add rate-limiting middleware | Revert middleware addition |
| 8 | Remove old `extractDIDFromAuthHeader:` patterns | Revert cleanup |

## Dependencies

- None — this is a self-contained refactor within the Network module
- Each pack migration is independent and reversible
- The protocol is backward-compatible: new and old patterns can coexist during migration

## Characterization Tests

For each pack migration, verify:
- Same NSIDs are registered
- Same auth requirements are enforced
- Same validation logic applied
- Same error responses returned

Existing scenario tests in `scripts/scenarios/` provide integration-level coverage.

## Confidence: High

This is a textbook "extract interface" refactoring. The protocol formalizes what is currently an unwritten convention.
