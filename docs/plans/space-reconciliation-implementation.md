# Space Reconciliation Implementation Plan

Reference: ADR 0005 — `docs/adr/0005-space-reconciliation-after-oplog-pruning.md`

Upstream proposal: `bluesky-social/proposals` 0016, pinned at
`3f6c96d5d2d25438bd40fa89d6ecc37865f8e354`.

## Architecture

The reconciliation protocol has three recovery paths, tried in order:

```
getLatestCommit → rev matches local? → DONE
    ↓ no
listRepoOps(since=local_rev) → first op's prev == since? → APPLY OPS (incremental)
    ↓ no (gap)
local repo empty? → FULL CAR (getRepo + importRepoFromCAR)
    ↓ no
listRecords(excludeValues=true) → diff against local → changes ≤ threshold?
    → YES: getRecord for each changed record (lightweight)
    → NO: FULL CAR (getRepo + importRepoFromCAR)
```

After any recovery path: verify commit hash matches LtHash digest.

## Phase 1: CAR reader multi-root support

**Files:** `Sources/Repository/CAR.h`, `Sources/Repository/CAR.m`

- [ ] Add `roots` property to `CARReader` (NSArray<CID *> of all root CIDs from the CAR header).
- [ ] Update `parseCarV1Data:` to store all roots from the header CBOR array, not just `firstObject`.
- [ ] Update `parseLegacyData:` similarly (single root → array of one).
- [ ] Keep `rootCID` as `roots.firstObject` for backward compatibility. Update the getter to return `self.roots.firstObject`.
- [ ] Test: parse a two-root CAR, verify both roots are accessible via `roots` and the first is accessible via `rootCID`.

**Why:** The space CAR has two roots (signed commit + DRISL index). The
current reader only exposes the first. Without this, the import code
cannot locate the index block. Using `CARReader` (rather than manual
parsing) reuses tested CAR parsing code and keeps the import logic clean.

## Phase 2: Oplog pruning

**Files:** `Sources/Services/PDS/PDSSpaceStore.h`, `Sources/Services/PDS/PDSSpaceStore.m`

- [ ] Add method:
  ```objc
  - (BOOL)pruneOplogForSpace:(NSString *)space
                      author:(NSString *)author
            keepingRevisions:(NSUInteger)keepCount
                       error:(NSError **)error;
  ```
  SQL: `DELETE FROM space_record_oplog WHERE space = ? AND author_did = ? AND rev NOT IN (SELECT DISTINCT rev FROM space_record_oplog WHERE space = ? AND author_did = ? ORDER BY rev DESC LIMIT ?)`

- [ ] Add method:
  ```objc
  - (BOOL)pruneAllOplogsKeepingRevisions:(NSUInteger)keepCount
                                    error:(NSError **)error;
  ```
  This enumerates all distinct `(space, author_did)` pairs in
  `space_record_oplog` and calls `pruneOplogForSpace:author:keepingRevisions:`
  for each one.

- [ ] Add a method to enumerate repos with oplog entries:
  ```objc
  - (NSArray<NSDictionary<NSString *, id> *> *)repositoriesWithOplogs:(NSError **)error;
  ```
  Returns `{ @"space": ..., @"author": ... }` for each distinct
  `(space, author_did)` in `space_record_oplog`.

- [ ] Test: insert 200 ops across 10 revisions, prune to keep 5, verify
  only the last 5 revisions remain.
- [ ] Test: prune a repo with 0 ops (no-op, no error).
- [ ] Test: prune with keepCount=0 (deletes all ops).

**Why:** The proposal says "a repo host may compact or drop it, retaining
only a backfill window." Count-based pruning is the simplest correct
implementation. The background timer (Phase 7) calls
`pruneAllOplogsKeepingRevisions:` periodically. Tests call the per-repo
method directly.

## Phase 3: PDSSpaceStore CAR import method

**Files:** `Sources/Services/PDS/PDSSpaceStore.h`, `Sources/Services/PDS/PDSSpaceStore.m`

- [ ] Add method:
  ```objc
  - (BOOL)importRepoFromCAR:(NSData *)carData
                      space:(NSString *)space
                     author:(NSString *)author
            commitPublicKey:(NSData *)publicKey
                      error:(NSError **)error;
  ```

- [ ] Implementation:
  1. Parse the CAR via `[CARReader readFromData:error:]`.
  2. Extract both roots: `reader.roots[0]` (commit CID), `reader.roots[1]` (index CID).
  3. Fetch the commit block: `[reader blockWithCID:reader.roots[0]]`.
  4. Fetch the index block: `[reader blockWithCID:reader.roots[1]]`.
  5. Decode the commit block as DAG-CBOR via `ATProtoDagCBOR`.
  6. Build a `PDSSpaceCommit` from the decoded commit fields.
  7. Verify the commit signature: `verifySignatureForSpace:author:publicKey:error:`.
  8. Verify the commit MAC: `verifyIntegrityForSpace:author:error:`.
  9. Decode the index block as DAG-CBOR: `{ path → CID }`.
  10. For each index entry, locate the record block by CID via `blockWithCID:`
      and validate the block's CID matches the index CID.
  11. Rebuild LtHash from index entries: `addElement("{collection}/{rkey}/{cid}")`
      for each.
  12. Compute SHA-256 digest of LtHash state, compare against commit `hash`.
  13. In a single SQLite transaction:
      - Delete existing `space_record` rows for this space+author.
      - Insert imported records (path, cid, value, repo_rev=commit.rev).
      - Update `space_repo` with new `lthash_state` and `rev`.
      - Truncate `space_record_oplog` for this space+author (delete all rows).

- [ ] Add error codes to `PDSSpaceStoreError` enum:
  - `PDSSpaceStoreErrorInvalidCAR` — CAR parsing failed.
  - `PDSSpaceStoreErrorCommitMismatch` — LtHash digest doesn't match commit hash.
  - `PDSSpaceStoreErrorCommitSignature` — commit signature verification failed.
  - `PDSSpaceStoreErrorMissingBlock` — a record block referenced by the index is missing from the CAR.

- [ ] Test: import a known-good CAR, verify records and state match.
- [ ] Test: import a CAR with a bad commit signature, verify rejection.
- [ ] Test: import a CAR with a bad LtHash, verify rejection.
- [ ] Test: import a CAR with a missing record block, verify rejection.
- [ ] Test: import a CAR over an existing repo, verify old records are replaced.

**Why:** This is the core full-state recovery primitive. The CAR is the
authoritative state from the repo host. The import must validate everything
before writing, and the write must be atomic. Using `CARReader` (after
multi-root support) reuses tested CAR parsing code.

## Phase 4: Pagination fix for listRecords and listRepoOps

**Files:** `Sources/Network/XrpcSpacePack.m`

- [ ] `listRecords` handler: when `records.count == limit`, include cursor
  in the response. The cursor is the last record's
  `{collection}/{rkey}`.
  ```objc
  NSMutableDictionary *result = [@{ @"records" : views } mutableCopy];
  if (records.count == limit) {
      NSDictionary *last = records.lastObject;
      result[@"cursor"] = [NSString stringWithFormat:@"%@/%@", last[@"collection"], last[@"rkey"]];
  }
  response.statusCode = HttpStatusOK; [response setJsonBody:result];
  ```

- [ ] `listRepoOps` handler: when `ops.count == limit`, include cursor in
  the response. The cursor is the last op's `rev`.
  ```objc
  if (ops.count == limit) {
      result[@"cursor"] = [ops.lastObject[@"rev"] copy];
  }
  ```

- [ ] Test: verify `listRecords` returns a cursor when results fill the limit.
- [ ] Test: verify `listRepoOps` returns a cursor when results fill the limit.
- [ ] Test: verify no cursor when results are below the limit.

**Why:** Both lexicons define `cursor` in the output schema, but the
handlers don't return it. This is a bug. The lightweight recovery path
requires paginating through all records via `listRecords`, so this must
be fixed first.

## Phase 5: PDSSpaceStore local record index method

**Files:** `Sources/Services/PDS/PDSSpaceStore.h`, `Sources/Services/PDS/PDSSpaceStore.m`

- [ ] Add method:
  ```objc
  - (nullable NSDictionary<NSString *, NSString *> *)recordIndexForSpace:(NSString *)space
                                                                  author:(NSString *)author
                                                                   error:(NSError **)error;
  ```
  Returns a `{ "{collection}/{rkey}" → cid }` dictionary for all records
  in the repo. This is the local side of the lightweight recovery diff.

- [ ] SQL:
  ```sql
  SELECT collection, rkey, cid FROM space_record
  WHERE space = ? AND author_did = ?
  ORDER BY collection, rkey
  ```

- [ ] Test: verify the index matches the records inserted by `applyWrites:`.
- [ ] Test: verify empty repo returns empty dictionary.

**Why:** The lightweight recovery path needs to diff the remote
`listRecords(excludeValues=true)` listing against the local state. This
method provides the local `{path → CID}` map.

## Phase 6: Lightweight recovery

**Files:** `Sources/Services/PDS/PDSSpaceReconciler.m` (or a new `PDSSpaceSyncer.m`)

This is the subplan for the lightweight recovery path. It is an
optimization of the full CAR path for the case where the local repo
already has most of the records and only a few have changed.

### Phase 6a: Remote listing fetch

- [ ] Add a method to the reconciler that fetches the full remote record
  listing via paginated `listRecords(excludeValues=true)` calls:
  ```objc
  - (nullable NSDictionary<NSString *, NSString *> *)
      fetchRemoteRecordIndexForSpace:(NSString *)space
                              author:(NSString *)author
                           endpoint:(NSURL *)endpoint
                              token:(NSString *)token
                               error:(NSError **)error;
  ```
  This paginates through all `listRecords` pages (limit=100 per page),
  following the cursor, and builds a `{ "{collection}/{rkey}" → cid }`
  dictionary.

- [ ] Test: mock the remote server, verify pagination works correctly.
- [ ] Test: verify the returned index matches the remote records.

### Phase 6b: Diff computation

- [ ] Add a diff method:
  ```objc
  - (void)computeDiffBetweenLocal:(NSDictionary<NSString *, NSString *> *)localIndex
                        andRemote:(NSDictionary<NSString *, NSString *> *)remoteIndex
                       toAdd:(NSMutableArray<NSString *> *)toAdd
                     toUpdate:(NSMutableArray<NSString *> *)toUpdate
                    toDelete:(NSMutableArray<NSString *> *)toDelete;
  ```
  - `toAdd`: paths in remote but not local.
  - `toUpdate`: paths in both but CID differs.
  - `toDelete`: paths in local but not remote.

- [ ] Test: diff two identical indexes → all empty.
- [ ] Test: diff with adds, updates, and deletes → correct classification.

### Phase 6c: Recovery path decision

- [ ] After computing the diff, decide which path to take:
  ```objc
  NSUInteger totalChanges = toAdd.count + toUpdate.count + toDelete.count;
  NSUInteger threshold = MIN(50, MAX(1, remoteIndex.count / 4));
  if (totalChanges <= threshold) {
      // Lightweight: fetch individual records via getRecord
  } else {
      // Full CAR: fetch via getRepo + importRepoFromCAR
  }
  ```

- [ ] The threshold is `MIN(50, MAX(1, remoteCount / 4))` — at most 50
  records, or 25% of the total, whichever is smaller. This is
  configurable via a property on the reconciler.

### Phase 6d: Lightweight record fetch and apply

- [ ] For each record in `toAdd` and `toUpdate`:
  1. Parse the path into `collection` and `rkey`.
  2. Call `getRecord` on the remote authority to fetch the record value.
  3. Build a `PDSSpaceWrite` with action=create (for add) or update (for update).
  4. Apply via `applyWrites:toSpace:author:rev:nil:error:`.

- [ ] For each record in `toDelete`:
  1. Parse the path into `collection` and `rkey`.
  2. Build a `PDSSpaceWrite` with action=delete.
  3. Apply via `applyWrites:toSpace:author:rev:nil:error:`.

- [ ] After all changes, verify the LtHash digest matches the commit hash.

- [ ] Test: mock remote, add 3 records, verify lightweight path is used.
- [ ] Test: mock remote, change 60% of records, verify full CAR fallback.
- [ ] Test: verify LtHash matches after lightweight recovery.

**Why:** The upstream proposal describes this as an optimization for
"slightly diverged" copies. The lightweight path trades the single
`getRepo` round-trip for smaller total transfer when most of the repo is
already held. The threshold ensures we only use the lightweight path when
it's actually more efficient. The `listRecords(excludeValues=true)` call
is cheap (just metadata), so it's always worth doing the listing before
deciding.

## Phase 7: Reconciler inbound sync

**Files:** `Sources/Services/PDS/PDSSpaceReconciler.h`, `Sources/Services/PDS/PDSSpaceReconciler.m`

- [ ] Add inbound sync to `reconcileOnQueue`:
  ```objc
  - (void)reconcileOnQueue {
      if (self.stopped) return;
      NSArray *heads = [self.spaceStore repositoriesForReconciliation:nil];
      for (NSDictionary *head in heads) {
          [self replayHead:head];      // outbound: notify authority
          [self syncRemoteRepo:head]; // inbound: sync from authority
      }
  }
  ```

- [ ] Add `syncRemoteRepo:`:
  1. Parse space, author, local rev, local hash from head.
  2. Skip if `[space.authorityDID isEqualToString:author]` (this is the
     authority's own repo, no need to sync from itself).
  3. Resolve the authority PDS endpoint from the space authority DID.
  4. Mint a service-auth JWT for `com.atproto.space.getLatestCommit`.
  5. Call `getLatestCommit` on the remote authority.
  6. If remote `rev` matches local `rev` → done.
  7. If not, call `listRepoOps` with `since=local_rev`.
  8. If first op's `prev` matches `since` (or `since` is nil): apply ops
     locally via `applyWrites:`, update LtHash, check commit hash.
  9. If first op's `prev` does not match `since` (gap detected):
     a. If local repo is empty (no records): call `getRepo`, call
        `importRepoFromCAR:`.
     b. If local repo exists: fetch remote listing via
        `listRecords(excludeValues=true)`, diff against local, decide
        lightweight vs full CAR (Phase 6).
  10. After recovery: verify commit hash matches LtHash digest.

- [ ] Test: mock remote authority, verify gap detection and fallback.
- [ ] Test: mock remote authority, verify incremental op application.
- [ ] Test: mock remote authority, verify lightweight recovery for small diff.
- [ ] Test: mock remote authority, verify full CAR fallback for large diff.

**Why:** The reconciler already has the timer, JWT minting, and HTTP
client infrastructure. Adding inbound sync alongside outbound replay is
the natural place for this logic. The three-path strategy (incremental →
lightweight → full CAR) follows the upstream proposal's design.

## Phase 8: Oplog pruning background timer

**Files:** `Sources/Services/PDS/PDSSpaceReconciler.h` (or a new `PDSSpaceOplogPruner.h`), `Sources/Services/PDS/PDSSpaceReconciler.m` (or new file)

- [ ] Add a periodic timer that calls `pruneAllOplogsKeepingRevisions:`
  on a configurable interval. This can be a separate class
  (`PDSSpaceOplogPruner`) or integrated into the PDS runtime.
- [ ] Config: `permissionedSpacesOplogRetentionCount` (default: 100),
  `permissionedSpacesOplogPruneInterval` (default: 3600 seconds).
- [ ] The timer runs on a serial dispatch queue, similar to the reconciler.
- [ ] Pruning is disabled by default (retention count = 0 means no pruning).
- [ ] Test: verify the timer fires and prunes oplogs correctly.

**Why:** The proposal says "a repo host may compact or drop it, retaining
only a backfill window." A background timer is the best practices
approach: it decouples pruning from the write path, is configurable, and
provides a predictable bound on oplog size.

## Phase 9: Scenario 93 update (or new scenario 94)

**Files:** `scripts/scenarios/scenarios/93_permissioned_spaces.ts` (or new `94_*.ts`)

- [ ] After the existing reader credential read step, add:
  1. Writer writes additional records on PDS A.
  2. Reader syncs via `listRepoOps` (incremental path).
  3. Simulate oplog pruning on the authority (call
     `pruneOplogForSpace:author:keepingRevisions:1` directly via a debug
     endpoint or test helper).
  4. Writer writes more records.
  5. Reader syncs again — detects gap, falls back to recovery.
  6. Verify reader has all records, including those written after pruning.
  7. If testing lightweight path: verify that only a few `getRecord`
     calls were made (small diff).
  8. If testing full CAR path: verify that `getRepo` was called (large diff).

- [ ] If scenario 93 is too long, create a new scenario 94 for
  reconciliation specifically.

**Why:** The compatibility gate requires a multi-PDS acceptance test for
full-state CAR reconciliation. This is the executable proof.

## Phase 10: Compatibility gate update

**Files:** `docs/permissioned-spaces-compatibility.md`

- [ ] Update "Multi-PDS recovery" row from "pending" to "Implemented" once
  the scenario passes.
- [ ] Update "Reads and writes" and "Notifications" rows from "scenario
  93 runtime pass pending" to "Implemented" once scenario 93 passes.

## Summary of new methods

| Class | Method | Phase |
|-------|--------|-------|
| `CARReader` | `roots` property | 1 |
| `PDSSpaceStore` | `pruneOplogForSpace:author:keepingRevisions:error:` | 2 |
| `PDSSpaceStore` | `pruneAllOplogsKeepingRevisions:error:` | 2 |
| `PDSSpaceStore` | `repositoriesWithOplogs:` | 2 |
| `PDSSpaceStore` | `importRepoFromCAR:space:author:commitPublicKey:error:` | 3 |
| `PDSSpaceStore` | `recordIndexForSpace:author:error:` | 5 |
| `PDSSpaceReconciler` | `syncRemoteRepo:` | 7 |
| `PDSSpaceReconciler` | `fetchRemoteRecordIndexForSpace:author:endpoint:token:error:` | 6a |
| `PDSSpaceReconciler` | `computeDiffBetweenLocal:andRemote:toAdd:toUpdate:toDelete:` | 6b |
| `PDSSpaceOplogPruner` (or inline) | periodic `pruneAllOplogsKeepingRevisions:` | 8 |

## Summary of bug fixes

| Bug | Fix | Phase |
|-----|-----|-------|
| `listRecords` doesn't return cursor | Return cursor when `records.count == limit` | 4 |
| `listRepoOps` doesn't return cursor | Return cursor when `ops.count == limit` | 4 |
