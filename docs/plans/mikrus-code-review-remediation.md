# Mikrus Code Review — Revised Remediation Plan

**Date**: 2026-05-21
**Scope**: Mikrus link index service (`Garazyk/Sources/Mikrus/`, `Garazyk/Tests/Mikrus/`, `Garazyk/Binaries/mikrus/`, `Garazyk/Tests/test_main.m`)

## Context

A deep manual code review of the Mikrus service identified four issues plus a test infrastructure
bug. Each finding was verified against the actual source code. This plan revises the original
remediation approach based on that verification, adjusting severity ratings, depth limits, and
addressing mitigations already in place.

---

## Finding 1: Uncapped Recursion in Link Extractor

- **File**: `Garazyk/Sources/Mikrus/MikrusLinkExtractor.m`
- **Method**: `+collectLinksFromObject:path:entries:seen:`
- **Original severity**: P1/P0 (DoS stack overflow)
- **Revised severity**: **P2** — defense-in-depth measure

### Analysis

The recursive tree walk has no depth guard. However:

1. Input comes from `NSJSONSerialization`, which cannot produce circular references
2. ATProto records are shallow (2–4 nesting levels typical; ~8 max for complex faceted posts)
3. The attack surface requires a malicious payload injected through a trusted relay
4. `collectSubjectsFromObject:components:index:results:` is already bounded by `components.count`

The risk is real but narrow. The fix is a defense-in-depth guard.

### Required Changes

**`MikrusLinkExtractor.m`** — Add a depth parameter to `collectLinksFromObject:`:

1. Change `collectLinksFromObject:path:entries:seen:` to `collectLinksFromObject:path:entries:seen:depth:`
2. Add `static const NSUInteger kMikrusMaxRecursionDepth = 50;`
3. At the top of the method, bail out if `depth > kMikrusMaxRecursionDepth`
4. Increment `depth + 1` on each recursive call
5. Update the public `+linkEntriesInRecord:` to pass `depth:0`

**Note**: The original plan's depth of 16 is too low. Legitimate deeply-structured records
(e.g., `app.bsky.feed.post` with facets containing features with URIs, embedded record refs)
can reach 5–8 levels. A depth of 50 provides ample headroom for any legitimate payload while
still preventing stack overflow from pathological 10,000-level nesting.

### Risk Considerations

- **False positive risk**: Near zero at depth 50 — no legitimate ATProto record approaches this
- **Stack usage per level**: ~200 bytes (two ObjC message sends + NSDictionary access). 50 levels ≈ 10KB, well within the default 512KB stack

---

## Finding 2: Synchronous Thread Blocking via dispatch_semaphore_t

- **File**: `Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m`
- **Methods**: `-resolveIdentifierToDID:error:`, `-fetchRemoteRecordForDID:collection:rkey:cid:`
- **Original severity**: P1 (GCD thread pool exhaustion)
- **Revised severity**: **P1** — real, but some mitigations already exist

### Analysis

Both methods use `dispatch_semaphore_wait` to bridge async APIs into a synchronous handler
context. Under high concurrency, this can exhaust GCD's thread pool.

**Mitigations already in place** (not captured by original review):

1. `resolveIdentifierToDID:error:` checks the local database cache **before** hitting the network:
   ```objc
   NSString *local = [_database resolveHandleToDID:[identifier lowercaseString] error:nil];
   if (local.length > 0) return local;  // cache hit, no blocking
   ```
2. `fetchRemoteRecordForDID:` checks the local database **before** falling back to the network:
   ```objc
   NSDictionary *record = [_database recordByURI:canonicalURI cid:cid error:&error];
   if (!record) {
       record = [self fetchRemoteRecordForDID:...]; // only on cache miss
   }
   ```
3. Handle resolution writes back to cache on success (`saveHandle:did:`)

### Required Changes

**`MikrusXrpcRoutePack.m`** — Two targeted changes:

1. **Shorten timeouts** from 10s to 5s in both methods:
   - `resolveIdentifierToDID:`: `dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)`
   - `fetchRemoteRecordForDID:`: `request.timeoutInterval = 5.0` and `dispatch_time(..., 5 * NSEC_PER_SEC)`

2. **Add concurrency guard comment** above each blocking method:
   ```objc
   // NOTE: Blocks the calling GCD thread up to 5s. Local cache is checked first;
   // network call only fires on cache miss. If HttpServer moves to async handler
   // dispatch, refactor to completion-block pattern.
   ```

### Out of Scope (Larger Refactor)

A proper async refactor would require `HttpServer` to support completion-callback-based
handler dispatch. This is a significant architectural change affecting the entire route
pack system. Not warranted for the current risk profile given the caching mitigations.

---

## Finding 3: GET Request with Database Write Side Effects

- **File**: `Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m`
- **Method**: `-handleResolveMiniDoc:response:`
- **Original severity**: P2 (SQLite lock contention)
- **Revised severity**: **P3** — acceptable read-through cache pattern

### Analysis

The GET handler calls `[_database saveHandle:handle did:did error:nil]` which performs an
`INSERT OR REPLACE` on the `mikrus_handles` table. This is:

1. **Idempotent** — safe to call repeatedly with the same values
2. **Fire-and-forget** — already uses `error:nil` (best-effort cache population)
3. **SQLite WAL compatible** — WAL mode allows concurrent reads alongside a writer without blocking
4. **Standard pattern** — read-through caching is a well-established identity resolution technique

### Required Changes

**None**. Accept as-is. The risk of lock contention is negligible in WAL mode with a
connection pool. Adding async write dispatch would add complexity (queue management,
potential data loss on crash before write) without meaningful benefit.

### Documentation

Add a brief comment above the `saveHandle:` call noting the read-through cache pattern:
```objc
// Populate local handle→DID cache for future lookups (best-effort, read-through pattern)
[_database saveHandle:handle did:did error:nil];
```

---

## Finding 4: Redundant Database Index

- **File**: `Garazyk/Sources/Mikrus/MikrusDatabase.m`
- **Method**: `-runMigrations:`
- **Original severity**: P2
- **Revised severity**: **P2** (confirmed)

### Analysis

The migration schema creates a redundant index:

```sql
CREATE TABLE IF NOT EXISTS mikrus_records (
  uri TEXT PRIMARY KEY,
  ...
  UNIQUE(did, collection, rkey)           -- (A) creates implicit unique B-tree index
);
CREATE INDEX IF NOT EXISTS idx_mikrus_records_did_collection
ON mikrus_records(did, collection, rkey);  -- (B) creates second, non-unique B-tree index
```

Index (B) is entirely redundant:
- The UNIQUE constraint's implicit index already covers those columns for all query patterns
- (B) wastes disk space (duplicate B-tree structure)
- (B) adds write overhead on every INSERT/UPDATE (both indexes must be maintained)
- SQLite's query planner will use the unique index for lookups regardless

### Required Changes

**`MikrusDatabase.m`** — Two changes in `runMigrations:`:

1. **Remove** the redundant `CREATE INDEX` line from the schema string
2. **Add cleanup migration** for existing databases:
   ```sql
   DROP INDEX IF EXISTS idx_mikrus_records_did_collection;
   ```
   Place this at the end of the schema string, after all CREATE statements.

The `IF EXISTS` clause ensures clean idempotent operation on both new and existing databases.

### SQLite Documentation Confirmation

Per SQLite docs: "In most cases, UNIQUE and PRIMARY KEY constraints are implemented by
creating a unique index in the database." The explicit non-unique index on the same columns
provides no additional query-plan benefit.

---

## Finding 5: Test Runner --gated Argument Parsing Mismatch

- **File**: `Garazyk/Tests/test_main.m`
- **Original severity**: Infrastructure bug
- **Revised severity**: **P2** — documentation/UX mismatch causes silent test skipping

### Analysis

The `--gated` argument parser only handles the two-token form:

```objc
if ([arg isEqualToString:@"--gated"] && i + 1 < argc) {
    NSString *mode = [NSString stringWithUTF8String:argv[i + 1]];
    // expects: --gated run   (space-separated tokens)
```

But the documentation and error messages reference the single-token form:

- Skip reason message (line ~525): `"gated:%@ (use --gated=run)"`
- Help text (line ~1060): `"--gated=MODE         Gated test mode: skip (default), run, include"`

A user running `--gated=run` will:
1. Have `--gated=run` match neither `--gated` nor any other flag
2. Silently skip all gated tests (defaults to `PDSGatedModeSkip`)

### Required Changes

**`test_main.m`** — Support both parsing forms:

Replace the current single-form parser:
```objc
if ([arg isEqualToString:@"--gated"] && i + 1 < argc) {
    NSString *mode = [NSString stringWithUTF8String:argv[i + 1]];
    ...
    i++;
}
```

With a dual-form parser:
```objc
NSString *mode = nil;
if ([arg isEqualToString:@"--gated"] && i + 1 < argc) {
    mode = [NSString stringWithUTF8String:argv[i + 1]];
    i++;  // consume mode argument
} else if ([arg hasPrefix:@"--gated="]) {
    mode = [arg substringFromIndex:8];  // length of "--gated="
} else {
    continue;  // not a --gated flag
}

if ([mode isEqualToString:@"run"]) {
    gatedMode = PDSGatedModeRun;
} else if ([mode isEqualToString:@"include"]) {
    gatedMode = PDSGatedModeMarkSkip;
} else {
    gatedMode = PDSGatedModeSkip;
}
```

Also update the help text to show both forms:
```c
fprintf(stderr, "      --gated run|include|skip   Gated test mode: skip (default), run, include\n");
fprintf(stderr, "      --gated=MODE               Equivalent to --gated MODE\n");
```

---

## Implementation Order

| Step | File | Change | Risk | Build Impact |
|------|------|--------|------|-------------|
| 1 | `MikrusLinkExtractor.m` | Add recursion depth guard (50) | Low | Recompile lib |
| 2 | `MikrusDatabase.m` | Remove redundant index + add DROP IF EXISTS | Low | Recompile lib |
| 3 | `MikrusXrpcRoutePack.m` | Shorten timeouts 10s→5s + add comments | Low | Recompile lib |
| 4 | `MikrusXrpcRoutePack.m` | Add comment on read-through cache pattern | None | None |
| 5 | `test_main.m` | Support --gated=MODE parsing | Low | Recompile test runner |

All changes are additive or removal-only; no API surface changes.

---

## Verification

1. **Build**: `cmake --build build --target mikrus --target AllTests`
2. **Unit tests**: Run `./build/bin/AllTests` and verify all 13 Mikrus tests pass
3. **Gated test parsing**:
   - `./build/bin/AllTests --gated run` → MikrusRuntimeTests runs
   - `./build/bin/AllTests --gated=run` → MikrusRuntimeTests runs (previously skipped)
   - `./build/bin/AllTests` → MikrusRuntimeTests skipped with clear message
4. **Index verification**: Inspect SQLite schema with `.schema mikrus_records` to confirm no redundant index
5. **Recursion guard**: Write a unit test with a 60-level nested JSON payload and verify it returns partial results (first 50 levels) without crashing

---

## Decisions Recorded

| Decision | Rationale |
|----------|-----------|
| Recursion depth = 50, not 16 | ATProto records may nest 5–8 levels legitimately; 50 provides 6× headroom |
| Accept GET write side effects | Read-through cache pattern is standard and safe in WAL mode |
| 5s timeouts instead of async refactor | Async refactor requires HttpServer changes; caching mitigates most blocking |
| Both `--gated` parsing forms | Backward-compatible; follows common CLI conventions (e.g., `--foo bar` and `--foo=bar`) |
