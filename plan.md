# Fix Plan: macOS API Bugs and Patterns (GNUstep-Compatible)

## Scope

Fix 23 issues across 8 source files identified in the critique. Every fix is annotated
with its platform scope. The codebase uses `#if defined(GNUSTEP)` / `#if !defined(__APPLE__)`
gates; all new platform-conditional code follows the same convention.

---

## Phase 1 — Cross-Platform Fixes (no new guards required)

These changes use only Foundation and CommonCrypto, both available on GNUstep.

---

### 1.1 Consolidate duplicated base64URL implementations

**Why:** Three independent encode/decode implementations exist:
- `PDSBase64URLStringFromData()` static function in `Auth/PDSAppleKeyManager.m`
- `+base64URLEncodeData:error:` / `+base64URLDecode:error:` in `Auth/JWT.m`
- `+base64URLEncode:` / `+base64URLDecode:` in `Auth/CryptoUtils.m`

Divergent implementations risk subtle differences in padding handling.

**What to change:**

`Auth/CryptoUtils.h` / `Auth/CryptoUtils.m`:
- The existing `+base64URLEncode:` / `+base64URLDecode:` are the canonical implementations.
  No changes to these methods.

`Auth/JWT.m`:
- Delete `+base64URLEncodeData:error:` and `+base64URLDecode:error:` class methods.
- Replace all internal call sites with `[CryptoUtils base64URLEncode:]` and
  `[CryptoUtils base64URLDecode:]`.

`Auth/PDSAppleKeyManager.m`:
- Delete `PDSBase64URLStringFromData()` static function.
- Replace the two call sites in `publicKeyJWK` and `publicKeyThumbprint` with
  `[CryptoUtils base64URLEncode:]`.

**GNUstep:** `CryptoUtils` uses only `NSString`/`NSData` Foundation APIs. No guards needed.

---

### 1.2 Fix null-buffer `CC_SHA256` crash in `AppView/FeedService.m`

**Why:** Two calls pass `nil` as the output buffer to `CC_SHA256`, which writes 32 bytes
into a null pointer — undefined behaviour / crash.

**`generateCIDForRecord:` (line ~527):**

Replace:
```objc
const unsigned char *hashBuffer = CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, nil);
```
With:
```objc
unsigned char hash[CC_SHA256_DIGEST_LENGTH];
CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, hash);
```
Then iterate `hash[i]` instead of `hashBuffer[i]`.

**`generateRkey` (line ~540):**

The existing code calls `[NSUUID UUID].UUIDString` twice, producing two different UUIDs —
one whose string is hashed, a different one. Fix both bugs together:

Replace:
```objc
const unsigned char *hashBuffer = CC_SHA256([[NSUUID UUID].UUIDString UTF8String],
                                            (CC_LONG)[[NSUUID UUID].UUIDString length], nil);
```
With:
```objc
NSString *uuidStr = [NSUUID UUID].UUIDString;
unsigned char hash[CC_SHA256_DIGEST_LENGTH];
CC_SHA256(uuidStr.UTF8String, (CC_LONG)[uuidStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding], hash);
```

**GNUstep:** CommonCrypto is available on GNUstep. No guards needed.

---

### 1.3 Fix JWT audience validation (RFC 7519 §4.1.3)

**Why:** `validateClaims:ofJWT:error:` silently accepts tokens that have no `aud` claim when
`expectedAudience` is configured. RFC 7519 requires rejection of such tokens.

**File:** `Auth/JWT.m` `validateClaims:ofJWT:error:`

Change:
```objc
if (self.expectedAudience && payload.aud &&
    ![payload.aud isEqualToString:self.expectedAudience]) {
```
To:
```objc
if (self.expectedAudience &&
    ![payload.aud isEqualToString:self.expectedAudience]) {
```

The `nil` string will never `isEqualToString:` a non-nil expected audience, so the check
fires correctly when `payload.aud` is nil.

**GNUstep:** Pure Foundation logic. No guards needed.

---

### 1.4 Fix `mintAccessTokenForDID:` / `mintRefreshTokenForDID:` error propagation

**Why:** Lines 551 and 583 build the signing input as a nested inline expression. If any
intermediate call returns nil (e.g. `dataWithJSONObject:` fails), the nil is coerced to `@""`
by the ternary operator and the `error` out-pointer is silently overwritten by the next call.

**File:** `Auth/JWT.m` `mintAccessTokenForDID:handle:scopes:dpopKeyThumbprint:error:` and
`mintRefreshTokenForDID:handle:scopes:error:`

Break lines 551 and 583 into explicit steps:

```objc
NSData *headerData = [NSJSONSerialization dataWithJSONObject:[header toDictionary]
                                                     options:0
                                                       error:error];
if (!headerData) return nil;

NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[payload toDictionary]
                                                      options:0
                                                        error:error];
if (!payloadData) return nil;

NSString *headerEncoded  = [CryptoUtils base64URLEncode:headerData];
NSString *payloadEncoded = [CryptoUtils base64URLEncode:payloadData];
NSString *signingInput   = [NSString stringWithFormat:@"%@.%@", headerEncoded, payloadEncoded];

NSData *signatureData = [self signData:signingInput error:error];
if (!signatureData) return nil;

NSString *signature = [CryptoUtils base64URLEncode:signatureData];
```

**GNUstep:** No platform guards needed.

---

### 1.5 Remove unused `error` parameter from `+base64URLEncodeData:error:`

**Why:** The method never populates `error` and cannot fail. The parameter misleads callers
into checking an error that is never set.

**Note:** After Fix 1.1 removes `+base64URLEncodeData:error:` from `JWT.m`, this fix is
automatically resolved as a side effect.

---

### 1.6 Make `clockOffset` functional in `JWTVerifier`

**Why:** `_clockOffset` is set to `[NSDate date]` in `init` but `validateClaims:` ignores it,
always using `[NSDate date]` directly. This makes clock-skew tolerance and test-time injection
impossible.

**File:** `Auth/JWT.m` `JWTVerifier`

In `validateClaims:ofJWT:error:`, replace:
```objc
NSDate *now = [NSDate date];
```
With:
```objc
NSDate *now = self.clockOffset ?: [NSDate date];
```

Update `init` to set `_clockOffset = nil` (meaning "use real clock"), so callers that want
clock injection set it explicitly. Remove the pointless `_clockOffset = [NSDate date]` in init.

Update the public header comment to document this: when `clockOffset` is non-nil it is used as
the reference time for `exp`/`nbf` validation.

**GNUstep:** No platform guards needed.

---

### 1.7 Fix misplaced doc comment in `Auth/CryptoUtils.m`

**Why:** The `@method hexStringFromData:` documentation block is attached to `+base64URLEncode:`
(line 107). The actual `+hexStringFromData:` is at line 139 with no doc comment.

**File:** `Auth/CryptoUtils.m`

- Move the `/*! @method hexStringFromData: ... */` comment block from above `+base64URLEncode:`
  to above `+hexStringFromData:`.
- Add a correct doc comment for `+base64URLEncode:`.

**GNUstep:** Comment-only change. No platform guards needed.

---

### 1.8 Collapse redundant `#if` branches in `App/AppDelegate.m`

**Why:** Lines 24–28 and 61–65 have `#if` / `#else` branches that execute identical code in
both arms — the preprocessor condition achieves nothing.

**File:** `App/AppDelegate.m`

Remove the inner `#if !defined(GNUSTEP) && ...` / `#else` / `#endif` wrappers around the
`PDS_LOG_ERROR_C` calls, leaving a single unconditional log statement.

**GNUstep:** The file is already excluded on non-Apple targets by the outer AppKit guard, so
this is safe either way. No new guards needed.

---

## Phase 2 — Apple-Only Fixes (Security.framework, AppKit, Network.framework)

All changes in this phase are inside existing `#if !defined(GNUSTEP)` or `#if defined(__APPLE__)`
blocks. GNUstep code paths are untouched.

---

### 2.1 Fix `PDSBiometricKeychain`: use `SecItemUpdate` instead of delete-then-add

**Why:** When `errSecDuplicateItem` is returned from `SecItemAdd`, the current code calls
`SecItemDelete` then `SecItemAdd`. Between these two calls the item does not exist — a race
window. `SecItemUpdate` is atomic.

**File:** `Security/PDSBiometricKeychain.m` `storeKey:forAccount:error:`

Replace the `errSecDuplicateItem` handling block:
```objc
// BEFORE (racy)
if (status == errSecDuplicateItem) {
    SecItemDelete((__bridge CFDictionaryRef)query);
    status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}
```

With a `SecItemUpdate` call using a search-only query (no `kSecValueData` / `kSecReturnData`
in the search dictionary):
```objc
if (status == errSecDuplicateItem) {
    NSMutableDictionary *searchQuery = [self baseQueryForAccount:account];
    NSDictionary *updateAttrs = @{ (__bridge id)kSecValueData: keyData };
    status = SecItemUpdate((__bridge CFDictionaryRef)searchQuery,
                           (__bridge CFDictionaryRef)updateAttrs);
}
```

The search query must not contain `kSecValueData`, `kSecReturnData`, or `kSecAttrAccessControl`
(access control cannot be updated after creation).

---

### 2.2 Remove conflicting `kSecAttrAccessible` when `kSecAttrAccessControl` is set

**Why:** Apple's documentation says these two keys must not both be present. When biometrics
are used, accessibility is encoded inside the `SecAccessControlRef`.

**File:** `Security/PDSBiometricKeychain.m` `storeKey:forAccount:error:`

The `kSecAttrAccessible` line is currently set unconditionally before the `if (self.useBiometrics)`
block. Restructure:

```objc
if (self.useBiometrics) {
    SecAccessControlRef accessControl = [self createAccessControlWithError:error];
    if (!accessControl) return NO;
    query[(__bridge id)kSecAttrAccessControl] = (__bridge_transfer id)accessControl;
    // Do NOT set kSecAttrAccessible — it conflicts with kSecAttrAccessControl
} else {
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
}
```

Also note: `(__bridge id)accessControl` followed by `CFRelease(accessControl)` can be replaced
with `(__bridge_transfer id)accessControl` which transfers ownership cleanly.

---

### 2.3 Fix `@available` version for `kSecAccessControlBiometryCurrentSet`

**Why:** `kSecAccessControlBiometryCurrentSet` was introduced in macOS 10.13, not 12.0.
The wrong version gate causes every device on macOS 10.13–11.x to use the weaker
`BiometryAny` policy unnecessarily.

**File:** `Security/PDSBiometricKeychain.m` `createAccessControlWithError:`

Since the project requires macOS 14+, drop the availability check entirely and use
`kSecAccessControlBiometryCurrentSet` unconditionally:

```objc
// BEFORE
if (@available(macOS 12.0, *)) {
    flags = kSecAccessControlBiometryCurrentSet;
} else {
    flags = kSecAccessControlBiometryAny;
}
```

```objc
// AFTER (macOS 14+ deployment target)
SecAccessControlCreateFlags flags = kSecAccessControlBiometryCurrentSet;
```

Same fix applies to `createAuthenticationContextWithError:` — the `@available(macOS 12.0, *)`
check around `LAPolicyDeviceOwnerAuthenticationWithBiometrics` is also overcautious:
`LAPolicyDeviceOwnerAuthenticationWithBiometrics` has been available since macOS 10.12.
Drop the version gate and call `canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics`
directly.

---

### 2.4 Remove invalid `kSecAttrType` string from keychain queries

**Why:** `kSecAttrType` expects a `CFNumberRef` encoding a `FourCharCode`, not an `NSString`.
Passing an `NSString` here is silently dropped or causes `errSecParam` on some OS versions.

**File:** `Security/PDSBiometricKeychain.m` `baseQueryForAccount:`

Remove:
```objc
query[(__bridge id)kSecAttrType] = kKeyType;
```

If the intent is to tag items for later enumeration or identification, use `kSecAttrLabel`
instead, which accepts an `NSString`:
```objc
query[(__bridge id)kSecAttrLabel] = kKeyType;
```

Update the constant name to reflect its new role (`kKeyLabel` or similar).

---

### 2.5 Add `kSecUseAuthenticationUISkip` to existence checks

**Why:** Calling `SecItemCopyMatching` on a biometrically-protected item without specifying UI
behaviour can trigger an unwanted biometric prompt merely to check if the item exists.

**File:** `Security/PDSBiometricKeychain.m`

In `keyExistsForAccount:`, add:
```objc
query[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUISkip;
```

In `upgradeExistingKeysWithAccounts:`, the existence check on line 170 calls
`keyExistsForAccount:` which will gain this fix automatically. The subsequent
`SecItemCopyMatching` on line 178 (to read the key data for the upgrade) should add
`kSecUseAuthenticationContext` with a fresh `LAContext` to avoid a headless UI prompt:
```objc
LAContext *ctx = [[LAContext alloc] init];
oldQuery[(__bridge id)kSecUseAuthenticationContext] = ctx;
```

`kSecUseAuthenticationUISkip` / `kSecUseAuthenticationUI` are available macOS 10.11+.
No availability guard needed (project requires macOS 14).

---

### 2.6 Fix `PDSAppleKeyManager`: remove dead `pubError` code

**Why:** `SecKeyCopyPublicKey` has no `CFErrorRef *` output parameter. `pubError` is declared
but can never be set; the `if (pubError)` branch is unreachable dead code. A real nil return
from `SecKeyCopyPublicKey` goes undetected.

**File:** `Auth/PDSAppleKeyManager.m` `generateKeyPairWithAlgorithm:keySize:error:` (~line 237)

Replace:
```objc
CFErrorRef pubError = NULL;
SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
if (pubError) {
    CFRelease(privateKey);
    if (error) { *error = CFBridgingRelease(pubError); }
    return nil;
}
```

With:
```objc
SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
if (!publicKey) {
    CFRelease(privateKey);
    if (error) {
        *error = [NSError errorWithDomain:KeyManagerErrorDomain
                                     code:KeyManagerErrorKeyGenerationFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive public key"}];
    }
    return nil;
}
```

---

### 2.7 Fix `currentKeyID` data race in `PDSAppleKeyManager`

**Why:** `self.currentKeyID = keyID` on line 260 is written outside `accessQueue`, while
`getActiveKeyPair:` reads `currentKeyID` without dispatch protection — a data race.

**File:** `Auth/PDSAppleKeyManager.m`

In `generateKeyPairWithAlgorithm:keySize:error:`, move the assignment inside the queue block:
```objc
dispatch_sync(self.accessQueue, ^{
    self.keyPairs[keyID] = keyPair;
    self.currentKeyID = keyID;   // moved here
});
// Remove the standalone self.currentKeyID = keyID line
```

In `loadKeysFromDatabase`, the existing `dispatch_sync` block already sets `self.currentKeyID`
on line 582 — that assignment is correctly placed. Verify no other out-of-queue mutation exists.

In `setKeyPairActive:error:`, `self.currentKeyID = keyID` on line 385 is already inside
`dispatch_sync` — correct.

---

### 2.8 Fix JWK emission to support EC keys in `PDSAppleKeyManager`

**Why:** `publicKeyJWK` always emits `kty: RSA` and the RSA fields `n`/`e` regardless of
actual key type. EC key external representation is an X9.63 point `04 || X || Y`, not an RSA
modulus — the JWK is wrong for any non-RSA key.

**File:** `Auth/PDSAppleKeyManager.m` `publicKeyJWK`

Branch on `self.algorithm`:

```objc
- (nullable NSDictionary *)publicKeyJWK {
    NSData *keyData = [self exportPublicKeyData:self.publicKey];
    if (!keyData) return nil;

    NSMutableDictionary *jwk = [NSMutableDictionary dictionary];
    jwk[@"kid"] = self.keyID;
    jwk[@"use"] = @"sig";

    if ([self.algorithm hasPrefix:@"RS"]) {
        // RSA: DER-encoded SubjectPublicKeyInfo; SecKeyCopyExternalRepresentation
        // returns PKCS#1 DER for RSA keys. Parse modulus (n) and exponent (e).
        // For brevity: n is the raw modulus bytes, e is typically 65537 (AQAB).
        jwk[@"kty"] = @"EC";       // placeholder — see full parsing below
        // Full implementation: parse ASN.1 DER to extract n and e bytes
        // then base64url-encode each. This is ~40 lines of DER parsing.
        // Use the existing exportPublicKeyData result which is PKCS#1 RSA for RSA keys.
        jwk[@"kty"] = @"RSA";
        jwk[@"alg"] = self.algorithm;
        // Parse DER to get n and e — see implementation note below
    } else {
        // EC (ES256 = P-256, ES256K = secp256k1): 65-byte uncompressed point 04||X||Y
        if (keyData.length != 65 || ((const uint8_t *)keyData.bytes)[0] != 0x04) return nil;
        NSData *xData = [keyData subdataWithRange:NSMakeRange(1, 32)];
        NSData *yData = [keyData subdataWithRange:NSMakeRange(33, 32)];
        jwk[@"kty"] = @"EC";
        jwk[@"alg"] = self.algorithm;
        jwk[@"crv"] = [self.algorithm isEqualToString:@"ES256K"] ? @"secp256k1" : @"P-256";
        jwk[@"x"]   = [CryptoUtils base64URLEncode:xData];
        jwk[@"y"]   = [CryptoUtils base64URLEncode:yData];
    }
    return [jwk copy];
}
```

**RSA DER parsing note:** `SecKeyCopyExternalRepresentation` for RSA returns a PKCS#1
`RSAPublicKey` DER structure (`SEQUENCE { INTEGER n, INTEGER e }`). Parse the ASN.1 manually
(~35 lines) or add a small helper `parseRSAPublicKeyDER:modulus:exponent:`. The exponent is
almost always `[0x01, 0x00, 0x01]` (65537) which base64url-encodes to `AQAB`.

---

### 2.9 Fix JWK thumbprint RFC 7638 canonical JSON

**Why:** RFC 7638 §3 requires hashing a minimal, **lexicographically sorted** JSON object
containing only the required members. `NSDictionary` serialisation does not guarantee key order.

**File:** `Auth/PDSAppleKeyManager.m` `publicKeyThumbprint`

Build the canonical JSON string manually without a dictionary:

```objc
- (nullable NSString *)publicKeyThumbprint {
    // Build canonical JSON as per RFC 7638 §3
    NSData *keyData = [self exportPublicKeyData:self.publicKey];
    if (!keyData) return nil;

    NSString *canonical = nil;

    if ([self.algorithm hasPrefix:@"RS"]) {
        // Required members in lex order: e, kty, n
        // Parse n and e from DER (see 2.8 helper)
        NSString *eStr = ...; // base64url of exponent bytes
        NSString *nStr = ...; // base64url of modulus bytes
        canonical = [NSString stringWithFormat:
            @"{\"e\":\"%@\",\"kty\":\"RSA\",\"n\":\"%@\"}", eStr, nStr];
    } else {
        // Required members in lex order: crv, kty, x, y
        if (keyData.length != 65) return nil;
        NSString *crv = [self.algorithm isEqualToString:@"ES256K"] ? @"secp256k1" : @"P-256";
        NSString *xStr = [CryptoUtils base64URLEncode:[keyData subdataWithRange:NSMakeRange(1,  32)]];
        NSString *yStr = [CryptoUtils base64URLEncode:[keyData subdataWithRange:NSMakeRange(33, 32)]];
        canonical = [NSString stringWithFormat:
            @"{\"crv\":\"%@\",\"kty\":\"EC\",\"x\":\"%@\",\"y\":\"%@\"}", crv, xStr, yStr];
    }

    NSData *canonicalData = [canonical dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [CryptoUtils sha256:canonicalData];
    return [CryptoUtils base64URLEncode:hash];
}
```

No `NSJSONSerialization` involved — no key ordering ambiguity.

---

### 2.10 Fix legacy key import hardcoded `kSecAttrKeyTypeRSA`

**Why:** `loadKeysFromDatabase` imports private key data with `kSecAttrKeyTypeRSA` regardless
of the stored algorithm. EC keys will fail to import silently.

**File:** `Auth/PDSAppleKeyManager.m` `loadKeysFromDatabase` (~line 545)

Replace:
```objc
NSDictionary *privateKeyAttrs = @{
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate
};
```

With:
```objc
CFTypeRef privateKeyType = [algorithm hasPrefix:@"RS"]
    ? kSecAttrKeyTypeRSA
    : kSecAttrKeyTypeECSECPrimeRandom;
NSDictionary *privateKeyAttrs = @{
    (__bridge id)kSecAttrKeyType:  (__bridge id)privateKeyType,
    (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate
};
```

This mirrors the public key import on line 559 which already does this correctly.

---

### 2.11 Fix `signPayload:withKeyID:error:` JWT signing input

**Why:** The `PDSAppleKeyManager` implementation signs the raw JSON payload bytes rather than
the correct JWT signing input (`base64url(header) || "." || base64url(payload)`). The parallel
`PDSOpenSSLSessionKeyManager` implementation is correct. The `PDSAppleKeyManager` version
must match.

**File:** `Auth/PDSAppleKeyManager.m` `signPayload:withKeyID:error:`

Rewrite to mirror `PDSOpenSSLSessionKeyManager`:

```objc
- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error {
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) return nil;

    NSDictionary *headerDict = @{ @"alg": self.algorithm ?: @"RS256",
                                  @"typ": @"JWT",
                                  @"kid": keyID };
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerDict options:0 error:error];
    if (!headerData) return nil;

    NSString *headerB64  = [CryptoUtils base64URLEncode:headerData];
    NSString *payloadB64 = [CryptoUtils base64URLEncode:payloadData];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *inputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    NSData *signature = [self signData:inputData withKeyID:keyID error:error];
    if (!signature) return nil;

    NSString *sigB64 = [CryptoUtils base64URLEncode:signature];
    return @{ @"token": [NSString stringWithFormat:@"%@.%@", signingInput, sigB64] };
}
```

---

### 2.12 Replace deprecated `NSImageNameNetwork` in `AppDelegate.m`

**Why:** `NSImageNameNetwork` was deprecated in macOS 12. The project requires macOS 14,
so the SF Symbols replacement is unconditionally available.

**File:** `App/AppDelegate.m` `setupStatusBar`

Replace:
```objc
self.statusItem.button.image = [NSImage imageNamed:NSImageNameNetwork];
```
With:
```objc
self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"network"
                                         accessibilityDescription:@"PDS Server"];
```

---

### 2.13 Add server failure feedback to the macOS menu bar app

**Why:** When `startServerWithError:` fails, only a log entry is written. The user sees no
visual indication in the running menu bar app.

**File:** `App/AppDelegate.m` `applicationDidFinishLaunching:`

After the failed start:
```objc
if (![self.pdsController startServerWithError:&error]) {
    PDS_LOG_ERROR_C(PDSLogComponentCore, @"Failed to start server: %@", error);
    // Update status item to indicate failure
    self.statusItem.button.title = @"PDS ✗";
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"network.slash"
                                             accessibilityDescription:@"PDS Server (offline)"];
    // Show a non-modal alert (doesn't block startup path)
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText    = @"PDS Server Failed to Start";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    alert.alertStyle     = NSAlertStyleCritical;
    [alert runModal];
}
```

---

### 2.14 Fix `PDSNetworkTransportMac`: set queue before state handler registration

**Why:** When `PDSNetworkConnectionMac` is initialized from an incoming `nw_connection_t`
(new connection from the listener), `setupHandlers` registers the state-changed handler but
no queue has been set yet. Network.framework requires a queue before it can deliver events;
any state transition between init and the caller's `startWithQueue:` call has undefined dispatch.

**File:** `Network/PDSNetworkTransportMac.m` `initWithConnection:`

Set a default queue before `setupHandlers`:
```objc
- (instancetype)initWithConnection:(nw_connection_t)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        // Set a default queue so handlers can fire immediately if the
        // connection transitions before startWithQueue: is called.
        nw_connection_set_queue(_connection,
            dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
        [self setupHandlers];
    }
    return self;
}
```

`startWithQueue:` already calls `nw_connection_set_queue` to reassign the definitive queue;
the double-set is safe (Network.framework allows it before `nw_connection_start`).

---

## Phase 3 — AES-GCM Upgrade (cross-platform, platform-conditional implementation)

### Context

`CryptoUtils +encryptData:withKey:` / `+decryptData:withKey:` use AES-256-CBC with PKCS7
padding and no authentication tag. CBC is malleable and vulnerable to padding oracle attacks.
The functions are used to encrypt private keys at rest in:

- `Database/ActorStore/ActorStore.m` — persists to SQLite
- `PLC/PLCRotationKeyManager.m` — persists to SQLite

Because encrypted data is stored persistently, the new format must coexist with existing
CBC-encrypted rows during the transition.

---

### 3.1 Versioned ciphertext format

**Current format:** `IV(16) || ciphertext`

**New format:** `version(1) || nonce(12) || tag(16) || ciphertext`

**Migration tag for legacy data:** The existing CBC format has no version byte.
A version prefix byte is added:

| Version byte | Format |
|---|---|
| `0x01` | Legacy: `IV(16) \|\| CBC-ciphertext` (decrypt only) |
| `0x02` | New: `nonce(12) \|\| tag(16) \|\| GCM-ciphertext` |

`decryptData:withKey:` reads the first byte. If it's `0x01` (or the buffer starts with a
16-byte IV that could be legacy data — see transition strategy below), it falls back to CBC.
Otherwise it uses GCM.

**Transition strategy:** Existing CBC-encrypted rows have no version prefix, so their first
byte is part of the raw IV (random, any value). To distinguish them from version-tagged rows:

Option A (cleanest): Add a migration step that re-encrypts all existing rows with GCM when the
server starts. `ActorStore` and `PLCRotationKeyManager` already have their decryption key
available at startup — re-encrypt in a transaction and update the rows.

Option B (simpler): Treat a first byte of `0x02` as versioned GCM; all other values as legacy
CBC. Since the IV is random, only 1/256 of legacy rows would have a `0x02` first byte — add
a secondary heuristic (e.g. check length ≥ 29 for GCM vs ≥ 17 for CBC).

**Recommended:** Option A (one-time migration on first startup with new binary).

---

### 3.2 Implement AES-256-GCM in `CryptoUtils`

**File:** `Auth/CryptoUtils.m`

Use platform-conditional code. Both branches have the same function signature.

**Apple platform (`#if defined(__APPLE__)`):**

Use `CCCryptorGCMOneshotEncrypt` / `CCCryptorGCMOneshotDecrypt` from CommonCrypto.
These are declared in `<CommonCrypto/CommonCryptorSPI.h>` (semi-private) but stable since
macOS 10.9. Alternatively, use the public `CCCryptorGCM` multi-step API available in
`<CommonCrypto/CommonCryptor.h>`:

```c
// Pseudo-code for the multi-step public API:
CCCryptorRef cref;
CCCryptorCreateWithMode(kCCEncrypt, kCCModeGCM, kCCAlgorithmAES, 0,
                        NULL, key, 32, NULL, 0, 0, 0, &cref);
CCCryptorGCMAddIV(cref, nonce, 12);
// (no AAD in this use case)
CCCryptorGCMEncrypt(cref, plaintext, len, ciphertext);
CCCryptorGCMFinal(cref, tag, &tagLen);
CCCryptorRelease(cref);
```

**GNUstep / Linux (`#else`):**

Use OpenSSL EVP AES-256-GCM (already a dependency via secp256k1):

```c
#include <openssl/evp.h>

EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, key, nonce);
EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, plaintextLen);
EVP_EncryptFinal_ex(ctx, ciphertext + len, &finalLen);
EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
EVP_CIPHER_CTX_free(ctx);
```

**Updated `encryptData:withKey:`:**
```objc
+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != 32) return nil;

    // Generate 12-byte random nonce
    NSMutableData *nonce = [NSMutableData dataWithLength:12];
    if (SecRandomCopyBytes(kSecRandomDefault, 12, nonce.mutableBytes) != errSecSuccess)
        return nil;

    // Allocate output: version(1) + nonce(12) + tag(16) + ciphertext
    NSMutableData *output = [NSMutableData dataWithLength:1 + 12 + 16 + data.length];
    uint8_t *outBytes = output.mutableBytes;
    outBytes[0] = 0x02; // GCM version tag
    memcpy(outBytes + 1, nonce.bytes, 12);
    // tag goes at outBytes+13, ciphertext at outBytes+29
    // ... platform-specific GCM encrypt writes into those offsets ...
    return output;
}
```

**Updated `decryptData:withKey:`:**
```objc
+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != 32 || data.length < 1) return nil;

    const uint8_t *bytes = data.bytes;
    if (bytes[0] == 0x02) {
        // GCM path: nonce(12) + tag(16) + ciphertext
        if (data.length < 1 + 12 + 16) return nil;
        // ... platform-specific GCM decrypt with tag verification ...
    } else {
        // Legacy CBC fallback: raw IV(16) + ciphertext (original format, no version byte)
        if (data.length < 16) return nil;
        return [self legacyCBCDecryptData:data withKey:key];
    }
}
```

Extract the existing CBC decrypt logic into a private `+legacyCBCDecryptData:withKey:` helper.

**GNUstep note:** `SecRandomCopyBytes` is Apple-only. On GNUstep, use `getrandom(2)` or
`/dev/urandom` for nonce generation. Add a `+secureRandomBytes:` private helper in
`CryptoUtils` with a `#if defined(__APPLE__)` / `#else` branch:

```objc
+ (nullable NSData *)secureRandomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
#if defined(__APPLE__)
    if (SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes) != errSecSuccess)
        return nil;
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return nil;
    ssize_t n = read(fd, data.mutableBytes, length);
    close(fd);
    if (n != (ssize_t)length) return nil;
#endif
    return data;
}
```

The existing `+randomBytes:` already calls `SecRandomCopyBytes` on Apple. On GNUstep,
`SecRandomCopyBytes` is presumably shimmed via the OpenSSL compat layer. If the existing
`+randomBytes:` works on GNUstep already, use it for the nonce; otherwise use the helper above.

---

### 3.3 One-time migration on startup (Option A)

**Files:** `Database/ActorStore/ActorStore.m`, `PLC/PLCRotationKeyManager.m`

Add a migration method called from the server startup path (after the database is open but
before the server accepts requests):

1. Select all rows with encrypted key data.
2. For each row, call `decryptData:withKey:` (which will use the legacy CBC path via the
   version-byte fallback).
3. Re-encrypt with the new `encryptData:withKey:` (which now writes GCM).
4. Update the row in a single SQLite transaction.

This is a one-time, idempotent operation (rows already in GCM format will have `0x02` as
the first byte and decrypt correctly without touching the migration path).

---

## Implementation Order

| Order | Fix | Phase | Risk |
|---|---|---|---|
| 1 | 1.2 — null buffer CC_SHA256 crash | 1 | Low |
| 2 | 1.3 — JWT aud validation | 1 | Low |
| 3 | 1.1 — Consolidate base64URL | 1 | Medium (many call sites) |
| 4 | 1.4 — mintAccessToken error handling | 1 | Low |
| 5 | 1.6 — clockOffset functional | 1 | Low |
| 6 | 1.7 — doc comment | 1 | Trivial |
| 7 | 1.8 — AppDelegate redundant #if | 1 | Trivial |
| 8 | 2.6 — pubError dead code | 2 | Low |
| 9 | 2.7 — currentKeyID data race | 2 | Low |
| 10 | 2.4 — kSecAttrType string | 2 | Low |
| 11 | 2.3 — @available version | 2 | Low |
| 12 | 2.2 — kSecAttrAccessible conflict | 2 | Medium |
| 13 | 2.1 — SecItemUpdate | 2 | Medium |
| 14 | 2.5 — kSecUseAuthenticationUISkip | 2 | Low |
| 15 | 2.10 — legacy key type import | 2 | Low |
| 16 | 2.8 — JWK EC emission | 2 | Medium |
| 17 | 2.9 — JWK thumbprint canonical | 2 | Medium |
| 18 | 2.11 — signPayload signing input | 2 | Medium |
| 19 | 2.12 — NSImageNameNetwork | 2 | Trivial |
| 20 | 2.13 — server failure alert | 2 | Low |
| 21 | 2.14 — nw queue before handler | 2 | Low |
| 22 | 3.1/3.2 — AES-GCM implementation | 3 | High |
| 23 | 3.3 — migration | 3 | High |

---

## GNUstep Compatibility Checklist

| Fix | GNUstep impact |
|---|---|
| All Phase 1 | No guards needed — Foundation + CommonCrypto only |
| All Phase 2 | Already inside `#if !defined(GNUSTEP)` blocks; no GNUstep code touched |
| 3.1 / 3.2 | New `#if defined(__APPLE__)` / `#else` block in `CryptoUtils.m`; GNUstep uses OpenSSL EVP |
| 3.3 migration | Calls `decryptData:` / `encryptData:` — same cross-platform methods; no guards needed |
| `secureRandomBytes:` helper | `#if defined(__APPLE__)` for `SecRandomCopyBytes`, `/dev/urandom` on GNUstep |
