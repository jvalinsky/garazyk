# XRPC Next Steps Plan

Generated: 2026-02-12T07:13:23.738Z

## Baseline

- Missing in code: 268
- Coverage: 16.51%
- Unknown registry entries: 2
- Duplicate registry registrations: 31

## Priority Rubric

- P0: Critical PDS identity/account/repo/sync gaps with security or federation impact.
- P1: High-value protocol completeness for core `com.atproto.*` flows.
- P2: Admin/label/temp and useful adjacent functionality.
- P3: Non-core namespaces for appview/chat/custom extensions.

## Phased Queue

### Phase 1: Identity and Account Safety

- Endpoint count: 14
- P0: 10, P1: 4, P2: 0, P3: 0
- Next batch:
  - P0 `com.atproto.identity.requestPlcOperationSignature`
  - P0 `com.atproto.identity.signPlcOperation`
  - P0 `com.atproto.identity.submitPlcOperation`
  - P0 `com.atproto.identity.updateHandle`
  - P0 `com.atproto.server.confirmEmail`
  - P0 `com.atproto.server.requestAccountDelete`
  - P0 `com.atproto.server.requestPasswordReset`
  - P0 `com.atproto.server.reserveSigningKey`
  - P0 `com.atproto.server.resetPassword`
  - P0 `com.atproto.server.updateEmail`
  - P1 `com.atproto.server.getAccountInviteCodes`
  - P1 `com.atproto.identity.refreshIdentity`

### Phase 2: Repository and Sync Completeness

- Endpoint count: 9
- P0: 5, P1: 4, P2: 0, P3: 0
- Next batch:
  - P0 `com.atproto.repo.listMissingBlobs`
  - P0 `com.atproto.sync.getRepoStatus`
  - P0 `com.atproto.sync.listReposByCollection`
  - P0 `com.atproto.repo.importRepo`
  - P0 `com.atproto.sync.requestCrawl`
  - P1 `com.atproto.sync.getCheckout`
  - P1 `com.atproto.sync.getHostStatus`
  - P1 `com.atproto.sync.listHosts`
  - P1 `com.atproto.sync.listRepos`

### Phase 3: Admin, Label, and Temp APIs

- Endpoint count: 21
- P0: 0, P1: 1, P2: 20, P3: 0
- Next batch:
  - P1 `com.atproto.label.subscribeLabels`
  - P2 `com.atproto.temp.revokeAccountCredentials`
  - P2 `com.atproto.admin.getAccountInfo`
  - P2 `com.atproto.admin.getAccountInfos`
  - P2 `com.atproto.admin.getInviteCodes`
  - P2 `com.atproto.admin.deleteAccount`
  - P2 `com.atproto.admin.disableAccountInvites`
  - P2 `com.atproto.admin.disableInviteCodes`
  - P2 `com.atproto.admin.enableAccountInvites`
  - P2 `com.atproto.admin.searchAccounts`
  - P2 `com.atproto.admin.sendEmail`
  - P2 `com.atproto.admin.updateAccountEmail`

### Phase 4: Non-core Namespaces

- Endpoint count: 224
- P0: 0, P1: 0, P2: 0, P3: 224
- Next batch:
  - P3 `app.bsky.actor.getSuggestions`
  - P3 `app.bsky.ageassurance.getConfig`
  - P3 `app.bsky.ageassurance.getState`
  - P3 `app.bsky.bookmark.getBookmarks`
  - P3 `app.bsky.contact.getMatches`
  - P3 `app.bsky.contact.getSyncStatus`
  - P3 `app.bsky.feed.getActorFeeds`
  - P3 `app.bsky.feed.getFeedGenerator`
  - P3 `app.bsky.feed.getFeedGenerators`
  - P3 `app.bsky.feed.getFeedSkeleton`
  - P3 `app.bsky.feed.getLikes`
  - P3 `app.bsky.feed.getListFeed`

## Recommended Work Order

1. Implement all Phase 1 P0/P1 endpoints.
2. Implement Phase 2 P0/P1 endpoints, then run interop/sync tests.
3. Implement Phase 3 P1/P2 endpoints needed for moderation/admin workflows.
4. Re-run `scripts/generate_xrpc_coverage_report.js` after each batch.

