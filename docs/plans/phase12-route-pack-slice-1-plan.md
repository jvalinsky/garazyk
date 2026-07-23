# Phase 12, Slice 1: Route Pack Decomposition

## Status: draft

## Summary

Split the four XRPC route-pack god files into Objective-C category files by
functional area, behind characterization tests. This is the first slice
of Phase 12 (mega-plan Phase 4 item 3 / workstream 02 A3).

## Files and current sizes

| File | Lines | Namespace(s) | Seams |
|------|-------|-------------|-------|
| `XrpcServerPack.m` | 1446 → 410 | `com.atproto.server.*` | describeServer, session, inviteCodes, appPasswords, accountManagement, accountLifecycle, health |
| `XrpcAdminPack.m` | 1672 | `com.atproto.admin.*` | accountLookup/search/email, serverStats/audit/repair, accountInfo/invites/subjectStatus, accountLifecycle/records/takedown, moderation (deprecated) |
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

### Step 2: `XrpcAdminPack.m` (1672 lines)

Split by `#pragma mark` sections:

| Category file | Routes moved |
|---------------|--------------|
| `XrpcAdminPack+AccountLookup.m` | `searchAccounts`, `sendEmail`, `updateAccountEmail`, `updateAccountHandle`, `updateAccountPassword` |
| `XrpcAdminPack+ServerStats.m` | `getServerStats`, `queryAuditLog`, `repairRepo`, `runBlobAudit`, `getBlobAuditStatus` |
| `XrpcAdminPack+AccountInfo.m` | `getAccountUsage`, `getAccountInfo`, `getAccountInfos`, `getInviteCodes`, `disableAccountInvites`, `enableAccountInvites` |
| `XrpcAdminPack+Lifecycle.m` | `updateSubjectStatus`, `getRecord`, `getSubjectStatus`, `getAccountTakedown`, `deleteAccount`, `disableInviteCodes`, `updateAccountSigningKey` |
| `XrpcAdminPack+Moderation.m` | `moderateAccount`, `moderateRecord`, `takeDownAccount`, `getModerationReports`, `resolveReport` |

The main `XrpcAdminPack.m` keeps: `routePackIdentifier`, `registerWithDispatcher:services:`, helper functions. An `XrpcAdminPack_Internal.h` exposes shared helpers.

### Step 3: `XrpcRepoPack.m` (1748 lines)

Two-phase decomposition:

**Phase A**: Extract validation helpers to their own files:
- `PDSRepoImportValidationResult.h/.m` — the result class
- `PDSRepoImportValidator.h/.m` — the validator class

**Phase B**: Category-decompose the route registration:

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
| `AppViewXRpcRoutePack+Identity.m` | `handleResolveHandle`, `handleGetRecord`, `handleQueryLabels`, `handleGetAccountInfos`, `handleGetSubjectStatus` |
| `AppViewXRpcRoutePack+AgeAssurance.m` | `handleAgeAssuranceBegin`, `handleAgeAssuranceGetConfig`, `handleAgeAssuranceGetState`, `handleProxyWrite` |
| `AppViewXRpcRoutePack+Contact.m` | `handleStartPhoneVerification`, `handleVerifyPhone`, `handleImportContacts`, `handleGetContactMatches`, `handleDismissContactMatch`, `handleGetContactSyncStatus`, `handleRemoveContactData` |
| `AppViewXRpcRoutePack+Search.m` | `handleSearchActorsSkeleton`, `handleSearchPostsSkeleton`, `handleSearchStarterPacksSkeleton` |
| `AppViewXRpcRoutePack+Drafts.m` | `handleGetDrafts`, `handleGetBookmarks` |

The main `AppViewXRpcRoutePack.m` keeps: `init`, ivars, `registerRoutesWithServer:`, `extractDIDFromAuth:request:`, `requireAuth:response:`.

## Build system

CMake uses `file(GLOB_RECURSE ATPROTO_XRPC_SOURCES "Garazyk/Sources/Network/Xrpc*.m" ...)`. 
New category files matching `Xrpc*.m` are automatically picked up. 
`AppViewXRpcRoutePack.m` is explicitly listed at CMakeLists.txt:396; 
new `AppViewXRpcRoutePack+*.m` files will need explicit entries.

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

## Remaining Phase 12 slices (not in this plan)

- Slice 2: `OAuth2Handler.m` (4197 lines)
- Slice 3: `PDSRecordService.m` (1982 lines) and `PDSRepositoryService.m` (2123 lines)
