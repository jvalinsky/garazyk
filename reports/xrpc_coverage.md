# XRPC Coverage Report

Generated: 2026-02-13T13:33:13.749Z

## Summary

- Implemented methods (unique, excluding `unknown`): 109
- Lexicon XRPC methods (unique, all scopes): 331
- Lexicon XRPC methods (in scope): 96
- Implemented and in lexicons (in scope): 96
- Missing in code (in scope): 0
- Implemented but missing lexicon (in scope): 0
- Coverage (in scope, implemented / lexicon): 100%
- Missing in code (out of scope): 223
- Unknown registry entries: 0
- Duplicate registry registrations: 0
- Duplicate registry registrations (cross-scope, actionable): 0
- Cross-scope overlap (expected controller/application dual-path): 0
- Cross-scope overlap (raw total): 0

## Namespace Coverage

| Namespace | Lexicon | Implemented | In Both | Coverage | Missing In Code |
|---|---:|---:|---:|---:|---:|
| com.atproto | 96 | 96 | 96 | 100% | 0 |

## Missing In Code (Top 60, In Scope)


## Missing In Code (Top 40, Out Of Scope)

- `app.bsky.actor.getSuggestions`
- `app.bsky.ageassurance.begin`
- `app.bsky.ageassurance.getConfig`
- `app.bsky.ageassurance.getState`
- `app.bsky.bookmark.createBookmark`
- `app.bsky.bookmark.deleteBookmark`
- `app.bsky.bookmark.getBookmarks`
- `app.bsky.contact.dismissMatch`
- `app.bsky.contact.getMatches`
- `app.bsky.contact.getSyncStatus`
- `app.bsky.contact.importContacts`
- `app.bsky.contact.removeData`
- `app.bsky.contact.sendNotification`
- `app.bsky.contact.startPhoneVerification`
- `app.bsky.contact.verifyPhone`
- `app.bsky.feed.describeFeedGenerator`
- `app.bsky.feed.getActorFeeds`
- `app.bsky.feed.getFeedGenerator`
- `app.bsky.feed.getFeedGenerators`
- `app.bsky.feed.getFeedSkeleton`
- `app.bsky.feed.getLikes`
- `app.bsky.feed.getListFeed`
- `app.bsky.feed.getPosts`
- `app.bsky.feed.getQuotes`
- `app.bsky.feed.getRepostedBy`
- `app.bsky.feed.getSuggestedFeeds`
- `app.bsky.feed.searchPosts`
- `app.bsky.feed.sendInteractions`
- `app.bsky.graph.getActorStarterPacks`
- `app.bsky.graph.getBlocks`
- `app.bsky.graph.getFollowers`
- `app.bsky.graph.getFollows`
- `app.bsky.graph.getKnownFollowers`
- `app.bsky.graph.getList`
- `app.bsky.graph.getListBlocks`
- `app.bsky.graph.getListMutes`
- `app.bsky.graph.getLists`
- `app.bsky.graph.getListsWithMembership`
- `app.bsky.graph.getMutes`
- `app.bsky.graph.getRelationships`

## Implemented But Missing Lexicon


## Scope

- Scope config source: `/Users/jack/Software/objpds/scripts/xrpc_coverage_scope.txt`
- Include globs: `com.atproto.*`
- Exclude globs: (none)

## Stub Scan

- `not_implemented` hits: 0
- `todo_fixme` hits: 0
- `stub_markers` hits: 0
- XRPC-related stub markers: 0

## Inputs

- Input mode: `source-parsed`
- `/Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
- `/Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcHandler.m`
- `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons`
- `/Users/jack/Software/objpds/reports/stub_scan_raw/stubs.json`

## Registration Scope Duplicates

### static.registerTempUtilityMethods

- Duplicate registrations: 0
- Unknown registrations: 0

### static.registerAdminAccountMaintenanceMethods

- Duplicate registrations: 0
- Unknown registrations: 0

### static.registerPhase1IdentityAndAccountMethods

- Duplicate registrations: 0
- Unknown registrations: 0

### class.registerMethodsWithDispatcher:controller

- Duplicate registrations: 0
- Unknown registrations: 0

### class.registerMethodsWithDispatcher:application

- Duplicate registrations: 0
- Unknown registrations: 0

## Cross-Scope Duplicate Methods (Actionable)

- none

## Cross-Scope Overlap (Expected)

- Methods overlapping between controller/application registrations: 0

