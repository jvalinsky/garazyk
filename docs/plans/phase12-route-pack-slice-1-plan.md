# Phase 12, Slice 1: Route Pack Decomposition

## Status: in progress — Steps 1–2 landed (`c85b1bed8`, `72a059eae`); Steps 3–4 remain

## Summary

Split the four XRPC route-pack god files into Objective-C category files by
functional area, behind characterization tests. This is the first slice
of Phase 12 (mega-plan Phase 4 item 3 / workstream 02 A3).

## Files and current sizes

| File | Lines | Namespace(s) | Seams |
|------|-------|-------------|-------|
| `XrpcServerPack.m` | 1446 → 410 | `com.atproto.server.*` | describeServer, session, inviteCodes, appPasswords, accountManagement, accountLifecycle, health |
| `XrpcAdminPack.m` | 1672 → 496 | `com.atproto.admin.*` | accountLookup/search/email, serverStats/audit/repair, accountInfo/invites/subjectStatus, accountLifecycle/records/takedown, moderation (deprecated) |
| `XrpcRepoPack.m` | 1748 | `com.atproto.repo.*` | validation helpers (PDSRepoImportValidationResult, PDSRepoImportValidator), route registration |
| `AppViewXRpcRoutePack.m` | 2019 | `app.bsky.*`, `com.atproto.*` | actor, feed, graph, notification, identity/repo/moderation, ageAssurance, drafts, bookmarks, contact, searchSkeleton |

All files in `Garazyk/Sources/Network/`.

## Pattern

The codebase already uses Objective-C categories for decomposition
(`PDSDatabase+Accounts.m`, `PDSDatabase+Blocks.m`,
`PDSActorStore+Account.m`, `NSDateFormatter+ATProto.m`). GNUstep
category loading is proven by these existing categories passing
AllTests on Linux Docker.

The existing split route packs (`XrpcAppBskyActorPack`,
`XrpcAppBskyFeedPack`, `XrpcAppBskyGraphPack`, etc.) are separate
classes conforming to `XrpcRoutePack` — one per NSID namespace. The
four god files are each a single class in a single namespace (except
`AppViewXRpcRoutePack` which spans multiple), so category
decomposition is the right tool, not class splitting.

## Order (lowest risk first)

### Step 1: Pilot — `XrpcServerPack.m` (1446 lines) ✅ DONE

Committed as `c85b1bed8`. Split into categories by `#pragma mark` sections:

| Category file | Routes moved |
|---------------|--------------|
| `XrpcServerPack+Describe.m` | `describeServer` |
| `XrpcServerPack+Session.m` | `createAccount`, `createSession`, `getSession`, `refreshSession`, `deleteSession` |
| `XrpcServerPack+InviteCodes.m` | `createInviteCode`, `createInviteCodes`, `getAccountInviteCodes` |
| `XrpcServerPack+AppPasswords.m` | `createAppPassword`, `listAppPasswords`, `revokeAppPassword` |
| `XrpcServerPack+AccountManagement.m` | `requestEmailConfirmation`, `requestEmailUpdate`, `confirmEmail`, `updateEmail`, `requestAccountDelete`, `requestPasswordReset`, `resetPassword`, `reserveSigningKey`, `getServiceAuth` |
| `XrpcServerPack+AccountLifecycle.m` | `getAccount`, `deleteAccount`, `checkAccountStatus`, `activateAccount`, `deactivateAccount` |
| `XrpcServerPack+Health.m` | health endpoint |

The main `XrpcServerPack.m` keeps: `routePackIdentifier`, `registerWithDispatcher:services:`, helper functions, and the `+register*WithDispatcher:` orchestration methods.

A shared internal header `XrpcServerPack_Internal.h` exposes helper functions shared by categories.

### Step 2: `XrpcAdminPack.m` (1672 → 496 lines) ✅ DONE

Committed as `72a059eae`. Split by `#pragma mark` sections, one `.h`/`.m`
pair per category plus `XrpcAdminPack_Internal.h` for shared helpers:

| Category file | Routes moved |
|---------------|--------------|
| `XrpcAdminPack+AccountLookup.m` | `searchAccounts`, `sendEmail`, `updateAccountEmail`, `updateAccountHandle`, `updateAccountPassword` |
| `XrpcAdminPack+ServerStats.m` | `getServerStats`, `queryAuditLog`, `repairRepo`, `runBlobAudit`, `getBlobAuditStatus` |
| `XrpcAdminPack+AccountInfo.m` | `getAccountUsage`, `getAccountInfo`, `getAccountInfos`, `getInviteCodes`, `disableAccountInvites`, `enableAccountInvites` |
| `XrpcAdminPack+Lifecycle.m` | `updateSubjectStatus`, `getRecord`, `getSubjectStatus`, `getAccountTakedown`, `deleteAccount`, `disableInviteCodes`, `updateAccountSigningKey` |
| `XrpcAdminPack+Moderation.m` | `moderateAccount`, `moderateRecord`, `takeDownAccount`, `getModerationReports`, `resolveReport` |

The main `XrpcAdminPack.m` keeps: `routePackIdentifier`, `registerWithDispatcher:services:`, helper functions. An `XrpcAdminPack_Internal.h` exposes shared helpers.

### Step 3: `XrpcRepoPack.m` (1748 lines)

**Structural caution**: unlike ServerPack/AdminPack, RepoPack registers all
12 routes inline as blocks inside a single ~1030-line
`+registerWithDispatcher:services:` (line 716 to EOF). There are no
per-route methods to move. The split therefore extracts per-area
`+register<Area>RoutesWithDispatcher:services:` class methods, each
implemented in its category file, with the main
`+registerWithDispatcher:services:` reduced to orchestration calls —
the same shape ServerPack ended with. The `upsertRecordHandler` block is
shared by the `putRecord` and `updateRecord` registrations; both live in
`+Records`, so it stays a local block there.

Two-phase decomposition:

**Phase A**: Extract validation helpers to their own files:
- `PDSRepoImportValidationResult.h/.m` — the result class
- `PDSRepoImportValidator.h/.m` — the validator class

Both classes are currently file-private (`@interface` in the `.m`,
lines 397–710). Their new headers stay internal — do not add them to any
public umbrella header. Note `PDSRepoImportValidator` has two
`+validateCARData:` overload variants (lines 406 and 647); keep both
together in the extracted class.

**Phase B**: Add `XrpcRepoPack_Internal.h` for the shared helper
functions (`#pragma mark - Helpers`, lines 87–395), then
category-decompose the route registration:

| Category file | Routes moved |
|---------------|--------------|
| `XrpcRepoPack+Records.m` | `listRecords`, `getRecord`, `createRecord`, `deleteRecord`, `putRecord`, `updateRecord`, `applyWrites` |
| `XrpcRepoPack+Blobs.m` | `uploadBlob`, `listMissingBlobs`, `getBlob`, `deleteBlob` |
| `XrpcRepoPack+Import.m` | `importRepo` |
| `XrpcRepoPack+Describe.m` | `describeRepo` |

### Step 4: `AppViewXRpcRoutePack.m` (2019 lines)

Instance-based class with injected services. Split by namespace area:

| Category file | Handlers moved |
|---------------|----------------|
| `AppViewXRpcRoutePack+Actor.m` | `handleGetProfile`, `handleGetProfiles`, `handleSearchActors`, `handleSearchActorsTypeahead`, `handleGetPreferences`, `handlePutPreferences`, `handleGetSuggestions` |
| `AppViewXRpcRoutePack+Feed.m` | `handleGetTimeline`, `handleGetAuthorFeed`, `handleGetPostThread`, `handleGetFeed`, `handleGetActorLikes`, `handleGetPosts`, `handleGetFeedGenerators`, `handleGetLikes`, `handleGetRepostedBy` |
| `AppViewXRpcRoutePack+Graph.m` | `handleGetFollows`, `handleGetFollowers`, `handleGetBlocks`, `handleGetMutes`, `handleGetRelationships`, `handleGetStarterPack`, `handleGetStarterPacks`, `handleGetLists`, `handleGetList`, `handleMuteActor`, `handleUnmuteActor`, `handleGetStarterPacksBulk` |
| `AppViewXRpcRoutePack+Notification.m` | `handleListNotifications`, `handleGetUnreadCount`, `handleUpdateSeen`, `handleRegisterPush`, `handleUnregisterPush`, `handleListActivitySubscriptions`, `handlePutActivitySubscription`, `handleGetNotificationPreferences`, `handlePutNotificationPreferences` |
| `AppViewXRpcRoutePack+Identity.m` | `handleResolveHandle`, `handleGetRecord`, `handleQueryLabels`, `handleGetAccountInfos`, `handleGetSubjectStatus`, `handleProxyWrite:response:nsid:` |
| `AppViewXRpcRoutePack+AgeAssurance.m` | `handleAgeAssuranceBegin`, `handleAgeAssuranceGetConfig`, `handleAgeAssuranceGetState` |
| `AppViewXRpcRoutePack+Contact.m` | `handleStartPhoneVerification`, `handleVerifyPhone`, `handleImportContacts`, `handleGetContactMatches`, `handleDismissContactMatch`, `handleGetContactSyncStatus`, `handleRemoveContactData` |
| `AppViewXRpcRoutePack+Search.m` | `handleSearchActorsSkeleton`, `handleSearchPostsSkeleton`, `handleSearchStarterPacksSkeleton` |
| `AppViewXRpcRoutePack+DraftsAndBookmarks.m` | `handleGetDrafts`, `handleGetBookmarks` |

`handleProxyWrite:response:nsid:` goes in `+Identity`, not
`+AgeAssurance`: despite sitting in the ageassurance `#pragma mark`
region of the file, it backs the proxied `com.atproto.repo.createRecord`
/ `putRecord` / `deleteRecord` routes registered at lines 341–351 and
has nothing to do with age assurance.

The main `AppViewXRpcRoutePack.m` keeps: `init`, ivars, `registerRoutesWithServer:` (~400 lines of route wiring), `extractDIDFromAuth:request:`, `requireAuth:response:`.

Method grouping follows NSID namespace, not file position — e.g.
`handleGetLikes`/`handleGetRepostedBy` are `app.bsky.feed.*` and go in
`+Feed` even though they sit in the graph `#pragma mark` region today.
Because ObjC category methods collide silently at load time if two
categories define the same selector, verify each handler appears in
exactly one category file before building (grep the selector across the
new files).

## Build system

CMake uses `file(GLOB_RECURSE ATPROTO_XRPC_SOURCES "Garazyk/Sources/Network/Xrpc*.m" ...)`.
New category files matching `Xrpc*.m` (Steps 1–3) are automatically
picked up, and the `ATPROTO_TRANSPORT_SOURCES` exclude regex
`.*/Network/Xrpc.*\.m$` (CMakeLists.txt:382) already keeps them out of
the transport target.

`AppViewXRpcRoutePack+*.m` files (Step 4) are different — two edits
are required, not one:

1. Add each new file to the explicit `ATPROTO_XRPC_SOURCES` list next to
   `AppViewXRpcRoutePack.m` (CMakeLists.txt:396).
2. Broaden the transport exclude at CMakeLists.txt:386 from
   `.*/Network/AppViewXRpcRoutePack\.m$` to
   `.*/Network/AppViewXRpcRoutePack.*\.m$`. Without this the
   `Network/*.m` glob sweeps the category files into
   `ATPROTO_TRANSPORT_SOURCES` as well, producing duplicate symbols
   across the two targets.

## Constraints

- No contract fixes and god-file decomposition in the same module at the same time. Pure decomposition — no handler logic changes.
- Characterization tests must pass before and after each split.
- Generated NSID constants and the registration drift/lint checks must stay green.
- One coherent decomposition slice per commit.
- No public API removals without caller proof — all category methods are internal.
- GNUstep category loading is proven by existing `PDSDatabase+*` and `PDSActorStore+*` categories.

## Global gates (after each commit)

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
deno task check
deno task lint
```

## Acceptance gate for Slice 1

- Every decomposed module has a characterization suite that passed before and after the split.
- Linux Docker gate passes for Network changes.
- NSID drift check passes.
- No handler logic changed — pure file-level decomposition.

## Tracking

Deciduous goal `#1362` (actions `#1363`–`#1366`, outcome `#1367`); this
plan is attached to the goal node. On slice completion: mark `#1362`
completed, update workstream 02 A3 and mega-plan Phase 4 item 3, and set
`docs/plans/prompts/phase-12-godfile-decomposition.md` status (it moves
to `complete` only after the OAuth and PDS-service slices below).

## Remaining Phase 12 slices (not in this plan)

- Slice 2: `OAuth2Handler.m` (4197 lines)
- Slice 3: `PDSRecordService.m` (1982 lines) and `PDSRepositoryService.m` (2123 lines)
