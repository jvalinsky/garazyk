# XrpcAppBskyMethods Namespace Pack Refactoring

**Status:** Phase 1 Infrastructure Complete

## Overview

We are decomposing the monolithic `XrpcAppBskyMethods.m` (~3259 lines) into modular namespace packs to improve maintainability and testability.

## Phase 1: Infrastructure (COMPLETE)

We have created four initial namespace pack modules:

| Pack | Scope | Approx. Lines |
|------|-------|-------|
| `XrpcAppBskyActorPack` | Profile, preferences, and search. | ~200 |
| `XrpcAppBskyFeedPack` | Timelines, posts, likes, and generators. | ~200 |
| `XrpcAppBskyGraphPack` | Follows, mutes, blocks, and relationships. | ~210 |
| `XrpcAppBskyNotificationPack` | Notifications and push delivery. | ~170 |

## Phase 2: Integration (PLANNED)

In this phase, `XrpcAppBskyMethods.m` will be refactored to delegate method registration to the individual packs:

```objc
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    // Delegate to namespace packs
    [XrpcAppBskyActorPack registerWithDispatcher:dispatcher
                                     appViewDatabase:appViewDatabase
                                          jwtMinter:jwtMinter
                                    adminController:adminController];
    // ...
}
```

## Benefits

1. **Maintainability:** Reduces the primary handler file size to coordination only.
2. **Isolation:** Each pack can be tested and developed independently without affecting other namespaces.
3. **Clarity:** Code organization now directly maps to ATProto Lexicon namespaces.

## Related
- [Architecture Overview](01-getting-started/architecture-overview)
- [API Reference](11-reference/api-reference)
- [Method Registry](04-network-layer/method-registry)
