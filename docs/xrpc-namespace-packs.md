# XrpcAppBskyMethods Namespace Pack Refactoring

**Status:** Phase 1 Infrastructure Complete

## Overview

The `XrpcAppBskyMethods.m` file (~3259 lines) has been decomposed into namespace packs for better maintainability and testability. This document tracks the phased refactoring approach.

## Phase 1: Infrastructure (COMPLETE)

Created 4 namespace pack modules:

| Pack | Scope | Lines |
|------|-------|-------|
| `XrpcAppBskyActorPack` | Profile, preferences, search | ~200 |
| `XrpcAppBskyFeedPack` | Timeline, posts, likes, generators | ~200 |
| `XrpcAppBskyGraphPack` | Follows, mutes, blocks, relationships | ~210 |
| `XrpcAppBskyNotificationPack` | Notifications, push | ~170 |

## Phase 2: Integration (FUTURE)

The main `XrpcAppBskyMethods.m` will delegate to packs:

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

    [XrpcAppBskyFeedPack registerWithDispatcher:dispatcher
                                   appViewDatabase:appViewDatabase
                                        jwtMinter:jwtMinter
                                  adminController:adminController];

    // ... etc

    // Only register remaining inline handlers (draft, video, chat, unspecced)
}
```

## Benefits

1. **Reduced file size** - Main file will drop to ~500 lines (coordination only)
2. **Focused testing** - Each pack can be tested independently
3. **Parallel development** - Teams can work on different packs without conflicts
4. **Clear boundaries** - Code organization matches Lexicon namespaces

## File Locations

```
ATProtoPDS/Sources/Network/
├── XrpcAppBskyMethods.h/.m        # Coordinator (future)
├── XrpcAppBskyActorPack.h/.m      # Actor namespace
├── XrpcAppBskyFeedPack.h/.m       # Feed namespace
├── XrpcAppBskyGraphPack.h/.m      # Graph namespace
├── XrpcAppBskyNotificationPack.h/.m # Notification namespace
└── XrpcAppBskyProxyMethodPack.h/.m  # Proxy-only methods (existing)
```

## Build Integration

Files are automatically picked up by the existing CMake glob:

```cmake
file(GLOB_RECURSE ATPROTO_XRPC_SOURCES
  "ATProtoPDS/Sources/Network/Xrpc*.m"
  ...
)
```
