# Plan: Implement Missing XRPC Endpoints

**Created**: 2026-04-17
**Git Hash**: aa933f41
**Related**: `docs/xrpc-coverage-analysis-2026-04-17.md`

## Overview

This plan addresses the identified gaps in XRPC endpoint coverage across garazyk services. Priority is based on user-facing functionality impact.

## Phase 1: app.bsky.graph.* Missing Endpoints (HIGH PRIORITY)

These affect basic social graph functionality that users expect.

### 1.1 app.bsky.graph.getListMutes

**Purpose**: List lists that the authenticated user has muted.

**Location**: `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m`

**Implementation Steps**:

- [ ] **Step 1**: Add method registration in `XrpcAppBskyGraphPack.m`
  ```objc
  [dispatcher registerMethod:@"app.bsky.graph.getListMutes" handler:^(HttpRequest *request, HttpResponse *response) {
      // Handler implementation
  }];
  ```

- [ ] **Step 2**: Create database migration for list mute tracking
  - File: `Garazyk/Sources/Database/Migrations/`
  - Table: `list_mutes` (actor_did, list_uri, created_at)
  - Or reuse existing `mutes` table with type discriminator

- [ ] **Step 3**: Implement query logic
  - Parse `limit` and `cursor` query params
  - Query mutes table for list-type mutes
  - Join with lists to return `ListView` records
  - Implement cursor-based pagination

- [ ] **Step 4**: Implement response format per lexicon
  ```json
  {
    "cursor": "string?",
    "mutes": [{ "$type": "app.bsky.graph.defs#listView", ... }]
  }
  ```

- [ ] **Step 5**: Add auth check - requires authenticated user
  - Use `XrpcAuthHelper` to extract DID from token

- [ ] **Step 6**: Write integration test
  - File: `Garazyk/Tests/Integration/XrpcAppBskyGraphTests.m`
  - Test: authenticated request, pagination, empty results

**Lexicon Reference**: Check `lexicons/app/bsky/graph/getListMutes.json`

**WHY**: Users need to manage which lists they've muted. This is basic profile settings functionality.

---

### 1.2 app.bsky.graph.getListBlocks

**Purpose**: List lists that the authenticated user has blocked.

**Location**: `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m`

**Implementation Steps**:

- [ ] **Step 1**: Add method registration
  ```objc
  [dispatcher registerMethod:@"app.bsky.graph.getListBlocks" handler:^(HttpRequest *request, HttpResponse *response) {
      // Handler implementation
  }];
  ```

- [ ] **Step 2**: Create database migration for list block tracking
  - Table: `list_blocks` or extend `blocks` with type field
  - Fields: actor_did, list_uri, created_at

- [ ] **Step 3**: Implement query logic
  - Parse pagination params
  - Query blocks for list-type entries
  - Return `ListView` records

- [ ] **Step 4**: Implement response format
  ```json
  {
    "cursor": "string?",
    "blocks": [{ "$type": "app.bsky.graph.defs#listView", ... }]
  }
  ```

- [ ] **Step 5**: Add auth check

- [ ] **Step 6**: Write integration tests

**Lexicon Reference**: `lexicons/app/bsky/graph/getListBlocks.json`

**WHY**: List blocking is separate from list muting (blocks affect visibility in other contexts).

---

### 1.3 app.bsky.graph.getListsWithMembership

**Purpose**: List lists that an actor is a member of.

**Location**: `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m`

**Implementation Steps**:

- [ ] **Step 1**: Add method registration
  ```objc
  [dispatcher registerMethod:@"app.bsky.graph.getListsWithMembership" handler:^(HttpRequest *request, HttpResponse *response) {
      // Handler implementation
  }];
  ```

- [ ] **Step 2**: Parse query params
  - `actor`: DID or handle (required)
  - `limit`: int (default 50, max 100)
  - `cursor`: string?

- [ ] **Step 3**: Resolve actor identifier (DID or handle)

- [ ] **Step 4**: Query list items for actor membership
  - Query `list_items` table where `subject_did = actor`
  - Join with lists table for list metadata
  - Apply pagination

- [ ] **Step 5**: Implement response format
  ```json
  {
    "cursor": "string?",
    "lists": [{ "$type": "app.bsky.graph.defs#listView", ... }]
  }
  ```

- [ ] **Step 6**: Handle public vs private lists
  - Only return lists where actor has visibility
  - Consider list access controls if any

- [ ] **Step 7**: Write integration tests

**Lexicon Reference**: `lexicons/app/bsky/graph/getListsWithMembership.json`

**WHY**: Users want to see which lists they (or others) are members of. Common "show my lists" feature.

---

### 1.4 app.bsky.actor.status

**Purpose**: Get actor's status (online, birthday today, etc).

**Location**: `Garazyk/Sources/Network/XrpcAppBskyActorPack.m`

**Implementation Steps**:

- [ ] **Step 1**: Add method registration
  ```objc
  [dispatcher registerMethod:@"app.bsky.actor.status" handler:^(HttpRequest *request, HttpResponse *response) {
      // Handler implementation
  }];
  ```

- [ ] **Step 2**: Parse query params
  - `actor`: DID or handle (required)

- [ ] **Step 3**: Resolve actor

- [ ] **Step 4**: Query status data
  - This may be derived from presence/online tracking
  - Or from profile record extension

- [ ] **Step 5**: Implement response per lexicon
  ```json
  {
    "status": "live" | "none" | ...
  }
  ```

- [ ] **Step 6**: Write tests

**Lexicon Reference**: `lexicons/app/bsky/actor/status.json`

**WHY**: Shows user presence/status information in profiles.

---

## Phase 2: chat.bsky.convo.* Missing Endpoints (MEDIUM PRIORITY)

Chat functionality for DMs.

### 2.1 chat.bsky.convo.acceptConvo

**Purpose**: Accept a conversation request.

**Implementation Steps**:

- [ ] Add method registration in `XrpcChatBskyConvoPack.m`
- [ ] Parse params (convoId)
- [ ] Update convo status in database
- [ ] Notify other participants
- [ ] Return updated convo view

### 2.2 chat.bsky.convo.addReaction

**Purpose**: Add emoji reaction to message.

**Implementation Steps**:

- [ ] Add method registration
- [ ] Store reaction in database
- [ ] Emit event to other participants
- [ ] Return reaction record

### 2.3 chat.bsky.convo.deleteMessageForSelf

**Purpose**: Delete message locally (not for others).

**Implementation Steps**:

- [ ] Add method registration
- [ ] Mark message as deleted for requesting user
- [ ] Remove from their view only

### 2.4 chat.bsky.convo.getConvoAvailability

**Purpose**: Check if can start convo with actor.

**Implementation Steps**:

- [ ] Add method registration
- [ ] Check privacy settings, blocks, etc.
- [ ] Return availability status

### 2.5 chat.bsky.convo.getConvoForMembers

**Purpose**: Get/create convo for a set of members.

**Implementation Steps**:

- [ ] Add method registration
- [ ] Parse member DIDs
- [ ] Find or create convo
- [ ] Return convo view

### 2.6 chat.bsky.convo.leaveConvo

**Purpose**: Leave a conversation.

**Implementation Steps**:

- [ ] Add method registration
- [ ] Update member list
- [ ] Handle last member case

### 2.7 chat.bsky.convo.listConvoRequests

**Purpose**: List pending conversation requests.

**Implementation Steps**:

- [ ] Add method registration
- [ ] Query pending requests
- [ ] Return paginated list

### 2.8 chat.bsky.convo.lockConvo / unlockConvo

**Purpose**: Lock/unlock conversation (restrict to admins).

**Implementation Steps**:

- [ ] Add method registrations
- [ ] Update convo lock status
- [ ] Enforce in message sending

### 2.9 chat.bsky.convo.muteConvo / unmuteConvo

**Purpose**: Mute/unmute conversation notifications.

**Implementation Steps**:

- [ ] Add method registrations
- [ ] Store mute preference per user per convo

### 2.10 chat.bsky.convo.removeReaction

**Purpose**: Remove emoji reaction from message.

### 2.11 chat.bsky.convo.sendMessageBatch

**Purpose**: Send multiple messages in batch.

### 2.12 chat.bsky.convo.updateAllRead / updateRead

**Purpose**: Mark messages as read.

---

## Phase 3: chat.bsky.group.* (LOWER PRIORITY)

Group chat functionality - larger scope.

### Endpoints

- `createGroup`
- `editGroup`
- `addMembers`
- `removeMembers`
- `createJoinLink`
- `enableJoinLink`
- `disableJoinLink`
- `editJoinLink`
- `getGroupPublicInfo`
- `requestJoin`
- `approveJoinRequest`
- `rejectJoinRequest`
- `listJoinRequests`

**Note**: Groups require additional infrastructure for:
- Group identity/records
- Member management
- Invite links
- Join request workflow

---

## Phase 4: app.bsky.unspecced.* Skeleton Endpoints (LOW PRIORITY)

These are internal/discovery endpoints mostly for Bluesky's clients.

### Skeletal Query Endpoints

These return bare arrays for client-side hydration:

- `getSuggestedFeedsSkeleton`
- `getSuggestedUsersSkeleton`
- `getSuggestionsSkeleton`
- `searchActorsSkeleton`
- `searchPostsSkeleton`
- `searchStarterPacksSkeleton`
- `getTaggedSuggestions`

### Discovery Endpoints

- `getTrends`
- `getTrendsSkeleton`
- `getTrendingTopics`
- `getOnboardingSuggestedStarterPacks`
- `getOnboardingSuggestedStarterPacksSkeleton`
- `getOnboardingSuggestedUsersSkeleton`
- `getSuggestedOnboardingUsers`
- `getSuggestedStarterPacks`
- `getSuggestedStarterPacksSkeleton`
- `getSuggestedUsersForDiscover`
- `getSuggestedUsersForDiscoverSkeleton`
- `getSuggestedUsersForExplore`
- `getSuggestedUsersForExploreSkeleton`
- `getSuggestedUsersForSeeMore`
- `getSuggestedUsersForSeeMoreSkeleton`

### V2 Endpoints

- `getPostThreadV2`
- `getPostThreadOtherV2`

### Age Assurance

- `getAgeAssuranceState`
- `initAgeAssurance`

**WHY SKIPPED**: These require recommendation/trending algorithms and substantial infrastructure. Core functionality works without them.

---

## Phase 5: tools.ozone.* (DEFERRED)

Ozone is a comprehensive moderation toolkit with 67 endpoints.

### Categories

- `tools.ozone.moderation.*` - 16 endpoints
- `tools.ozone.communication.*` - 5 endpoints
- `tools.ozone.set.*` - 6 endpoints
- `tools.ozone.signature.*` - 3 endpoints
- `tools.ozone.team.*` - 4 endpoints
- `tools.ozone.verification.*` - 3 endpoints
- `tools.ozone.safelink.*` - 5 endpoints
- `tools.ozone.hosting.*` - 1 endpoint
- `tools.ozone.setting.*` - 3 endpoints
- `tools.ozone.server.*` - 1 endpoint

**DEFERRAL REASON**: Large scope (67 endpoints), requires:
- Moderation event system
- Action scheduling
- Template management
- Team management
- Signature correlation
- Verification issuance

Implementable in future when moderation workflows are needed.

---

## Implementation Order

### Sprint 1: Graph Essentials (Phase 1)
1. `app.bsky.graph.getListMutes`
2. `app.bsky.graph.getListBlocks`
3. `app.bsky.graph.getListsWithMembership`
4. `app.bsky.actor.status`

### Sprint 2: Chat Core (Phase 2 priority items)
1. `chat.bsky.convo.acceptConvo`
2. `chat.bsky.convo.getConvoAvailability`
3. `chat.bsky.convo.getConvoForMembers`
4. `chat.bsky.convo.leaveConvo`
5. `chat.bsky.convo.listConvoRequests`

### Sprint 3: Chat Features (Phase 2 remaining)
1. Reactions (addReaction, removeReaction)
2. Read status (updateRead, updateAllRead)
3. Muting (muteConvo, unmuteConvo)
4. Locking (lockConvo, unlockConvo)
5. Batch ops (sendMessageBatch)
6. Self-delete (deleteMessageForSelf)

### Sprint 4: Groups (Phase 3)
- Full group implementation

### Future
- Ozone (Phase 5)
- Skeleton/unspecced (Phase 4)

---

## Files to Create/Modify

### New Files
- `Garazyk/Sources/Database/Migrations/XXX_add_list_mutes.sql`
- `Garazyk/Sources/Database/Migrations/XXX_add_list_blocks.sql`
- `Garazyk/Tests/Integration/XrpcAppBskyGraphListTests.m`

### Modified Files
- `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m` - Add 3 endpoints
- `Garazyk/Sources/Network/XrpcAppBskyActorPack.m` - Add status endpoint
- `Garazyk/Sources/Network/XrpcChatBskyConvoPack.m` - Add ~15 endpoints

---

## Testing Strategy

For each endpoint:

1. **Unit tests**: Mock database, test handler logic
2. **Integration tests**: Real database, test full flow
3. **E2E tests**: With actual client (Bluesky app or custom client)
4. **Lexicon validation**: Verify request/response against lexicon schema

---

## Reference Implementation

Clone and compare:
```bash
git clone https://github.com/bluesky-social/atproto.git reference/atproto
```

Key files to reference:
- `packages/pds/src/api/app-bsky/` - AppView handlers
- `packages/pds/src/api/chat-bsky/` - Chat handlers
- `lexicons/app/bsky/` - Lexicon definitions
