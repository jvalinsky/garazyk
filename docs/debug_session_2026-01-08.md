# Test Suite Debug Session - January 8, 2026

## Overview

A debugging session was conducted to resolve failing tests in the ATProtoPDS Objective-C test suite. Results: all 31 tests passing, increased from 25/31 (81%) at session start.

## Initial State

| Test Suite | Passing | Failing | Percentage |
|------------|---------|---------|------------|
| ActorStoreTests | 8 | 0 | 100% |
| DatabasePoolTests | 8 | 1 | 89% |
| PDSControllerTests | 9 | 5 | 64% |
| **Total** | **25** | **6** | **81%** |

## Issues Found and Resolved

### Issue 1: Database Pool Eviction Test Assertion

**File:** `tests/Database/Pool/DatabasePoolTests.m:127`

**Symptom:** Test expected `currentSize == 2` after evicting and recreating store.

**Root Cause:** Test logic was incorrect. After creating 3 stores (A, B, C), evicting B (count: 2), and recreating B, pool correctly has 3 stores. Test assertion `XCTAssertEqual(self.pool.currentSize, 2)` was incorrect.

**Fix:** Changed assertion to expect 3 stores:
```objc
XCTAssertEqual(self.pool.currentSize, 3, @"Pool should have 3 stores (evicted was recreated)");
```

---

### Issue 2: Duplicate Account Error Code

**File:** `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m:410-418`

**Symptom:** `testCreateDuplicateAccount` failed with error code 1555 (SQLite UNIQUE constraint) instead of expected 1001 (`PDSControllerErrorAccountAlreadyExists`).

**Root Cause:** The SQLite constraint error was propagated without translation to the domain-specific error.

**Fix:** Added proper error translation in `createAccount:`:
```objc
if (!success) {
    int sqliteCode = sqlite3_extended_errcode(self.db);
    BOOL isConstraintViolation = (sqliteCode == SQLITE_CONSTRAINT_UNIQUE ||
                                  sqliteCode == SQLITE_CONSTRAINT_PRIMARYKEY ||
                                  sqliteCode == SQLITE_CONSTRAINT_FOREIGNKEY ||
                                  sqliteCode == SQLITE_CONSTRAINT_CHECK ||
                                  sqliteCode == SQLITE_CONSTRAINT_NOTNULL);
    if (isConstraintViolation) {
        *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                    code:PDSActorStoreErrorAlreadyExists
                                userInfo:@{NSLocalizedDescriptionKey: @"Account already exists",
                                         @"sqlite_code": @(sqliteCode),
                                         @"sqlite_message": [NSString stringWithUTF8String:sqlite3_errmsg(self.db)] ?: @""}];
    }
}
```

---

### Issue 3: Refresh Token Validation

**File:** `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m`

**Symptom:** `testRefreshToken` failed with "Invalid refresh token" error.

**Root Cause:** The schema defined a `refresh_tokens` table for token management, but it was never populated. The `getAccountByRefreshToken:` method queried this table, which was empty.

**Fix:** 
1. Added token storage method to `ServiceDatabases.h`:
```objc
- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error;
- (BOOL)deleteRefreshTokensForAccount:(NSString *)accountDid error:(NSError **)error;
```

2. Implemented token storage in `ServiceDatabases.m`:
```objc
- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error {
    // INSERT into refresh_tokens table
}
```

3. Updated `PDSController` to store tokens on account creation and login:
```objc
[_serviceDatabases storeRefreshToken:refreshToken forAccount:resolvedDid error:nil];
```

---

### Issue 4: Account Deletion - Wrong Database Query

**File:** `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m:166-171`

**Symptom:** `testDeleteAccount` and `testDeleteAccountWrongPassword` failed with "Account not found" error.

**Root Cause:** The bug was subtle and required deep investigation:

1. `PDSController.deleteAccount:` called `ServiceDatabases.getAccountByDid:`
2. `getAccountByDid:` called `servicePool.getAccount:did`
3. `DatabasePool.getAccount:did` called `storeForDid:did`
4. This created/opened a store for the user's DID (e.g., `did:plc:xxx`)
5. But accounts are stored in the `__service__` database, not per-user databases!

The method was looking in the wrong database entirely.

**Fix:** Rewrote `getAccountByDid:` to query the `__service__` store directly:
```objc
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:nil];
    if (!store) return nil;

    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
    sqlite3_stmt *stmt = [store prepareStatement:sql error:error];
    if (!stmt) return nil;

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [store accountFromStatement:stmt];
    }

    [store finalizeStatement:stmt];
    return account;
}
```

---

## Debug Techniques Used

### 1. Targeted Test Filtering
```bash
./AllTests --filter testDeleteAccount
```

### 2. Strategic Debug Logging
Added temporary NSLog statements at key points:
- DID creation and storage
- Handle lookup results
- DID resolution flow
- Database query results

Example:
```objc
NSLog(@"[DEBUG] createAccount: storing account with did=%@, handle=%@", account.did, account.handle);
```

### 3. Trace Comparison
Matched debug output from create vs. delete operations to identify discrepancies:
```
[DEBUG] createAccount: storing did=did:plc:abc123, handle=testuser
[DEBUG] getAccountByDid: looking for did=did:plc:abc123
[DEBUG] getAccountByDid: result=(null)  <- Problem!
```

### 4. Code Path Tracing
Traced the flow through:
1. `PDSController.createAccountForEmail:...`
2. `ServiceDatabases.createAccount:`
3. `ActorStore.createAccount:`
4. Reverse: `PDSController.deleteAccount:did:...`
5. `ServiceDatabases.getAccountByDid:`
6. `DatabasePool.getAccount:did`
7. `ActorStore.getAccountForDid:`

## Key Insights

### Database Architecture Understanding
- **Service database** (`__service__`): Stores account metadata, tokens, invite codes
- **User databases**: One per account, stores records, blocks, repo data
- **Critical distinction**: Account lookups must query `__service__`, not per-user databases

### SQLite Error Handling
- Constraint violations (codes 1555-1559, 1299) need translation to domain errors
- Error propagation must preserve helpful context

### Token Management
- Refresh tokens should be stored in a dedicated table with proper indexing
- Cleanup needed on account deletion

## Final Results

| Test Suite | Passing | Failing | Percentage |
|------------|---------|---------|------------|
| ActorStoreTests | 8 | 0 | 100% |
| DatabasePoolTests | 9 | 0 | 100% |
| PDSControllerTests | 14 | 0 | 100% |
| **Total** | **31** | **0** | **100%** |

## Files Modified

| File | Changes |
|------|---------|
| `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m` | Error translation for constraint violations |
| `ATProtoPDS/Sources/App/PDSController.m` | Refresh token storage, error handling |
| `ATProtoPDS/Sources/Database/Service/ServiceDatabases.h` | Added refresh token methods |
| `ATProtoPDS/Sources/Database/Service/ServiceDatabases.m` | Token storage, fixed getAccountByDid |
| `tests/Database/PDSControllerTests.m` | Fixed delete tests to use actual DID |
| `tests/Database/Pool/DatabasePoolTests.m` | Fixed pool size assertion |

## Lessons Learned

1. **Follow the data flow**: When debugging, trace data from creation to consumption
2. **Test assertions may be wrong**: Not all test failures indicate code bugs
3. **Architecture matters**: Understanding the database separation (service vs user) was key
4. **Error translation is critical**: Low-level errors should be translated to domain errors at appropriate layers
5. **Dedicated logging during debugging**: Strategic NSLog statements saved hours of investigation
