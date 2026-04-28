# WebAuthn Registration Endpoints Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add WebAuthn credential registration, authentication endpoints, and integrate with OAuth2 token exchange flow.

**Architecture:** Create HTTP handlers for WebAuthn registration flows, add database table for credential storage, wire into OAuth2 token endpoint alongside existing TOTP MFA.

**Tech Stack:** Objective-C, SQLite (via existing PDSDatabase), WebAuthnVerifier (existing), OAuth2.m

---

### Task 1: Add webauthn_credentials table to schema

**Files:**
- Modify: `Garazyk/Sources/Database/Schema/PDSSchemaManager.m:132-166`
- Verify: Tests pass after migration

**Step 1: Add schema method**

In `PDSSchemaManager.m`, add after `serviceRefreshTokensTableSchema`:

```objc
- (NSString *)serviceWebAuthnCredentialsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS webauthn_credentials ("
           @"    id TEXT PRIMARY KEY,"
           @"    account_did TEXT NOT NULL,"
           @"    credential_id BLOB NOT NULL,"
           @"    public_key_cose BLOB NOT NULL,"
           @"    sign_count INTEGER DEFAULT 0,"
           @"    aaguid BLOB,"
           @"    created_at REAL NOT NULL,"
           @"    UNIQUE(account_did, credential_id)"
           @")";
}
```

**Step 2: Add to serviceSchemaSQL**

Add to the `serviceSchemaSQL` method, after line 143:
```objc
[sql appendString:[self serviceWebAuthnCredentialsTableSchema]];
[sql appendString:@";\n\n"];
[sql appendString:@"CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_account ON webauthn_credentials(account_did);"];
[sql appendString:@";\n"];
```

**Step 3: Run tests**

Run: `./build/tests/AllTests`
Expected: PASS

**Step 4: Commit**

```bash
git add Garazyk/Sources/Database/Schema/PDSSchemaManager.m
git commit -m "feat: add webauthn_credentials table schema"
```

---

### Task 2: Add WebAuthn credential persistence to PDSDatabase

**Files:**
- Modify: `Garazyk/Sources/Database/PDSDatabase.m`

**Dependencies:** Task 1 complete

**Step 1: Add migration column check**

At line ~640 in PDSDatabase.m (near other ALTER TABLE statements), add:

```objc
[self addColumnIfNeeded:@"accounts" column:@"webauthn_enabled" type:@"INTEGER DEFAULT 0"];
```

**Step 2: Add credential CRUD methods**

Add new methods to PDSDatabase.m for credential persistence. Search for existing patterns like `getAccountByHandle:` to match style.

```objc
- (void)storeWebAuthnCredential:(NSDictionary *)credential forDid:(NSString *)did {
    // INSERT OR REPLACE INTO webauthn_credentials
    // Fields: id (UUID), account_did, credential_id, public_key_cose, sign_count, aaguid, created_at
}

- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did {
    // SELECT * FROM webauthn_credentials WHERE account_did = ?
}

- (void)deleteWebAuthnCredential:(NSString *)credentialId forDid:(NSString *)did {
    // DELETE FROM webauthn_credentials WHERE credential_id = ? AND account_did = ?
}

- (void)updateWebAuthnCredentialSignCount:(NSString *)credentialId forDid:(NSString *)did signCount:(uint32_t)signCount {
    // UPDATE webauthn_credentials SET sign_count = ? WHERE credential_id = ? AND account_did = ?
}
```

**Step 3: Add column for webauthn_credentials account**

Add in PDSDatabase.m schema migration section (~line 640):
```objc
[self addColumnIfNeeded:@"accounts" column:@"webauthn_enabled" type:@"INTEGER DEFAULT 0"];
```

**Step 4: Test persistence**

This is implicitly tested by Task 3 handlers.

**Step 5: Commit**

```bash
git add Garazyk/Sources/Database/PDSDatabase.m
git commit -m "feat: add WebAuthn credential persistence"
```

---

### Task 3: Create WebAuthnRegistrationHandler HTTP endpoints

**Files:**
- Create: `Garazyk/Sources/Auth/WebAuthnRegistrationHandler.m`
- Create: `Garazyk/Sources/Auth/WebAuthnRegistrationHandler.h`
- Modify: `Garazyk/Sources/Network/XrpcHandler.m` (register the handler)
- Test: Create test class

**Dependencies:** Task 2 complete

**Step 1: Create handler interface**

Create `WebAuthnRegistrationHandler.h`:

```objc
#import "Network/HttpHandler.h"

@interface WebAuthnRegistrationHandler : NSObject <HttpHandler>

@property(nonatomic, strong) id<Database> database;
@property(nonatomic, strong) NSString *serverOrigin;

- (instancetype)initWithDatabase:(id<Database>)database serverOrigin:(NSString *)serverOrigin;

@end
```

**Step 2: Create handler implementation**

Create `WebAuthnRegistrationHandler.m`. Implement three endpoints:

1. `POST /auth/webauthn/register/begin` - Issue a challenge
```objc
// Generate 32-byte random challenge
// Store challenge in session (or temporary storage keyed by session)
// Return: { challenge: base64url, rp: { name: "PDS" }, user: { id: did, name: handle }, pubKeyCredParams: [{ type: "public-key", alg: -7 }] }
```

2. `POST /auth/webauthn/register/complete` - Validate attestation, store credential
```objc
// Verify attestation using [WebAuthnVerifier verifyRegistrationResponse:challenge:origin:error:]
// Parse credential data (credentialId, publicKeyCOSE, aaguid, signCount)
// Store in webauthn_credentials table via PDSDatabase
// Mark account as webauthn_enabled
// Return: { success: YES, credentialId: base64 }
```

3. `POST /auth/webauthn/assert` - Verify assertion, issue session
```objc
// Get credential_id from request
// Fetch stored credential from webauthn_credentials
// Verify assertion using [WebAuthnVerifier verifyAssertionResponse:challenge:origin:publicKey:signCount:newSignCount:error:]
// Update sign count
// Return: { success: YES, did: account_did }
```

**Step 3: Register handler in XrpcHandler**

Add handler registration in `XrpcHandler.m` (similar to existing handlers).

**Step 4: Write handler tests**

Create `WebAuthnRegistrationHandlerTests.m`:

```objc
// Test begin endpoint returns valid challenge
// Test complete stores credential
// Test assert verifies valid assertion
// Test assert rejects invalid assertion
// Test assert rejects cloned authenticator (sign count check)
```

**Step 5: Run tests**

Run: `./build/tests/AllTests`
Expected: PASS

**Step 6: Commit**

```bash
git add Garazyk/Sources/Auth/WebAuthnRegistrationHandler.m
git add Garazyk/Sources/Auth/WebAuthnRegistrationHandler.h
git add Garazyk/Tests/Auth/WebAuthnRegistrationHandlerTests.m
git commit -m "feat: add WebAuthn registration HTTP endpoints"
```

---

### Task 4: Integrate WebAuthn into OAuth2 token exchange

**Files:**
- Modify: `Garazyk/Sources/Auth/OAuth2.m:735-760`

**Dependencies:** Task 3 complete

**Step 1: Add webauthn_enabled check**

In `OAuth2.m`, around line 735 (where TOTP MFA is checked), add parallel branch for WebAuthn:

```objc
// Check WebAuthn requirement
if (account.webauthnEnabled && !request.tfaCode) {
    // Check if request has webauthn assertion
    if (!request.webauthnAssertion) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                              code:OAuth2ErrorInteractionRequired
                                          userInfo:@{NSLocalizedDescriptionKey: @"WebAuthn authentication required", @"error": @"webauthn_required"}];
        completion(nil, error);
        return;
    }
    
    // Verify WebAuthn assertion
    // Fetch stored credentials, verify with WebAuthnVerifier
    // If valid, continue to session creation
    // If invalid, return error
}
```

**Step 2: Add WebAuthnVerifier header import**

In `OAuth2.m` imports (line ~16), add:
```objc
#import "Auth/WebAuthnVerifier.h"
```

**Step 3: Run tests**

Ensure existing OAuth2 tests pass, add new test for WebAuthn flow:
```bash
./build/tests/AllTests
```

**Step 4: Commit**

```bash
git add Garazyk/Sources/Auth/OAuth2.m
git commit -m "feat: integrate WebAuthn into OAuth2 token flow"
```

---

### Task 5: Quality gates and push

**Step 1: Generate project**

```bash
xcodegen generate
```

**Step 2: Build AllTests**

```bash
xcodebuild -scheme AllTests build
```

**Step 3: Run tests**

```bash
./build/tests/AllTests
```

**Step 4: Build CLI**

```bash
xcodebuild -scheme ATProtoPDS-CLI build
```

**Step 5: Push**

```bash
git push
```

---

## Summary

This plan adds WebAuthn credential registration endpoints and integrates them into OAuth2:

1. **Schema**: `webauthn_credentials` table
2. **Persistence**: CRUD methods in PDSDatabase
3. **HTTP Handler**: Register/assert endpoints 
4. **OAuth2 Integration**: Alternative to TOTP at ~line 747

**Estimated tasks:** 5 major tasks with ~10-15 commit steps
