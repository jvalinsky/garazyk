# Refactor 1: PDSDatabase Monolithic Decomposition

**Evidence:**
- `Garazyk/Sources/Database/PDSDatabase.m` — **3,804 lines**
- 11 category extensions declared in `PDSDatabase.h` but only 5 implemented in separate `@implementation` blocks
- Accounts, Repos, Blocks, Blobs, Transactions + VideoJobs categories are implemented inline in the main body
- `Garazyk/Sources/Database/PDSDatabase.h` — **1,014 lines** single header

## Why It Matters

Consumers of the library can't selectively depend on individual database domains (accounts, blobs, records, etc.). The monolith prevents parallel development, makes testing harder, and creates merge conflicts. It also means any change to one category recompiles everything.

## Target Pattern

The existing `PDSActorStore` decomposition validates the split-category approach:

```
PDSActorStore+Account.h/.m
PDSActorStore+Blob.h/.m  
PDSActorStore+Session.h/.m
```

PDSDatabase should follow the same pattern.

## Proposed Decomposition

### Phase 1: Characterization Tests (before any splitting)

Write integration tests against each PDSDatabase category that capture current behavior:

| Category | Key Methods to Characterize |
|----------|---------------------------|
| Accounts | createAccount, updateAccount, getByDid, getByHandle, deleteAccount |
| Repos | createRepo, updateRepoRoot, getRepoForDid, deleteRepo |
| Records | saveRecord, getRecord, getRecordsForDid:collection: |
| Blocks | saveBlock, saveBlocks:, getBlockWithCid:repoDid:, deleteBlock |
| Blobs | saveBlob, getBlobWithCid, getBlobsForDid, deleteBlob |
| Transactions | begin/commit/rollback, transactWithBlock |
| Moderation | takeDownAccount, createLabel, getLabelsWithPatterns |
| AdminAudit | insertAuditLogEntry, queryAuditLog |
| Reports | createReport, queryReports, updateReportStatus |
| AdminConfig | getAdminConfigValue, setAdminConfigValue |
| VideoJobs | create/update/list/get video jobs |

Tests in: `Garazyk/Tests/Database/PDSDatabase*Tests.m`

### Phase 2: Split Header

Create per-category headers:

```
Database/
  PDSDatabase.h              ← core interface only (open, close, preparedStatement)
  PDSDatabase+Accounts.h/.m
  PDSDatabase+Repos.h/.m
  PDSDatabase+Records.h/.m
  PDSDatabase+Blocks.h/.m
  PDSDatabase+Blobs.h/.m
  PDSDatabase+Transactions.h/.m
  PDSDatabase+Moderation.h/.m
  PDSDatabase+AdminAudit.h/.m
  PDSDatabase+Reports.h/.m
  PDSDatabase+AdminConfig.h/.m
  PDSDatabase+VideoJobs.h/.m
```

Each `.m` file is a single `@implementation PDSDatabase (CategoryName)` block. The main `PDSDatabase.m` retains only the core: init, open, close, statement cache, `safeExecuteSync:`.

### Phase 3: Move Implementation Code

Move each category's implementation into its own file. Preserve all existing method signatures — this is a pure decomposition, no behavioral changes.

### Phase 4: Update CMakeLists.txt

Replace the single `"Garazyk/Sources/Database/*.m"` glob with explicit file lists or verify glob picks up the new files correctly.

### Phase 5: Verify

- All existing tests pass
- Builds with no new warnings
- Benchmarks show no regression (the split should be invisible at runtime)

## Staging

| Step | Description | Rollback |
|------|-------------|----------|
| 1 | Write characterization tests per category | Remove test files |
| 2 | Split PDSDatabase.h into category headers | Revert to single header |
| 3 | Move Accounts implementation | Revert single file |
| 4 | Move Records implementation | Revert single file |
| 5 | Move Repos, Blocks, Blobs implementations | Revert single file |
| 6 | Move Transactions, Moderation implementations | Revert single file |
| 7 | Move AdminAudit, Reports, AdminConfig, VideoJobs | Revert single file |
| 8 | Clean up CMakeLists.txt | Revert CMake change |
| 9 | Final verification pass | n/a |

Each step 3-7 is a separate PR of ~100-400 lines moved. Doable in a single focused session each.

## Dependencies

- Blocked by test coverage (Phase 1) for safe execution
- Must update CMakeLists.txt if using glob (no change needed) or explicit list
- No other files should need changes — all consumers already import `PDSDatabase.h` which can re-export the category headers

## Confidence: High

PDSActorStore already uses this exact pattern successfully.
