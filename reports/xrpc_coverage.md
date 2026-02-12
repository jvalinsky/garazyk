# XRPC Coverage Report

Generated: 2026-02-12T13:11:57.268Z

## Summary

- Implemented methods (unique, excluding `unknown`): 86
- Lexicon XRPC methods (unique): 321
- Implemented and in lexicons: 77
- Missing in code: 244
- Implemented but missing lexicon: 9
- Overall coverage (implemented / lexicon): 23.99%
- Unknown registry entries: 2
- Duplicate registry registrations: 41

## Namespace Coverage

| Namespace | Lexicon | Implemented | In Both | Coverage | Missing In Code |
|---|---:|---:|---:|---:|---:|
| app.bsky | 98 | 13 | 12 | 12.24% | 86 |
| tools.ozone | 45 | 0 | 0 | 0% | 45 |
| social.grain | 31 | 0 | 0 | 0% | 31 |
| place.stream | 27 | 0 | 0 | 0% | 27 |
| chat.bsky | 22 | 0 | 0 | 0% | 22 |
| com.atproto | 86 | 73 | 65 | 75.58% | 21 |
| com.shinolabs | 8 | 0 | 0 | 0% | 8 |
| com.whtwnd | 4 | 0 | 0 | 0% | 4 |

## Missing In Code (Top 60)

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
- `app.bsky.graph.getStarterPack`
- `app.bsky.graph.getStarterPacks`
- `app.bsky.graph.getStarterPacksWithMembership`
- `app.bsky.graph.getSuggestedFollowsByActor`
- `app.bsky.graph.muteActor`
- `app.bsky.graph.muteActorList`
- `app.bsky.graph.muteThread`
- `app.bsky.graph.searchStarterPacks`
- `app.bsky.graph.unmuteActor`
- `app.bsky.graph.unmuteActorList`
- `app.bsky.graph.unmuteThread`
- `app.bsky.labeler.getServices`
- `app.bsky.notification.getPreferences`
- `app.bsky.notification.getUnreadCount`
- `app.bsky.notification.listActivitySubscriptions`
- `app.bsky.notification.listNotifications`
- `app.bsky.notification.putActivitySubscription`
- `app.bsky.notification.putPreferences`
- `app.bsky.notification.putPreferencesV2`
- `app.bsky.notification.unregisterPush`

## Implemented But Missing Lexicon

- `app.bsky.user.getUserStats`
- `com.atproto.admin.moderateAccount`
- `com.atproto.admin.moderateRecord`
- `com.atproto.label.createLabel`
- `com.atproto.label.getLabels`
- `com.atproto.repo.deleteBlob`
- `com.atproto.repo.getBlob`
- `com.atproto.repo.updateRecord`
- `com.atproto.server.getAccount`

## Stub Scan

- `not_implemented` hits: 0
- `todo_fixme` hits: 0
- `stub_markers` hits: 0
- XRPC-related stub markers: 0

## Inputs

- `reports/xrpc_sync_raw/methods.tsv`
- `reports/xrpc_sync_raw/lexicons.tsv`
- `reports/xrpc_sync_raw/diff.json`
- `reports/stub_scan_raw/stubs.json`

