# XRPC Endpoint Coverage Analysis

**Generated**: 2026-04-17
**Reference**: bluesky-social/atproto lexicons (main branch)
**Commit**: 326f66e3 (skip_plc_operations removal)

## Summary

Analysis of XRPC endpoint coverage across garazyk services:
- **kaszlak** (PDS)
- **campagnola** (PLC Directory Server)
- **zuk** (Relay)
- **syrena** (AppView)

## Service Responsibilities

### PDS (kaszlak)

The Personal Data Server is responsible for:
- Account management (`com.atproto.server.*`)
- Repository operations (`com.atproto.repo.*`)
- Identity operations (`com.atproto.identity.*`)
- Sync operations (`com.atproto.sync.*`) - for hosted repos
- Label queries (`com.atproto.label.*`)
- Moderation reporting (`com.atproto.moderation.createReport`)
- Blob storage and retrieval
- **Proxies** `app.bsky.*` and `chat.bsky.*` to AppViews

### PLC Directory (campagnola)

NOT an XRPC service. Implements HTTP API for:
- DID registration and resolution
- Operation submission and audit
- Key rotation

### Relay (zuk)

Aggregates firehoses from multiple PDSes:
- `com.atproto.sync.subscribeRepos` - firehose subscription
- `com.atproto.sync.requestCrawl` - request repo crawl
- `com.atproto.sync.listRepos` - list known repos
- `com.atproto.sync.getHostStatus` - PDS health status

### AppView (syrena)

App-specific query views:
- `app.bsky.actor.*` - profile queries
- `app.bsky.feed.*` - feed/timeline queries
- `app.bsky.graph.*` - social graph queries
- `app.bsky.notification.*` - notification queries
- `app.bsky.unspecced.*` - experimental queries

---

## com.atproto.server.* (PDS)

| NSID | Status | Notes |
|------|--------|-------|
| `createAccount` | ✅ IMPLEMENTED | |
| `createSession` | ✅ IMPLEMENTED | |
| `deleteSession` | ✅ IMPLEMENTED | |
| `refreshSession` | ✅ IMPLEMENTED | |
| `getSession` | ✅ IMPLEMENTED | |
| `describeServer` | ✅ IMPLEMENTED | |
| `createAppPassword` | ✅ IMPLEMENTED | |
| `listAppPasswords` | ✅ IMPLEMENTED | |
| `revokeAppPassword` | ✅ IMPLEMENTED | |
| `createInviteCode` | ✅ IMPLEMENTED | |
| `createInviteCodes` | ✅ IMPLEMENTED | |
| `getAccountInviteCodes` | ✅ IMPLEMENTED | |
| `activateAccount` | ✅ IMPLEMENTED | |
| `deactivateAccount` | ✅ IMPLEMENTED | |
| `checkAccountStatus` | ✅ IMPLEMENTED | |
| `confirmEmail` | ✅ IMPLEMENTED | |
| `requestAccountDelete` | ✅ IMPLEMENTED | |
| `requestPasswordReset` | ✅ IMPLEMENTED | |
| `resetPassword` | ✅ IMPLEMENTED | |
| `reserveSigningKey` | ✅ IMPLEMENTED | |
| `updateEmail` | ✅ IMPLEMENTED | |
| `requestEmailConfirmation` | ✅ IMPLEMENTED | |
| `requestEmailUpdate` | ✅ IMPLEMENTED | |
| `getServiceAuth` | ✅ IMPLEMENTED | |
| `deleteAccount` | ✅ IMPLEMENTED | Admin auth required |
| `getAccount` | ✅ IMPLEMENTED | Non-standard, admin |

**Coverage: 100%** (all 25 endpoints)

---

## com.atproto.repo.* (PDS)

| NSID | Status | Notes |
|------|--------|-------|
| `createRecord` | ✅ IMPLEMENTED | |
| `getRecord` | ✅ IMPLEMENTED | |
| `listRecords` | ✅ IMPLEMENTED | |
| `deleteRecord` | ✅ IMPLEMENTED | |
| `putRecord` | ✅ IMPLEMENTED | |
| `applyWrites` | ✅ IMPLEMENTED | |
| `describeRepo` | ✅ IMPLEMENTED | |
| `uploadBlob` | ✅ IMPLEMENTED | |
| `importRepo` | ✅ IMPLEMENTED | |
| `listMissingBlobs` | ✅ IMPLEMENTED | |
| `getBlob` | ✅ IMPLEMENTED | (non-standard, also in sync) |
| `deleteBlob` | ✅ IMPLEMENTED | Non-standard extension |
| `updateRecord` | ✅ IMPLEMENTED | Non-standard extension |
| `strongRef` | 📋 RECORD TYPE | Not an endpoint |

**Coverage: 100%** (all 11 XRPC endpoints + 2 non-standard)

---

## com.atproto.sync.* (PDS + Relay)

| NSID | PDS | Relay | Notes |
|------|-----|-------|-------|
| `getRepo` | ✅ | ✅ | |
| `getCheckout` | ✅ | ❓ | |
| `getHead` | ✅ | ❓ | |
| `getBlob` | ✅ | ✅ | |
| `listBlobs` | ✅ | ✅ | |
| `getBlocks` | ✅ | ✅ | |
| `getRecord` | ✅ | ✅ | |
| `getLatestCommit` | ✅ | ✅ | |
| `getRepoStatus` | ✅ | ❓ | |
| `listRepos` | ❓ | ✅ | PDS may not need this |
| `listReposByCollection` | ✅ | ❌ | |
| `listHosts` | ✅ | ❓ | |
| `getHostStatus` | ✅ | ✅ | |
| `notifyOfUpdate` | ✅ | ❌ | |
| `requestCrawl` | ❓ | ✅ | Relay-specific |
| `subscribeRepos` | ✅ | ✅ | Firehose |

**PDS Coverage: 93%** (14/15, minus requestCrawl which is relay-specific)
**Relay: Needs verification for zuk**

---

## com.atproto.identity.* (PDS)

| NSID | Status | Notes |
|------|--------|-------|
| `resolveHandle` | ✅ IMPLEMENTED | |
| `resolveDid` | ✅ IMPLEMENTED | |
| `resolveIdentity` | ✅ IMPLEMENTED | |
| `updateHandle` | ✅ IMPLEMENTED | |
| `getRecommendedDidCredentials` | ✅ IMPLEMENTED | |
| `requestPlcOperationSignature` | ✅ IMPLEMENTED | |
| `signPlcOperation` | ✅ IMPLEMENTED | |
| `submitPlcOperation` | ✅ IMPLEMENTED | |
| `refreshIdentity` | ✅ IMPLEMENTED | |

**Coverage: 100%** (all 9 endpoints)

---

## com.atproto.label.* (PDS/Labeler)

| NSID | Status | Notes |
|------|--------|-------|
| `queryLabels` | ✅ IMPLEMENTED | |
| `subscribeLabels` | ✅ IMPLEMENTED | WebSocket subscription |
| `getLabels` | ✅ IMPLEMENTED | Non-standard? |
| `createLabel` | ✅ IMPLEMENTED | Non-standard, labeler-only |

**Coverage: 100%**

---

## com.atproto.moderation.* (PDS)

| NSID | Status | Notes |
|------|--------|-------|
| `createReport` | ✅ IMPLEMENTED | |

**Coverage: 100%**

---

## com.atproto.admin.* (PDS Admin)

| NSID | Status | Notes |
|------|--------|-------|
| `deleteAccount` | ✅ IMPLEMENTED | |
| `disableAccountInvites` | ✅ IMPLEMENTED | |
| `disableInviteCodes` | ✅ IMPLEMENTED | |
| `enableAccountInvites` | ✅ IMPLEMENTED | |
| `getAccountInfo` | ✅ IMPLEMENTED | |
| `getAccountInfos` | ✅ IMPLEMENTED | |
| `getInviteCodes` | ✅ IMPLEMENTED | |
| `getSubjectStatus` | ✅ IMPLEMENTED | |
| `searchAccounts` | ✅ IMPLEMENTED | |
| `sendEmail` | ✅ IMPLEMENTED | |
| `updateAccountEmail` | ✅ IMPLEMENTED | |
| `updateAccountHandle` | ✅ IMPLEMENTED | |
| `updateAccountPassword` | ✅ IMPLEMENTED | |
| `updateAccountSigningKey` | ✅ IMPLEMENTED | |
| `updateSubjectStatus` | ✅ IMPLEMENTED | |
| `getAccountTakedown` | ⚠️ DEPRECATED | Returns 410 Gone |
| `moderateAccount` | ⚠️ DEPRECATED | Returns 410 Gone |
| `moderateRecord` | ⚠️ DEPRECATED | Returns 410 Gone |
| `takeDownAccount` | ⚠️ DEPRECATED | Returns 410 Gone |
| `getModerationReports` | ✅ IMPLEMENTED | Non-standard |

**Note**: Deprecated endpoints migrated to `tools.ozone.moderation.*`

---

## com.atproto.temp.* (PDS)

| NSID | Status | Notes |
|------|--------|-------|
| `addReservedHandle` | ✅ IMPLEMENTED | |
| `checkHandleAvailability` | ✅ IMPLEMENTED | |
| `checkSignupQueue` | ✅ IMPLEMENTED | |
| `dereferenceScope` | ✅ IMPLEMENTED | |
| `fetchLabels` | ✅ IMPLEMENTED | |
| `requestPhoneVerification` | ✅ IMPLEMENTED | |
| `revokeAccountCredentials` | ✅ IMPLEMENTED | |

**Coverage: 100%**

---

## com.atproto.lexicon.* (PDS)

| NSID | Status | Notes |
|------|--------|-------|
| `resolveLexicon` | ✅ IMPLEMENTED | |
| `schema` | 📋 RECORD TYPE | Not an endpoint |

**Coverage: 100%**

---

## app.bsky.* (AppView - Proxied from PDS)

### app.bsky.actor.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `getProfile` | ✅ | Syrena AppView |
| `getProfiles` | ✅ | Syrena AppView |
| `getSuggestions` | ✅ | Syrena AppView |
| `getPreferences` | ✅ | Syrena AppView |
| `putPreferences` | ✅ | Syrena AppView |
| `searchActors` | ✅ | Syrena AppView |
| `searchActorsTypeahead` | ✅ | Syrena AppView |
| `status` | ❓ | Check implementation |
| `profile` | 📋 RECORD TYPE | |

**PDS Coverage: 0% (proxied to AppView)**
**AppView Coverage: ~88%**

### app.bsky.feed.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `getTimeline` | ✅ | Syrena AppView |
| `getAuthorFeed` | ✅ | Syrena AppView |
| `getFeed` | ✅ | Syrena AppView |
| `getFeedSkeleton` | ✅ | Syrena AppView |
| `getFeedGenerator` | ✅ | Syrena AppView |
| `getFeedGenerators` | ✅ | Syrena AppView |
| `describeFeedGenerator` | ✅ | Syrena AppView |
| `getActorFeeds` | ✅ | Syrena AppView |
| `getLikes` | ✅ | Syrena AppView |
| `getPosts` | ✅ | Syrena AppView |
| `getPostThread` | ✅ | Syrena AppView |
| `getQuotes` | ✅ | Syrena AppView |
| `getRepostedBy` | ✅ | Syrena AppView |
| `getSuggestedFeeds` | ✅ | Syrena AppView |
| `getActorLikes` | ✅ | Syrena AppView |
| `getListFeed` | ✅ | Syrena AppView |
| `searchPosts` | ✅ | Syrena AppView |
| `sendInteractions` | ✅ | Syrena AppView |
| `post` | 📋 RECORD TYPE | |
| `like` | 📋 RECORD TYPE | |
| `repost` | 📋 RECORD TYPE | |
| `generator` | 📋 RECORD TYPE | |
| `postgate` | 📋 RECORD TYPE | |
| `threadgate` | 📋 RECORD TYPE | |

**AppView Coverage: 100%**

### app.bsky.graph.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `getFollowers` | ✅ | Syrena AppView |
| `getFollows` | ✅ | Syrena AppView |
| `getKnownFollowers` | ✅ | Syrena AppView |
| `getMutes` | ✅ | Syrena AppView |
| `getBlocks` | ✅ | Syrena AppView |
| `getList` | ✅ | Syrena AppView |
| `getLists` | ✅ | Syrena AppView |
| `getListMutes` | ❌ | **MISSING** |
| `getListBlocks` | ❌ | **MISSING** |
| `getRelationships` | ✅ | Syrena AppView |
| `getStarterPack` | ✅ | Syrena AppView |
| `getStarterPacks` | ✅ | Syrena AppView |
| `getStarterPacksWithMembership` | ✅ | Syrena AppView |
| `getActorStarterPacks` | ✅ | Syrena AppView |
| `getSuggestedFollowsByActor` | ✅ | Syrena AppView |
| `getListsWithMembership` | ❌ | **MISSING** |
| `searchStarterPacks` | ✅ | Syrena AppView |
| `muteActor` | ✅ | Syrena AppView |
| `unmuteActor` | ✅ | Syrena AppView |
| `muteActorList` | ✅ | Syrena AppView |
| `unmuteActorList` | ✅ | Syrena AppView |
| `muteThread` | ✅ | Syrena AppView |
| `unmuteThread` | ✅ | Syrena AppView |
| `follow` | 📋 RECORD TYPE | |
| `block` | 📋 RECORD TYPE | |
| `list` | 📋 RECORD TYPE | |
| `listitem` | 📋 RECORD TYPE | |
| `listblock` | 📋 RECORD TYPE | |
| `starterpack` | 📋 RECORD TYPE | |
| `verification` | 📋 RECORD TYPE | |

**AppView Coverage: ~85%** (missing getListMutes, getListBlocks, getListsWithMembership)

### app.bsky.notification.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `listNotifications` | ✅ | Syrena AppView |
| `getUnreadCount` | ✅ | Syrena AppView |
| `updateSeen` | ✅ | Syrena AppView |
| `getPreferences` | ✅ | Syrena AppView |
| `putPreferences` | ✅ | Syrena AppView |
| `putPreferencesV2` | ✅ | Syrena AppView |
| `registerPush` | ✅ | Syrena AppView |
| `unregisterPush` | ✅ | Syrena AppView |
| `listActivitySubscriptions` | ✅ | Syrena AppView |
| `putActivitySubscription` | ✅ | Syrena AppView |
| `declaration` | 📋 RECORD TYPE | |

**AppView Coverage: 100%**

### app.bsky.labeler.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `getServices` | ✅ | Syrena AppView |
| `service` | 📋 RECORD TYPE | |

**AppView Coverage: 100%**

### app.bsky.video.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `uploadVideo` | ✅ | Syrena AppView |
| `getJobStatus` | ✅ | Syrena AppView |
| `getUploadLimits` | ✅ | Syrena AppView |

**AppView Coverage: 100%**

### app.bsky.unspecced.*

| NSID | Status | Implementation |
|------|--------|----------------|
| `getConfig` | ✅ | Syrena AppView |
| `getPopularFeedGenerators` | ✅ | Syrena AppView |
| `getSuggestedFeeds` | ✅ | Syrena AppView |
| `getSuggestedUsers` | ✅ | Syrena AppView |
| `getTaggedSuggestions` | ✅ | Syrena AppView |
| `getTrendingTopics` | ✅ | Syrena AppView |
| `getAgeAssuranceState` | ❌ | **MISSING** |
| `getOnboardingSuggestedStarterPacks` | ❌ | **MISSING** |
| `getOnboardingSuggestedStarterPacksSkeleton` | ❌ | **MISSING** |
| `getOnboardingSuggestedUsersSkeleton` | ❌ | **MISSING** |
| `getPostThreadOtherV2` | ❌ | **MISSING** |
| `getPostThreadV2` | ❌ | **MISSING** |
| `getSuggestedFeedsSkeleton` | ❌ | **MISSING** |
| `getSuggestedOnboardingUsers` | ❌ | **MISSING** |
| `getSuggestedStarterPacks` | ❌ | **MISSING** |
| `getSuggestedStarterPacksSkeleton` | ❌ | **MISSING** |
| `getSuggestedUsersForDiscover` | ❌ | **MISSING** |
| `getSuggestedUsersForDiscoverSkeleton` | ❌ | **MISSING** |
| `getSuggestedUsersForExplore` | ❌ | **MISSING** |
| `getSuggestedUsersForExploreSkeleton` | ❌ | **MISSING** |
| `getSuggestedUsersForSeeMore` | ❌ | **MISSING** |
| `getSuggestedUsersForSeeMoreSkeleton` | ❌ | **MISSING** |
| `getSuggestedUsersSkeleton` | ❌ | **MISSING** |
| `getSuggestionsSkeleton` | ❌ | **MISSING** |
| `getTrends` | ❌ | **MISSING** |
| `getTrendsSkeleton` | ❌ | **MISSING** |
| `initAgeAssurance` | ❌ | **MISSING** |
| `searchActorsSkeleton` | ❌ | **MISSING** |
| `searchPostsSkeleton` | ❌ | **MISSING** |
| `searchStarterPacksSkeleton` | ❌ | **MISSING** |

**AppView Coverage: ~20%** (most skeleton/unspecce`d endpoints missing)

### app.bsky.bookmark.*, app.bsky.draft.*, app.bsky.contact.*

These are non-standard Bluesky extensions:

| NSID | Status | Notes |
|------|--------|-------|
| `bookmark.createBookmark` | ✅ | Non-standard |
| `bookmark.deleteBookmark` | ✅ | Non-standard |
| `bookmark.getBookmarks` | ✅ | Non-standard |
| `draft.createDraft` | ✅ | Non-standard |
| `draft.updateDraft` | ✅ | Non-standard |
| `draft.getDrafts` | ✅ | Non-standard |
| `draft.deleteDraft` | ✅ | Non-standard |

---

## chat.bsky.* (Chat AppView)

Currently minimal implementation:

| NSID | Status | Notes |
|------|--------|-------|
| `convo.getConvo` | ✅ | |
| `convo.getLog` | ✅ | |
| `convo.getMessages` | ✅ | |
| `convo.listConvos` | ✅ | |
| `convo.sendMessage` | ✅ | |
| `convo.acceptConvo` | ❌ | **MISSING** |
| `convo.addReaction` | ❌ | **MISSING** |
| `convo.deleteMessageForSelf` | ❌ | **MISSING** |
| `convo.getConvoAvailability` | ❌ | **MISSING** |
| `convo.getConvoForMembers` | ❌ | **MISSING** |
| `convo.leaveConvo` | ❌ | **MISSING** |
| `convo.listConvoRequests` | ❌ | **MISSING** |
| `convo.lockConvo` | ❌ | **MISSING** |
| `convo.muteConvo` | ❌ | **MISSING** |
| `convo.removeReaction` | ❌ | **MISSING** |
| `convo.sendMessageBatch` | ❌ | **MISSING** |
| `convo.unlockConvo` | ❌ | **MISSING** |
| `convo.unmuteConvo` | ❌ | **MISSING** |
| `convo.updateAllRead` | ❌ | **MISSING** |
| `convo.updateRead` | ❌ | **MISSING** |
| `group.*` | ❌ | All group endpoints **MISSING** |
| `moderation.*` | ❌ | All moderation endpoints **MISSING** |

**Chat Coverage: ~25%**

---

## tools.ozone.* (Ozone Moderation Service)

**NOT IMPLEMENTED** - Ozone API deferred

All 67 ozone endpoints are not implemented. These are moderation/trust/safety tools.

---

## Summary Table

| Namespace | Service | Coverage | Missing |
|-----------|---------|----------|---------|
| `com.atproto.server.*` | PDS | 100% | 0 |
| `com.atproto.repo.*` | PDS | 100% | 0 |
| `com.atproto.sync.*` | PDS/Relay | 93% | requestCrawl (relay-specific) |
| `com.atproto.identity.*` | PDS | 100% | 0 |
| `com.atproto.label.*` | PDS | 100% | 0 |
| `com.atproto.moderation.*` | PDS | 100% | 0 |
| `com.atproto.admin.*` | PDS | 100% | 0 (4 deprecated return 410) |
| `com.atproto.temp.*` | PDS | 100% | 0 |
| `com.atproto.lexicon.*` | PDS | 100% | 0 |
| `app.bsky.actor.*` | AppView | ~88% | status |
| `app.bsky.feed.*` | AppView | 100% | 0 |
| `app.bsky.graph.*` | AppView | ~85% | getListMutes, getListBlocks, getListsWithMembership |
| `app.bsky.notification.*` | AppView | 100% | 0 |
| `app.bsky.video.*` | AppView | 100% | 0 |
| `app.bsky.unspecced.*` | AppView | ~20% | 24 skeleton/experimental endpoints |
| `app.bsky.labeler.*` | AppView | 100% | 0 |
| `chat.bsky.convo.*` | ChatView | ~25% | 15 endpoints |
| `chat.bsky.group.*` | ChatView | 0% | 11 endpoints |
| `tools.ozone.*` | Ozone | 0% | 67 endpoints (deferred) |

## Priority Missing Endpoints

### High Priority (Core Functionality)

1. **app.bsky.graph.getListMutes** - List muted lists
2. **app.bsky.graph.getListBlocks** - List blocked lists  
3. **app.bsky.graph.getListsWithMembership** - Lists containing actor

### Medium Priority (Chat)

1. `chat.bsky.convo.*` batch operations
2. `chat.bsky.convo.*` reactions
3. `chat.bsky.group.*` group chat

### Low Priority (Skeleton/Unspecced)

These are internal/discovery endpoints mostly for Bluesky's own clients:
- `app.bsky.unspecced.*Skeleton` endpoints
- `app.bsky.unspecced.getTrends*`
- Age assurance endpoints

### Deferred

- `tools.ozone.*` - 67 endpoints, large scope moderation toolkit
