# XrpcAppBskyPack Namespace Pack Refactoring

**Status:** Phase 2 Complete

## Overview

We have decomposed the monolithic `XrpcAppBskyMethods.m` into modular namespace packs and standardized the top-level coordination into `XrpcAppBskyPack`.

## Modular Architecture

The `app.bsky` namespace is now managed by several specialized packs, all orchestrated by `XrpcAppBskyPack`:

| Pack | Scope |
|------|-------|
| `XrpcAppBskyActorPack` | Profile, preferences, and search. |
| `XrpcAppBskyFeedPack` | Timelines, posts, likes, and generators. |
| `XrpcAppBskyGraphPack` | Follows, mutes, blocks, and relationships. |
| `XrpcAppBskyNotificationPack` | Notifications and push delivery. |
| `XrpcAppBskyDraftsPack` | Draft management. |
| `XrpcAppBskyBookmarksPack` | Bookmark management. |
| `XrpcAppBskyProxyMethodPack` | Request forwarding to remote AppView. |
| `XrpcAppBskyUnspeccedPack` | Unspecced internal APIs. |

## Integration

`XrpcMethodRegistry` now delegates to `XrpcAppBskyPack` using the standard `XrpcRoutePack` protocol:

```objc
[XrpcAppBskyPack registerWithDispatcher:dispatcher services:routePackServices];
```

## Benefits

1. **Maintainability:** The primary coordination file is now focused on dependency management rather than endpoint logic.
2. **Isolation:** Each domain pack is independent and adheres to the `XrpcRoutePack` interface.
3. **Clarity:** Code organization directly reflects the ATProto Lexicon namespaces.

## Related
- [Architecture Overview](01-getting-started/architecture-overview)
- [API Reference](11-reference/api-reference)
- [Method Registry](04-network-layer/method-registry)
