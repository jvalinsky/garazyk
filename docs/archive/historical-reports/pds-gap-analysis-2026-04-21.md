# PDS (kaszlak) XRPC Endpoint Gap Analysis

**Date**: 2026-04-21
**Compared against**: bluesky-social/atproto lexicon definitions (main branch)
**Reference**: bluesky-social/indigo (Go), bluesky-social/atproto/packages/pds (TypeScript)

## Summary

| Namespace | Spec Endpoints | Implemented | Missing | Coverage |
|-----------|---------------|-------------|---------|----------|
| com.atproto.server | 25 | 25 | 0 | **100%** |
| com.atproto.repo | 11 | 12 | 0 | **100%** (+1 non-standard) |
| com.atproto.sync | 16 | 16 | 0 | **100%** |
| com.atproto.identity | 9 | 9 | 0 | **100%** |
| com.atproto.label | 2 | 4 | 0 | **100%** (+2 non-standard) |
| com.atproto.moderation | 1 | 1 | 0 | **100%** |
| com.atproto.admin | 15 | 17 | 0 | **100%** (+2 deprecated + non-standard) |
| com.atproto.temp | 7 | 7 | 0 | **100%** |
| com.atproto.lexicon | 1 | 1 | 0 | **100%** |
| **app.bsky.actor** | **7** | **1** | **6** | **14%** |
| **app.bsky.feed** | **17** | **11** | **6** | **65%** |
| **app.bsky.graph** | **25** | **20** | **5** | **80%** |
| **app.bsky.notification** | **11** | **9** | **2** | **82%** |
| **app.bsky.labeler** | **1** | **1** | **0** | **100%** |
| **app.bsky.video** | **3** | **3** | **0** | **100%** |
| **app.bsky.bookmark** | **3** | **3** | **0** | **100%** |
| **app.bsky.draft** | **4** | **4** | **0** | **100%** |
| **app.bsky.unspecced** | **28** | **28** | **0** | **100%** |
| **app.bsky.ageassurance** | **3** | **0** | **3** | **0%** |
| **app.bsky.contact** | **8** | **0** | **8** | **0%** |
| **chat.bsky.convo** | **21** | **19** | **2** | **90%** |
| **chat.bsky.group** | **13** | **13** | **0** | **100%** |
| **chat.bsky.actor** | **2** | **0** | **2** | **0%** |
| **chat.bsky.moderation** | **4** | **0** | **4** | **0%** |
| tools.ozone.moderation | 15 | 15 | 0 | **100%** |
| tools.ozone.team | 4 | 4 | 0 | **100%** |
| **tools.ozone.set** | **6** | **1** | **5** | **17%** |
| tools.ozone.communication | 4 | 4 | 0 | **100%** |
| tools.ozone.hosting | 1 | 1 | 0 | **100%** |
| tools.ozone.server | 1 | 2 | 0 | **100%** (+1 non-standard) |
| tools.ozone.signature | 3 | 3 | 0 | **100%** |
| tools.ozone.safelink | 5 | 5 | 0 | **100%** |
| tools.ozone.setting | 3 | 3 | 0 | **100%** |
| **tools.ozone.verification** | **3** | **3** | **0** | **100%** (naming mismatch) |
| tools.ozone.report | 0 | 0 | 0 | N/A |

**Total**: ~252 spec endpoints, ~228 implemented, **~24 missing** + **5 naming mismatches**

---

## Critical Gaps (PDS Core Functionality)

### app.bsky.actor (6 missing) — CRITICAL

These are fundamental AppView endpoints that every client needs:

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `getProfile` | Get a user's profile | **P0** - Used by every client |
| `getProfiles` | Batch get profiles | **P0** - Used by every client |
| `searchActors` | Search for users | **P1** - Core discovery |
| `searchActorsTypeahead` | Typeahead search | **P1** - Search autocomplete |
| `getPreferences` | Get user preferences | **P1** - Settings/feeds |
| `putPreferences` | Update user preferences | **P1** - Settings/feeds |

Note: `app.bsky.actor.status` is a record type, NOT an endpoint.

### app.bsky.feed (6 missing) — CRITICAL

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `getTimeline` | Home timeline | **P0** - Primary user experience |
| `getAuthorFeed` | User's posts feed | **P0** - Profile page |
| `getPostThread` | Thread view | **P0** - Post detail view |
| `getPosts` | Batch get posts by URI | **P0** - Used everywhere |
| `getFeed` | Get feed with hydration | **P1** - Custom feeds |
| `getFeedGenerators` | Batch get feed generators | **P2** - Feed discovery |
| `getActorLikes` | User's liked posts | **P2** - Profile tab |

### app.bsky.graph (5 missing) — HIGH

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `getBlocks` | List blocked users | **P1** - Settings page |
| `getMutes` | List muted users | **P1** - Settings page |
| `getStarterPack` | Get single starter pack | **P2** - Starter pack view |
| `getStarterPacks` | Batch get starter packs | **P2** - Starter pack views |
| `getActorStarterPacks` | User's starter packs | **P2** - Profile page |

---

## Moderate Gaps (Secondary Functionality)

### app.bsky.notification (2 missing) — MODERATE

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `registerPush` | Register for push notifications | **P2** - Mobile notifications |
| `unregisterPush` | Unregister push notifications | **P2** - Mobile notifications |

### chat.bsky.convo (2 missing) — MODERATE

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `getConvoMembers` | Get conversation members | **P1** - Chat UI |
| `getLog` | Get conversation event log | **P2** - Chat sync |

---

## Low Priority Gaps (New/Experimental Features)

### app.bsky.ageassurance (3 missing) — LOW

New namespace for age verification. We have `unspecced.initAgeAssurance` and `unspecced.getAgeAssuranceState` which may overlap.

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `begin` | Begin age assurance flow | **P3** - New feature |
| `getConfig` | Get age assurance config | **P3** - New feature |
| `getState` | Get current age assurance state | **P3** - New feature |

### app.bsky.contact (8 missing) — LOW

New namespace for contact sync. Likely needs mobile app integration.

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `importContacts` | Import phone contacts | **P3** - New feature |
| `getMatches` | Get contact matches | **P3** - New feature |
| `dismissMatch` | Dismiss a contact match | **P3** - New feature |
| `getSyncStatus` | Get contact sync status | **P3** - New feature |
| `removeData` | Remove contact data | **P3** - New feature |
| `sendNotification` | Send contact notification | **P3** - New feature |
| `startPhoneVerification` | Start phone verification | **P3** - New feature |
| `verifyPhone` | Verify phone number | **P3** - New feature |

### chat.bsky.actor (2 missing) — LOW

Note: `declaration` is a record type, NOT an endpoint.

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `deleteAccount` | Delete chat account | **P3** - Chat management |
| `exportAccountData` | Export chat data | **P3** - Data portability |

### chat.bsky.moderation (4 missing) — LOW

| Missing Endpoint | Purpose | Priority |
|-----------------|---------|----------|
| `getActorMetadata` | Get chat actor metadata | **P3** - Chat moderation |
| `getMessageContext` | Get message context | **P3** - Chat moderation |
| `subscribeModEvents` | Subscribe to mod events | **P3** - Chat moderation |
| `updateActorAccess` | Update chat access | **P3** - Chat moderation |

---

## Naming Mismatches (Spec Non-Compliance)

These endpoints exist but use wrong NSID names. Clients using the official SDK will fail to find them.

### tools.ozone.set — 5 naming mismatches

| Our NSID | Correct Spec NSID | Issue |
|----------|------------------|-------|
| `tools.ozone.set.create` | `tools.ozone.set.upsertSet` | Wrong name |
| `tools.ozone.set.delete` | `tools.ozone.set.deleteSet` | Wrong name |
| `tools.ozone.set.get` | `tools.ozone.set.getValues` | Wrong name |
| `tools.ozone.set.list` | `tools.ozone.set.querySets` | Wrong name |
| `tools.ozone.set.update` | *(no spec equivalent)* | Non-standard |
| *(missing)* | `tools.ozone.set.deleteValues` | Not implemented |

### tools.ozone.verification — 2 naming mismatches

| Our NSID | Correct Spec NSID | Issue |
|----------|------------------|-------|
| `tools.ozone.verification.grantVerification` | `tools.ozone.verification.grantVerifications` | Singular vs plural |
| `tools.ozone.verification.revokeVerification` | `tools.ozone.verification.revokeVerifications` | Singular vs plural |

### tools.ozone.moderation — 1 naming mismatch

| Our NSID | Correct Spec NSID | Issue |
|----------|------------------|-------|
| `tools.ozone.moderation.cancelScheduledAction` | `tools.ozone.moderation.cancelScheduledActions` | Singular vs plural |

### tools.ozone.moderation — 1 missing endpoint

| Missing NSID | Description |
|-------------|-------------|
| `tools.ozone.moderation.getSubjects` | Batch get subject statuses (different from `getSubjectStatus`) |

---

## Not Endpoints (Record Types / Permission Sets)

These lexicon definitions are NOT XRPC query/procedure endpoints:

- `app.bsky.actor.status` — Record type (status declaration)
- `app.bsky.auth*` (9 items) — OAuth permission-set definitions, not endpoints
- `chat.bsky.actor.declaration` — Record type (chat preferences)
- `app.bsky.feed.post`, `.like`, `.repost`, `.generator`, `.postgate`, `.threadgate` — Record types
- `app.bsky.graph.follow`, `.block`, `.list`, `.listitem`, `.listblock`, `.starterpack`, `.verification` — Record types
- `app.bsky.labeler.service` — Record type
- `app.bsky.notification.declaration` — Record type
- `app.bsky.richtext.*` — Facet definitions
- `app.bsky.embed.*` — Embed record types
- `com.atproto.repo.strongRef` — Record type
- `com.atproto.sync.defs` — Type definitions

---

## Implementation Priority Order

### Phase 1: P0 — Client-breaking gaps (17 endpoints)

These are needed for any atproto client (Bluesky app, etc.) to function:

1. `app.bsky.actor.getProfile`
2. `app.bsky.actor.getProfiles`
3. `app.bsky.feed.getTimeline`
4. `app.bsky.feed.getAuthorFeed`
5. `app.bsky.feed.getPostThread`
6. `app.bsky.feed.getPosts`
7. `app.bsky.actor.searchActors`
8. `app.bsky.actor.searchActorsTypeahead`
9. `app.bsky.actor.getPreferences`
10. `app.bsky.actor.putPreferences`
11. `app.bsky.feed.getFeed`
12. `app.bsky.feed.getFeedGenerators`
13. `app.bsky.feed.getActorLikes`
14. `app.bsky.graph.getBlocks`
15. `app.bsky.graph.getMutes`
16. `chat.bsky.convo.getConvoMembers`
17. `chat.bsky.convo.getLog`

### Phase 2: P1 — Naming mismatches (8 fixes)

Fix spec compliance for existing implementations:

1. Rename `tools.ozone.set.create` → `upsertSet`
2. Rename `tools.ozone.set.delete` → `deleteSet`
3. Rename `tools.ozone.set.get` → `getValues`
4. Rename `tools.ozone.set.list` → `querySets`
5. Add `tools.ozone.set.deleteValues`
6. Remove `tools.ozone.set.update` (non-standard)
7. Rename `grantVerification` → `grantVerifications`, `revokeVerification` → `revokeVerifications`
8. Rename `cancelScheduledAction` → `cancelScheduledActions`

### Phase 3: P2 — Secondary features (7 endpoints)

1. `app.bsky.graph.getStarterPack`
2. `app.bsky.graph.getStarterPacks`
3. `app.bsky.graph.getActorStarterPacks`
4. `app.bsky.notification.registerPush`
5. `app.bsky.notification.unregisterPush`
6. `tools.ozone.moderation.getSubjects`

### Phase 4: P3 — New/experimental features (17 endpoints)

1. `app.bsky.ageassurance.*` (3 endpoints)
2. `app.bsky.contact.*` (8 endpoints)
3. `chat.bsky.actor.*` (2 endpoints)
4. `chat.bsky.moderation.*` (4 endpoints)

---

## Com.atproto.* Coverage — 100% Complete

All core AT Protocol endpoints are implemented:

- **com.atproto.server**: 25/25 (createAccount, createSession, etc.)
- **com.atproto.repo**: 12/11 (+updateRecord non-standard)
- **com.atproto.sync**: 16/16 (all PDS + relay endpoints)
- **com.atproto.identity**: 9/9 (handle/DID operations)
- **com.atproto.label**: 4/2 (+createLabel, getLabels non-standard)
- **com.atproto.moderation**: 1/1 (createReport)
- **com.atproto.admin**: 17/15 (+deprecated getAccountTakedown, moderateAccount/Record + getModerationReports, resolveReport non-standard)
- **com.atproto.temp**: 7/7 (all temporary endpoints)
- **com.atproto.lexicon**: 1/1 (resolveLexicon)
