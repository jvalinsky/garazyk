# AppView (syrena) XRPC Endpoint Gap Analysis

**Date**: 2026-04-21
**Compared against**: bluesky-social/atproto lexicon definitions + reference AppView (packages/bsky)
**Reference**: bluesky-social/atproto/packages/bsky/src/api (TypeScript AppView)

## Architecture Context

The AppView is a **read-optimized query service** that:
1. Ingests firehose events from relays via `AppViewIngestEngine`
2. Indexes records into SQLite via `AppViewIndexer` subclasses (actor, feed, graph, notification)
3. Serves hydrated query responses via XRPC endpoints

**Key distinction from PDS**: The PDS handles writes (createRecord, etc.) and serves raw repo data. The AppView handles reads (getTimeline, getProfile, etc.) with hydrated views (embedding profiles, counts, etc.).

The reference AppView also proxies some `com.atproto.*` read operations (resolveHandle, getRecord, queryLabels).

## Current State

### AppViewXRpcRoutePack.m — Only 4 endpoints registered

| Endpoint | Status |
|----------|--------|
| `app.bsky.feed.getTimeline` | ✅ Implemented |
| `app.bsky.feed.getAuthorFeed` | ✅ Implemented |
| `app.bsky.actor.getProfile` | ✅ Implemented |
| `app.bsky.notification.listNotifications` | ✅ Implemented |

### Services Available (Backend Logic Exists)

The following services have method implementations but **no XRPC route registration**:

| Service | Methods Available | Routes Missing |
|---------|------------------|----------------|
| **ActorService** | getProfile, getProfiles, getPreferences, putPreferences, searchActors, searchActorsTypeahead, getFollowersCount, getFollowsCount, getPostsCount | 5 endpoints |
| **FeedService** | getTimeline, getAuthorFeed, getPostThread, getFeed, getActorLikes, getPosts, getPostByURI | 5 endpoints |
| **GraphService** | getFollows, getFollowers, getBlocks, getMutes, muteActor, unmuteActor, getRelationship, getLikes, getRepostedBy, getStarterPack, getStarterPacksForActor | 11+ endpoints |
| **NotificationService** | registerPush, unregisterPush, getNotifications, markNotificationsAsRead, getUnreadCount, putActivitySubscription, getActivitySubscriptions | 7+ endpoints |
| **BookmarkService** | getBookmarks, indexBookmark, unindexBookmark | 0 endpoints (PDS handles route) |
| **ChatService** | createConversation, getConversation, listConversations, sendMessage, getMessages, addReaction, removeReaction, muteConversation, unmuteConversation, etc. | 0 endpoints (PDS handles route) |
| **GroupService** | createGroup, editGroup, deleteGroup, addMembers, removeMembers, listMembers, etc. | 0 endpoints (PDS handles route) |
| **ModerationService** | emitModerationEvent, queryModerationStatuses, getModerationRecord, getModerationRepo, etc. | 0 endpoints (PDS handles route) |

---

## Gap Analysis: AppView-Specific Endpoints

These are endpoints the **reference AppView** serves that our AppView does NOT. The PDS may also serve some of these (noted where applicable).

### app.bsky.actor (5 missing from AppView)

| Endpoint | Service Method Exists | PDS Route Exists | Priority |
|----------|----------------------|------------------|----------|
| `getProfiles` | ✅ ActorService.getProfilesForActors | ✅ (PDS has it) | **P1** |
| `searchActors` | ✅ ActorService.searchActors | ✅ (PDS has it) | **P1** |
| `searchActorsTypeahead` | ✅ ActorService.searchActorsTypeahead | ✅ (PDS has it) | **P1** |
| `getPreferences` | ✅ ActorService.getPreferencesForActor | ✅ (PDS has it) | **P1** |
| `putPreferences` | ✅ ActorService.putPreferencesForActor | ✅ (PDS has it) | **P1** |
| `getSuggestions` | ❌ No service method | ✅ (PDS has it) | **P2** |

### app.bsky.feed (5 missing from AppView)

| Endpoint | Service Method Exists | PDS Route Exists | Priority |
|----------|----------------------|------------------|----------|
| `getPostThread` | ✅ FeedService.getPostThread | ✅ (PDS has it) | **P0** |
| `getFeed` | ✅ FeedService.getFeed | ✅ (PDS has it) | **P1** |
| `getActorLikes` | ✅ FeedService.getActorLikes | ✅ (PDS has it) | **P2** |
| `getPosts` | ✅ FeedService.getPosts | ✅ (PDS has it) | **P1** |
| `getFeedGenerators` | ❌ No service method | ✅ (PDS has it) | **P2** |

Note: `getLikes`, `getRepostedBy`, `getListFeed`, `getActorFeeds`, `getSuggestedFeeds`, `getQuotes`, `searchPosts`, `getFeedGenerator`, `describeFeedGenerator`, `getFeedSkeleton`, `sendInteractions` are served by PDS but not by AppView. The reference AppView serves all of these.

### app.bsky.graph (11+ missing from AppView)

| Endpoint | Service Method Exists | PDS Route Exists | Priority |
|----------|----------------------|------------------|----------|
| `getFollows` | ✅ GraphService.getFollowsForActor | ✅ (PDS has it) | **P1** |
| `getFollowers` | ✅ GraphService.getFollowersForActor | ✅ (PDS has it) | **P1** |
| `getBlocks` | ✅ GraphService.getBlocksForActor | ✅ (PDS has it) | **P1** |
| `getMutes` | ✅ GraphService.getMutesForActor | ✅ (PDS has it) | **P1** |
| `getRelationships` | ✅ GraphService.getRelationship | ✅ (PDS has it) | **P1** |
| `getLikes` | ✅ GraphService.getLikesForURI | ✅ (PDS has it) | **P1** |
| `getRepostedBy` | ✅ GraphService.getRepostedByForURI | ✅ (PDS has it) | **P1** |
| `getStarterPack` | ✅ GraphService.getStarterPack | ✅ (PDS has it) | **P2** |
| `getStarterPacks` | ✅ GraphService.getStarterPacksForActor | ✅ (PDS has it) | **P2** |
| `muteActor` | ✅ GraphService.muteActor | ✅ (PDS has it) | **P2** |
| `unmuteActor` | ✅ GraphService.unmuteActor | ✅ (PDS has it) | **P2** |

Note: Many more graph endpoints exist in the reference AppView that we don't serve from either service (getKnownFollowers, getList, getLists, getListMutes, getListBlocks, getListsWithMembership, getStarterPacksWithMembership, getSuggestedFollowsByActor, muteActorList, unmuteActorList, muteThread, unmuteThread, searchStarterPacks, getActorStarterPacks).

### app.bsky.notification (7+ missing from AppView)

| Endpoint | Service Method Exists | PDS Route Exists | Priority |
|----------|----------------------|------------------|----------|
| `getUnreadCount` | ✅ NotificationService.getUnreadCountForActor | ✅ (PDS has it) | **P1** |
| `updateSeen` | ✅ NotificationService.markNotificationsAsReadForActor | ✅ (PDS has it) | **P1** |
| `registerPush` | ✅ NotificationService.registerPushForActor | ❌ (PDS missing too) | **P2** |
| `unregisterPush` | ✅ NotificationService.unregisterPushForActor | ❌ (PDS missing too) | **P2** |
| `putActivitySubscription` | ✅ NotificationService.putActivitySubscriptionForActor | ✅ (PDS has it) | **P2** |
| `listActivitySubscriptions` | ✅ NotificationService.getActivitySubscriptionsForActor | ✅ (PDS has it) | **P2** |
| `getPreferences` | ❌ No service method | ✅ (PDS has it) | **P2** |
| `putPreferences` | ❌ No service method | ✅ (PDS has it) | **P2** |
| `putPreferencesV2` | ❌ No service method | ✅ (PDS has it) | **P2** |

### com.atproto.* Proxied Endpoints (5 missing from AppView)

The reference AppView proxies these read-only `com.atproto.*` endpoints:

| Endpoint | Reference Has | We Have | Priority |
|----------|--------------|---------|----------|
| `com.atproto.identity.resolveHandle` | ✅ | ❌ | **P2** |
| `com.atproto.repo.getRecord` | ✅ | ❌ | **P2** |
| `com.atproto.label.queryLabels` | ✅ | ❌ | **P2** |
| `com.atproto.admin.getAccountInfos` | ✅ | ❌ | **P3** |
| `com.atproto.admin.getSubjectStatus` | ✅ | ❌ | **P3** |
| `com.atproto.temp.fetchLabels` | ✅ | ❌ | **P3** (deprecated) |

### AppView Indexers (Ingest Pipeline)

The AppView has 4 indexers that process firehose events:

| Indexer | Purpose | Status |
|---------|---------|--------|
| AppViewActorIndexer | Indexes profile records, handles, avatars | ✅ Exists |
| AppViewFeedIndexer | Indexes posts, likes, reposts, feeds | ✅ Exists |
| AppViewGraphIndexer | Indexes follows, blocks, mutes, lists | ✅ Exists |
| AppViewNotificationIndexer | Indexes notification events | ✅ Exists |

**Missing indexers** (reference AppView has these):
- Bookmark indexer (BookmarkService has index/unindex methods but no firehose indexer)
- Chat/Group indexer (ChatService/GroupService have methods but no firehose indexer)
- Moderation indexer (ModerationService has methods but no firehose indexer)
- Labeler indexer (for app.bsky.labeler.getServices)
- Draft indexer (for app.bsky.draft endpoints)
- Age assurance indexer
- Contact indexer

---

## Summary Table

| Category | Reference Has | AppView Routes | Service Methods | Gap |
|----------|--------------|----------------|-----------------|-----|
| app.bsky.actor | 5 query endpoints | 1 | 6 | **4 routes** |
| app.bsky.feed | 15 query endpoints | 2 | 7 | **5 routes** |
| app.bsky.graph | 23 query/mutation endpoints | 0 | 11+ | **11+ routes** |
| app.bsky.notification | 10 endpoints | 1 | 7+ | **7+ routes** |
| app.bsky.labeler | 1 query endpoint | 0 | 0 | **1 route** |
| app.bsky.unspecced | 16+ endpoints | 0 | 0 | **16+ routes** |
| app.bsky.bookmark | 3 endpoints | 0 | 3 | **0 routes** (PDS serves) |
| app.bsky.draft | 4 endpoints | 0 | 0 | **0 routes** (PDS serves) |
| app.bsky.ageassurance | 3 endpoints | 0 | 0 | **3 routes** |
| app.bsky.contact | 8 endpoints | 0 | 0 | **8 routes** |
| com.atproto proxy | 5 endpoints | 0 | 0 | **5 routes** |
| chat.bsky | 25+ endpoints | 0 | 20+ | **0 routes** (PDS serves) |

**Total AppView gap**: ~60+ endpoints where service methods exist but routes aren't registered, plus ~30+ endpoints where neither service methods nor routes exist.

---

## Key Insight: Service Methods vs Routes

The biggest finding is that **service methods exist for many endpoints but XRPC routes aren't registered in the AppView**. This means:

1. **Quick wins**: Registering routes for existing service methods (ActorService, FeedService, GraphService, NotificationService) would add ~25 endpoints with minimal code.

2. **Missing services**: Some endpoints need new service methods (getFeedGenerators, getPreferences for notifications, unspecced endpoints, etc.)

3. **Architecture decision**: The PDS currently serves most `app.bsky.*` endpoints directly. In production AT Protocol, the PDS **proxies** these to the AppView. We need to decide:
   - **Option A**: Keep PDS serving app.bsky.* directly (current state, simpler)
   - **Option B**: Move app.bsky.* query endpoints to AppView, have PDS proxy (reference architecture, more scalable)

---

## Implementation Priority

### Phase 1: Wire existing services to routes (quick wins)

Register XRPC routes for service methods that already exist:

1. `app.bsky.actor.getProfiles` → ActorService.getProfilesForActors
2. `app.bsky.actor.searchActors` → ActorService.searchActors
3. `app.bsky.actor.searchActorsTypeahead` → ActorService.searchActorsTypeahead
4. `app.bsky.actor.getPreferences` → ActorService.getPreferencesForActor
5. `app.bsky.actor.putPreferences` → ActorService.putPreferencesForActor
6. `app.bsky.feed.getPostThread` → FeedService.getPostThread
7. `app.bsky.feed.getFeed` → FeedService.getFeed
8. `app.bsky.feed.getActorLikes` → FeedService.getActorLikes
9. `app.bsky.feed.getPosts` → FeedService.getPosts
10. `app.bsky.graph.getFollows` → GraphService.getFollowsForActor
11. `app.bsky.graph.getFollowers` → GraphService.getFollowersForActor
12. `app.bsky.graph.getBlocks` → GraphService.getBlocksForActor
13. `app.bsky.graph.getMutes` → GraphService.getMutesForActor
14. `app.bsky.graph.getLikes` → GraphService.getLikesForURI
15. `app.bsky.graph.getRepostedBy` → GraphService.getRepostedByForURI
16. `app.bsky.notification.getUnreadCount` → NotificationService.getUnreadCountForActor
17. `app.bsky.notification.updateSeen` → NotificationService.markNotificationsAsReadForActor
18. `app.bsky.notification.registerPush` → NotificationService.registerPushForActor
19. `app.bsky.notification.unregisterPush` → NotificationService.unregisterPushForActor

### Phase 2: Add missing service methods + routes

1. `app.bsky.actor.getSuggestions` (new service method needed)
2. `app.bsky.feed.getFeedGenerators` (new service method needed)
3. `app.bsky.notification.getPreferences` (new service method needed)
4. `app.bsky.notification.putPreferences` (new service method needed)
5. `app.bsky.notification.putPreferencesV2` (new service method needed)

### Phase 3: Architecture decision — PDS proxy vs AppView direct

Decide whether to:
- Have the PDS proxy `app.bsky.*` queries to the AppView (reference architecture)
- Or keep the PDS serving them directly (simpler, current state)

This affects how clients discover and use the AppView.

### Phase 4: New feature namespaces

1. app.bsky.ageassurance (3 endpoints)
2. app.bsky.contact (8 endpoints)
3. com.atproto.* proxy endpoints (5 endpoints)
4. app.bsky.unspecced (16+ endpoints — many are skeleton/recommendation endpoints)
