# Test Failure Remediation Plan — 2026-04-22

**Git hash**: see `git rev-parse HEAD`
**Test run**: `alltests_4_22_2026.txt`
**Total failures**: 57 test cases across 8 test suites, 199 FAIL: lines

## Summary of Failure Categories

| # | Category | Test Suites | Test Cases | Root Cause | Priority |
|---|----------|-------------|------------|------------|----------|
| A | DB open failure (sqlite_code=14) | XrpcAppBskyAgeAssuranceTests, XrpcChatBskyActorTests, XrpcChatBskyConvoTests | 35 | `AdminAuthXrpcTestBase` setUp fails to open DB | **Critical** |
| B | AppView DB open failure | AppViewBackfillWorkerTests | 2 | `AppViewDatabase` doesn't create parent dir before `sqlite3_open_v2` | **High** |
| C | Interop fixture path resolution | SyntaxInteropTests, AtprotoInteropFixturesTests, LexiconValidatorInteropTests | 13 | Fixture files exist in source tree but runtime path lookup fails | **High** |
| D | SQLite transaction error | SubscribeReposHandler (background) | N/A (log noise) | "cannot commit - no transaction is active" | **Medium** |

---

## Category A: AdminAuthXrpcTestBase DB Open Failure (35 tests)

### Affected Test Suites
- `XrpcAppBskyAgeAssuranceTests` — 3 tests, 18 failures
- `XrpcChatBskyActorTests` — 5 tests, 22 failures
- `XrpcChatBskyConvoTests` — 27 tests, 133 failures

### Root Cause
`AdminAuthXrpcTestBase.m:26` creates a temp directory and passes it to `PDSApplication`, but the database open chain fails with `sqlite_code=14` ("unable to open database file"). The cascade:

1. `setUp` creates temp dir at `NSTemporaryDirectory()/<UUID>`
2. `PDSApplication` init tries to open `ServiceDatabases` at that path
3. SQLite open fails because nested subdirectories (`service/`, `did_cache/`, etc.) don't exist yet
4. Account creation fails → `userDid` is nil → `userJwt` is nil
5. All subsequent assertions fail
6. `NSInvalidArgumentException` from nil insertion into `NSDictionary`/`NSArray`

### Why Other XRPC Tests Pass
The working `RepoAuthXrpcTestBase` sets environment variables:
- `PDS_AVAILABLE_USER_DOMAINS`
- `PDS_ADMIN_PASSWORD`
- `PDS_MASTER_SECRET`

`AdminAuthXrpcTestBase` does NOT set these, which may cause `PDSApplication` to fail differently.

### Fix Plan

- [ ] **A1**: Read `AdminAuthXrpcTestBase.m` setUp and compare with `RepoAuthXrpcTestBase.m` setUp
- [ ] **A2**: Add missing environment variables to `AdminAuthXrpcTestBase` (match `RepoAuthXrpcTestBase`)
- [ ] **A3**: Ensure `PDSApplication` creates parent directories before SQLite open (check `ServiceDatabases.m`, `ActorStore.m`)
- [ ] **A4**: Add error checking to `AdminAuthXrpcTestBase` setUp — fail fast if DB open fails instead of cascading
- [ ] **A5**: Run `XrpcAppBskyAgeAssuranceTests` alone to verify fix
- [ ] **A6**: Run `XrpcChatBskyActorTests` alone to verify fix
- [ ] **A7**: Run `XrpcChatBskyConvoTests` alone to verify fix

### Key Files
- `Garazyk/Tests/Network/AdminAuthXrpcTestBase.m` — failing setUp
- `Garazyk/Tests/Network/RepoAuthXrpcTestBase.m` — working reference
- `Garazyk/Sources/App/PDSApplication.m` — app initialization
- `Garazyk/Sources/Database/Service/ServiceDatabases.m` — DB open chain
- `Garazyk/Sources/Database/ActorStore/ActorStore.m` — where sqlite_code=14 gets wrapped

---

## Category B: AppViewBackfillWorkerTests DB Open (2 tests)

### Root Cause
`AppViewBackfillWorkerTests.m:52` creates `self.testDirectory` but `AppViewDatabase.m` calls `sqlite3_open_v2` directly without ensuring the parent directory exists. The error is `AppViewDatabaseErrorDomain Code=14 "unable to open database file"`.

### Fix Plan

- [ ] **B1**: Add parent directory creation in `AppViewDatabase.m` before `sqlite3_open_v2` (match pattern in `PDSDatabase.m`)
- [ ] **B2**: Or: use in-memory SQLite (`:memory:`) for tests that don't need filesystem persistence
- [ ] **B3**: Run `AppViewBackfillWorkerTests` alone to verify fix

### Key Files
- `Garazyk/Tests/AppView/AppViewBackfillWorkerTests.m` — test setUp
- `Garazyk/Sources/AppView/Server/AppViewDatabase.m` — DB open without parent dir creation

---

## Category C: Interop Fixture Path Resolution (13 tests)

### Affected Test Suites
- `SyntaxInteropTests` — 6 tests, 6 failures
- `AtprotoInteropFixturesTests` — 5 tests, 7 failures
- `LexiconValidatorInteropTests` — 2 tests, 8 failures

### Root Cause
The fixture files **exist** in `Garazyk/Tests/fixtures/atproto-interop-tests/` but the runtime path lookup fails. Each test file has its own lookup logic:

1. **SyntaxInteropTests** — tries CWD-based paths + bundle resourcePath, but bundle path doesn't include `Tests/fixtures/atproto-interop-tests/` prefix
2. **AtprotoInteropFixturesTests** — similar CWD + bundle lookup, same issue
3. **LexiconValidatorInteropTests** — only checks two CWD-based roots, no bundle fallback at all

The tests look for files like `syntax/did_syntax_valid.txt` but the actual path is `Tests/fixtures/atproto-interop-tests/syntax/did_syntax_valid.txt`.

### Fix Plan

- [ ] **C1**: Create a shared `InteropFixtureHelper` category/utility that all 3 test files use
- [ ] **C2**: The helper should search: (1) bundle path + `Tests/fixtures/atproto-interop-tests/`, (2) source tree CWD relative paths, (3) CMake build dir relative paths
- [ ] **C3**: Ensure the fixture directory is included in the test target's resources (CMakeLists.txt or bundle copy phase)
- [ ] **C4**: Update `SyntaxInteropTests.m` to use the shared helper
- [ ] **C5**: Update `AtprotoInteropFixturesTests.m` to use the shared helper
- [ ] **C6**: Update `LexiconValidatorInteropTests.m` to use the shared helper
- [ ] **C7**: Run all 3 interop test suites to verify fix

### Key Files
- `Garazyk/Tests/Interop/SyntaxInteropTests.m` — fixture lookup at lines 11-33
- `Garazyk/Tests/Interop/AtprotoInteropFixturesTests.m` — fixture lookup at lines 21-49
- `Garazyk/Tests/Interop/LexiconValidatorInteropTests.m` — fixture lookup at lines 17-44
- `Garazyk/Tests/fixtures/atproto-interop-tests/` — the actual fixture files (exist!)

---

## Category D: SubscribeReposHandler Transaction Errors (log noise)

### Root Cause
8 instances of `SubscribeReposHandler.m:544` logging "cannot commit - no transaction is active". This is a SQLite transaction lifecycle bug — the code calls `COMMIT` without a matching `BEGIN TRANSACTION`, or the transaction was already rolled back.

### Fix Plan

- [ ] **D1**: Read `SubscribeReposHandler.m:544` and surrounding transaction code
- [ ] **D2**: Add transaction state tracking (check if transaction is active before COMMIT)
- [ ] **D3**: Or: wrap in `@try`/`@catch` to gracefully handle double-commit
- [ ] **D4**: Verify the fix doesn't break firehose event sequencing

### Key Files
- `Garazyk/Sources/Sync/SubscribeReposHandler.m` — line 544

---

## Completed Work (This Session)

### ✅ 19 Missing Lexicon JSON Files Added

All 19 XRPC methods that were registered but had no lexicon JSON now have schemas:

**11 from official atproto repo** (bluesky-social/atproto):
| Method | File |
|--------|------|
| `app.bsky.unspecced.getSuggestedUsersForSeeMore` | `app/bsky/unspecced/getSuggestedUsersForSeeMore.json` |
| `app.bsky.unspecced.getSuggestedUsersForSeeMoreSkeleton` | `app/bsky/unspecced/getSuggestedUsersForSeeMoreSkeleton.json` |
| `app.bsky.unspecced.getSuggestedUsersForDiscover` | `app/bsky/unspecced/getSuggestedUsersForDiscover.json` |
| `app.bsky.unspecced.getSuggestedUsersForDiscoverSkeleton` | `app/bsky/unspecced/getSuggestedUsersForDiscoverSkeleton.json` |
| `app.bsky.unspecced.getSuggestedUsersForExplore` | `app/bsky/unspecced/getSuggestedUsersForExplore.json` |
| `app.bsky.unspecced.getSuggestedUsersForExploreSkeleton` | `app/bsky/unspecced/getSuggestedUsersForExploreSkeleton.json` |
| `app.bsky.unspecced.getSuggestedOnboardingUsers` | `app/bsky/unspecced/getSuggestedOnboardingUsers.json` |
| `app.bsky.unspecced.getOnboardingSuggestedUsersSkeleton` | `app/bsky/unspecced/getOnboardingSuggestedUsersSkeleton.json` |
| `chat.bsky.convo.listConvoRequests` | `chat/bsky/convo/listConvoRequests.json` |
| `chat.bsky.convo.lockConvo` | `chat/bsky/convo/lockConvo.json` |
| `chat.bsky.convo.unlockConvo` | `chat/bsky/convo/unlockConvo.json` |

**8 custom PDS-specific schemas** (not in official atproto repo — deciduous node #158):
| Method | Type | File | Notes |
|--------|------|------|-------|
| `tools.ozone.moderation.getSubjectStatus` | query | `tools/ozone/moderation/getSubjectStatus.json` | Ozone-specific subject status (different from `com.atproto.admin.getSubjectStatus`) |
| `tools.ozone.moderation.cancelScheduledAction` | procedure | `tools/ozone/moderation/cancelScheduledAction.json` | Cancel single action by ID (official repo has plural `cancelScheduledActions`) |
| `tools.ozone.server.updateConfig` | procedure | `tools/ozone/server/updateConfig.json` | Ozone server config update (official repo only has `getConfig`) |
| `com.atproto.admin.getServerStats` | query | `com/atproto/admin/getServerStats.json` | PDS admin stats endpoint |
| `com.atproto.admin.queryAuditLog` | query | `com/atproto/admin/queryAuditLog.json` | PDS admin audit log query |
| `com.atproto.admin.repairRepo` | procedure | `com/atproto/admin/repairRepo.json` | Force reinitialize repo for DID |
| `com.atproto.admin.runBlobAudit` | procedure | `com/atproto/admin/runBlobAudit.json` | Start blob consistency audit job |
| `com.atproto.admin.getBlobAuditStatus` | query | `com/atproto/admin/getBlobAuditStatus.json` | Check blob audit job status |

### Deciduous Updates
- Node #157: `Add 19 missing lexicon JSON files` → **completed**
- Node #158: `8 custom lexicon schemas for PDS-specific XRPC methods` → **observation** (documents the non-standard schemas)
- Node #159: `Fix remaining 57 test failures: 3 root causes` → **decision** (linked to goals #14 and #141)
- Node #26: `Add missing chat.bsky.convo lexicon JSON files` → **completed**

---

## Execution Order

1. **Category A** first — fixes 35 of 57 test cases (biggest impact)
2. **Category B** — 2 more tests
3. **Category C** — 13 more tests
4. **Category D** — log noise cleanup (doesn't affect test pass/fail)

Total: 50 test cases fixed (7 remaining from Category D which is log-level, not test-level)
