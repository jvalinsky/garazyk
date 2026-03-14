# Test Coverage Plan — ATProtoPDS

**Goal:** 100% source-file coverage (every `.m` has at least one test file exercising it).

**Current state:** 119/185 source files covered (~64%). 66 files have no test at all.
Additionally, several *existing* test files have gaps for code recently modified.

**Framework:** XCTest, with a custom runner in `Tests/test_main.m` that supports both macOS and GNUstep. All new test files must follow the existing `#ifdef __APPLE__` / `#else … "Compat/XCTest/XCTest.h"` include guard pattern from `PLCRotationKeyManagerTests.m`.

---

## Part 1 — Gaps in existing test files

These are targeted additions to test files that already exist, covering code we
recently changed.

### 1.1 `Tests/Auth/CryptoTests.m`

`CryptoTests.m` currently only tests `sha256`, `hmacSHA1`, `hmacSHA256`,
`randomBytes`, and `constantTimeCompare`. The entire encryption/decryption surface
is untested.

**Add:**

| Test method | What it covers |
|---|---|
| `testEncryptDecryptRoundTrip` | GCM round-trip: `encryptData:withKey:` produces a ciphertext starting with version byte `0x02`; `decryptData:withKey:` recovers the plaintext |
| `testEncryptDecryptDifferentCiphertexts` | Two encryptions of the same plaintext produce different ciphertexts (random nonce) |
| `testDecryptRejectsTamperedTag` | Flip one byte in the tag bytes (positions 13–28); decryption must return `nil` |
| `testDecryptRejectsTamperedCiphertext` | Flip a byte in the ciphertext body; decryption must return `nil` |
| `testDecryptLegacyCBCVersioned` | Craft a blob with version byte `0x01` followed by a 16-byte IV and CBC ciphertext; `decryptData:withKey:` must recover the plaintext |
| `testDecryptLegacyCBCUnversioned` | Craft a raw 16-byte-IV + CBC blob with no version byte; `decryptData:withKey:` must recover the plaintext (backward compat for pre-migration blobs) |
| `testBase64URLEncodeMatchesRFC` | Known vector: SHA-256("") encodes as `47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU` |
| `testBase64URLDecodeRoundTrip` | Encode 32 random bytes, decode, assert equality |
| `testBase64URLDecodeRejectsInvalidInput` | Non-base64url strings must return `nil` |
| `testDeriveKeyFromPasswordLength` | `deriveKeyFromPassword:salt:` returns 32 bytes |
| `testDeriveKeyDeterminism` | Same password + salt always produces same key |
| `testDeriveKeyDifferentSalts` | Same password, different salts produce different keys |

### 1.2 `Tests/Auth/JWTTests.m`

`testJWTVerificationWithWrongAudience` exists but does not test the case where
the token contains **no `aud` claim at all** while `expectedAudience` is set (the
RFC 7519 §4.1.3 fix from this review cycle).

**Add:**

| Test method | What it covers |
|---|---|
| `testJWTVerificationRejectsMissingAudience` | Mint a token with no `aud` key in payload; verify with `expectedAudience = "test.audience"` set; must return `NO` with an error |
| `testJWTVerificationAllowsMissingAudienceWhenNotRequired` | Same token, but `expectedAudience = nil`; must return `YES` |
| `testMintAccessTokenForDIDProducesValidJWT` | Call `mintAccessTokenForDID:` on a configured `JWTMinter`; result must be a valid 3-part JWT string |
| `testMintRefreshTokenForDIDProducesValidJWT` | Same for `mintRefreshTokenForDID:` |
| `testClockOffsetShiftsExpiry` | Set `clockOffset` to a future date; a token expired in real-time must still verify |

### 1.3 `Tests/AppView/FeedServiceTests.m`

`generateCIDForRecord:` and `generateRkey` are private helpers that are only
reachable through a test-expose category or by making them `+ (NSString *)` class
methods accessible via a `@testable` header trick. The simplest approach for
Objective-C is to add a `FeedService+Testing` category declared only inside the
test file.

**Add:**

| Test method | What it covers |
|---|---|
| `testGenerateCIDForRecordProducesConsistentHash` | Same NSDictionary input always produces the same CID string |
| `testGenerateCIDForRecordProducesBafkreiPrefix` | Result starts with `"bafkrei"` |
| `testGenerateCIDForRecordDifferentInputsDifferentCIDs` | Different dictionaries produce different CIDs |
| `testGenerateRkeyIsHexString` | Result is lowercase hex, length 32 |
| `testGenerateRkeyIsUnique` | Two consecutive calls produce different strings |

### 1.4 `Tests/PLC/PLCRotationKeyManagerTests.m`

The lazy CBC→GCM migration path added in this review cycle has no tests.

**Add:**

| Test method | What it covers |
|---|---|
| `testLoadMigratesCBCEncryptedKeyToGCM` | Write a file containing a version-byte `0x01` CBC blob; call `loadOrGenerateKeyWithError:`; verify the manager loads the key correctly, and that the file on disk is now GCM-formatted (first byte `0x02`) |
| `testLoadMigratesLegacyUnversionedCBCToGCM` | Same for a raw CBC blob without a version byte |
| `testLoadAlreadyGCMKeyDoesNotRewrite` | Write a file containing a real GCM-encrypted blob; call load; verify the file is unchanged (no unnecessary re-write) |

### 1.5 `Tests/Database/ActorStore/ActorStoreTests.m`

**Add:**

| Test method | What it covers |
|---|---|
| `testRotationKeyMigratesCBCToGCM` | Store a rotation key row by injecting a CBC-formatted `encrypted_private_key` blob directly via SQLite; call `rotationKeyDecryptedWithPassword:error:`; verify: (1) the plaintext key is returned correctly, (2) the stored blob is now GCM-formatted |

---

## Part 2 — New test files (66 untested source files)

Grouped by priority.

### Priority 1 — Security-critical

#### `Tests/Security/PDSBiometricKeychainTests.m`
Source: `Sources/Security/PDSBiometricKeychain.m`

All Keychain tests must run only on Apple (`#if defined(__APPLE__)`).

| Test | Description |
|---|---|
| `testStoreAndRetrieveKeyNoBiometrics` | Store a 32-byte key with biometrics disabled; retrieve it; assert equality |
| `testStoreKeyUpdateWithSecItemUpdate` | Store a key, store a different key under the same account; retrieve — must get the second value (tests atomic update path) |
| `testDeleteKey` | Store then delete; keyExistsForAccount: must return NO |
| `testKeyExistsReturnsFalseForMissingKey` | Fresh account, no prior store; `keyExistsForAccount:` returns NO |
| `testKeyExistsDoesNotPromptBiometric` | Store biometric key; call `keyExistsForAccount:` (must not throw/block — validates `kSecUseAuthenticationUISkip`) |
| `testAccessControlConflictsResolvedCorrectly` | Store with biometrics=YES; verify `kSecAttrAccessible` is NOT in the query |
| `testUpgradeExistingKeysNoOp` | Empty accounts array; `upgradeExistingKeysWithAccounts:` completes without error |

#### `Tests/Auth/PDSAppleKeyManagerTests.m`
Source: `Sources/Auth/PDSAppleKeyManager.m`
Platform: Apple-only (`#if !defined(GNUSTEP)`)

| Test | Description |
|---|---|
| `testGenerateKeyPairCreatesEC256Key` | Generate; keyPairs has one entry; algorithm is `"ES256"` |
| `testPublicKeyJWKContainsRequiredFields` | `publicKeyJWK` returns dict with `kty:"EC"`, `crv`, `x`, `y` |
| `testPublicKeyThumbprintIsRFC7638Compliant` | Parse known EC key bytes; assert thumbprint equals precomputed RFC 7638 value |
| `testSignAndVerifyPayload` | Sign a base64url header + payload string; verify signature with the stored public key |
| `testCurrentKeyIDUpdatedInsideLock` | Generate two keys; after second generation, `currentKeyID` equals the second key |
| `testLoadKeysFromDatabaseRestoresState` | Save to in-memory DB; create new manager; load; assert same keyPair count |

#### `Tests/Auth/PDSOpenSSLKeyManagerExtendedTests.m`
Source: `Sources/Auth/PDSOpenSSLSessionKeyManager.m`
Platform: GNUstep-only or skip on Apple.

The existing `PDSOpenSSLKeyManagerTests.m` may already cover basics; add:

| Test | Description |
|---|---|
| `testLoadKeysFromDatabaseRestoresActiveFlag` | Persist a key with `is_active=1`; reload; assert `currentKeyID` is set |
| `testSignPayloadProducesValidJWTSigningInput` | Assert signing input is `base64url(header).base64url(payload)` (3-part JWT format) |

#### `Tests/Auth/PKCEUtilTests.m`
Source: `Sources/Auth/PKCEUtil.m`

| Test | Description |
|---|---|
| `testGenerateCodeVerifierLength` | Default verifier is 43–128 characters |
| `testCodeChallengeFromVerifierMatchesSHA256` | `codeChallenge` equals `base64url(SHA-256(verifier))` |
| `testCodeChallengeMethod` | `codeChallengeMethod` equals `"S256"` |
| `testVerifierIsURLSafe` | Contains only `[A-Za-z0-9\-._~]` |

#### `Tests/Auth/DPoPUtilTests.m`
Source: `Sources/Auth/DPoPUtil.m`

| Test | Description |
|---|---|
| `testDPoPTokenCreation` | `createWithMethod:uri:nonce:error:` succeeds for valid inputs |
| `testDPoPTokenRejectsInvalidHTU` | Empty/non-http URI returns nil + error |
| `testDPoPTokenHTMIsPreserved` | `htm` property matches input |
| `testDPoPTokenHTUIsCanonical` | Trailing slash stripped, fragment removed, etc. |
| `testDPoPTokenExpiry` | `exp` is approximately 300 seconds after `iat` |

#### `Tests/Auth/Base32UtilsTests.m`
Source: `Sources/Auth/Base32Utils.m`

Use RFC 4648 test vectors.

| Test | Description |
|---|---|
| `testEncodeDecodeRoundTrip` | 8 bytes of known data; encode; decode; assert equal |
| `testDecodeKnownVector` | `"MFRA"` decodes to `0x61 0x62 0x63` (`"abc"` in base32) |
| `testDecodeIgnoresPadding` | `"MFRA===="` == `"MFRA"` |
| `testDecodeInvalidCharacter` | Non-base32 char returns nil |
| `testDecodeNilInput` | Returns nil without crash |

### Priority 2 — Core ATProto types

#### `Tests/Core/TIDTests.m`
Source: `Sources/Core/TID.m`

| Test | Description |
|---|---|
| `testTIDIsThirteenCharacters` | `[TID tid].stringValue.length == 13` |
| `testTIDsAreMonotonicallyIncreasing` | Two consecutive TIDs: second > first (lexicographically) |
| `testTIDWithKnownTimestamp` | `tidWithTimestamp:` with a fixed µs value encodes to the expected base32 string |
| `testTIDParseRoundTrip` | Parse a TID string back to timestamp; matches input timestamp |
| `testTIDUniqueness` | 1000 consecutive TIDs are all distinct |

#### Extend `Tests/Core/ATProtoCoreTests.m`
Source: `Sources/Core/CID.m`, `Sources/Core/DID.m`

| Test | Description |
|---|---|
| `testCIDFromStringRoundTrip` | Known CIDv1 string → `CID` → `.cidString` == original |
| `testCIDFromInvalidStringReturnsNil` | Garbage input returns nil |
| `testDIDParsing` | `did:plc:abc123` → method `"plc"`, identifier `"abc123"` |
| `testDIDInvalidFormatReturnsNil` | `"notadid"` → nil |

#### `Tests/Auth/Secp256k1ExtendedTests.m` (or extend `JWTTests.m`)
Source: `Sources/Auth/Secp256k1.m`

The class is exercised through `JWTTests.m` but not directly.

| Test | Description |
|---|---|
| `testGenerateKeyPairProducesValid32BytePrivateKey` | Private key is exactly 32 bytes |
| `testPublicKeyIs65BytesUncompressed` | Public key (uncompressed) is 65 bytes |
| `testCompressedPublicKeyIs33Bytes` | Compressed public key is 33 bytes |
| `testKeyPairFromPrivateKeyDerivesMatchingPublic` | Re-derive from private; compressed public matches |
| `testSignAndVerifyHash` | Sign a 32-byte hash; `verifySignature:forHash:error:` returns YES with same key |
| `testVerifyFailsWithWrongKey` | Sign with key A; verify with key B → NO |

#### `Tests/AuthCrypto/AuthCryptoTests.m` (new, covers 4 files)
Sources: `AuthCrypto/AuthCryptoBase64URL.m`, `AuthCryptoDPoP.m`, `AuthCryptoECDSA.m`, `AuthCryptoJWK.m`

| Test | Description |
|---|---|
| `testBase64URLEncodeDecodeRoundTrip` | `AuthCryptoBase64URL` |
| `testCanonicalHTUStripsFragment` | `AuthCryptoDPoP` |
| `testCanonicalHTUStripsQuery` | `AuthCryptoDPoP` |
| `testECDSASignVerifyWithP256Key` | `AuthCryptoECDSA` sign+verify |
| `testJWKFromECPublicKey` | `AuthCryptoJWK` produces correct `kty:EC` dict |
| `testJWKThumbprintMatchesRFC7638` | Canonical JSON ordering, SHA-256 |

### Priority 3 — Network layer

#### Extend `Tests/Network/PDSNetworkTransportTests.m`
Source: `Sources/Network/PDSNetworkTransportMac.m`

| Test | Description |
|---|---|
| `testInitWithConnectionSetsDefaultQueue` | Verify that constructing a transport object does not crash — the fix is that a queue is assigned before the state handler fires |
| `testConnectionStateChangeHandlerIsRegistered` | State-change callback is invoked when connection closes |

#### `Tests/Network/HttpRequestTests.m`
Source: `Sources/Network/HttpRequest.m`

| Test | Description |
|---|---|
| `testParseGETRequestLine` | Method, path, and HTTP version parsed correctly |
| `testParseHeadersDict` | Multiple headers stored; header lookup is case-insensitive |
| `testBodyDataAttached` | Request with body stores correct bytes |
| `testQueryStringParsing` | `?foo=bar&baz=qux` → NSDictionary with expected keys/values |

### Priority 4 — Repository

#### Extend `Tests/Repository/CARInteropTests.m`
Source: `Sources/Repository/CAR.m`

| Test | Description |
|---|---|
| `testCAREncodeSingleBlock` | Encode one block; decode; assert block data matches |
| `testCAREncodeMultipleBlocks` | Encode 3 blocks; decode; all present |
| `testCARRootCIDPreserved` | Root CID in header matches what was set on encode |
| `testCARRejectsTruncated` | Truncated byte slice returns error/nil on parse |

#### Extend `Tests/Core/ATProtoDagCBORTests.m`
Source: `Sources/Repository/CBOR.m`, `Sources/Core/ATProtoCBORSerialization.m`

These may already have coverage; verify the following are present:

| Test | Description |
|---|---|
| `testCBOREncodeDecodeString` | UTF-8 string round-trip |
| `testCBOREncodeDecodeNestedMap` | Nested dict round-trip |
| `testCBOREncodeDecodeCIDLink` | CID link tag (`42`) preserved |
| `testCBOREncodeDecodeBytes` | Byte string round-trip |

### Priority 5 — Database layer

#### Extend `Tests/Database/ActorStore/ActorStoreTests.m`
Sources: `Database/ActorStore/PDSActorStore+Account.m`, `PDSActorStore+Blob.m`

| Test | Description |
|---|---|
| `testCreateAccountStoresHashedPassword` | Account created; `passwordHashForDID:` returns non-nil, non-plaintext value |
| `testStoreBlobRoundTrip` | Store 100-byte blob; retrieve by CID; bytes match |
| `testBlobCachingReturnsSameData` | Two fetches return same NSData pointer (cache hit) |

#### `Tests/Database/PDSDatabaseTests.m` (new or extend existing)
Source: `Sources/Database/PDSDatabase.m`

| Test | Description |
|---|---|
| `testOpenAndClose` | Open an in-memory DB; close; no crash |
| `testExecuteParameterizedUpdateAndQuery` | Insert row; query; returned NSDictionary has correct values |
| `testTransactionRollbackOnError` | Begin transaction; insert; force rollback; row absent |

#### `Tests/Database/PDSSchemaManagerTests.m`
Source: `Sources/Database/Schema/PDSSchemaManager.m`, `Sources/Database/Schema.m`

| Test | Description |
|---|---|
| `testActorStoreSchemaContainsRequiredTables` | `actorStoreSchemaSQL` contains `CREATE TABLE` for `records`, `blocks`, `rotation_keys` |
| `testServiceSchemaContainsJWTSigningKeys` | Service schema SQL contains `jwt_signing_keys` |
| `testSchemaVersionIsIncremented` | Schema version is a positive integer |

### Priority 6 — Service and handler layer

#### `Tests/Network/XrpcAdminMethodsTests.m` (new)
Source: `Sources/Network/XrpcAdminMethods.m`, `XrpcAuthHelper.m`, `XrpcIdentityHelper.m`

These are mostly integration-style and already partially covered via
`AdminAuthXrpcTests.m`. Add focused unit tests for the helper/factory classes:

| Test | Description |
|---|---|
| `testAuthHelperExtractsBearerToken` | Header `"Authorization: Bearer abc"` → token `"abc"` |
| `testAuthHelperRejectsMissingHeader` | Missing Authorization header → nil |
| `testIdentityHelperNormalizesHandle` | `"Alice.Test"` → `"alice.test"` |

#### `Tests/AppView/GraphServiceTests.m` (new)
Source: `Sources/AppView/GraphService.m`

| Test | Description |
|---|---|
| `testFollowRelationshipStored` | Insert follow; `isFollowingDID:byDID:` returns YES |
| `testUnfollowRemovesRelationship` | Follow then unfollow; `isFollowingDID:byDID:` returns NO |
| `testFollowerCountIsAccurate` | Insert 3 followers; `followerCountForDID:` == 3 |

#### `Tests/AppView/BookmarkServiceTests.m` (new)
Source: `Sources/AppView/BookmarkService.m`

| Test | Description |
|---|---|
| `testAddBookmarkStored` | Add bookmark; `bookmarksForDID:` contains URI |
| `testRemoveBookmarkDeletes` | Add then remove; `bookmarksForDID:` is empty |
| `testDuplicateBookmarkIsIdempotent` | Add same URI twice; count is 1 |

### Priority 7 — CLI (functional/smoke tests)

Source files: `PDSCLIDispatcher.m`, `PDSCLIAdminCommand.m`, `PDSCLIDaemonCommand.m`,
`PDSCLIHealthCommand.m`, `PDSCLIInitCommand.m`, `PDSCLINukeCommand.m`,
`PDSCLIOAuthCommand.m`, `PDSCLIServeCommand.m`, `PDSCLIInputHelper.m`,
`PDSCLIAccountManager.m`

Most of these require a running server. The existing `Tests/CLI/` tests cover the
major commands via `PDSCLIServiceStubTests.m`. Extend that stub to cover the
remaining 10 command implementations:

| Test class to extend | Missing commands |
|---|---|
| `PDSCLITests.m` | `admin`, `daemon`, `health`, `init`, `nuke`, `oauth`, `serve` smoke tests |
| `PDSCLIServiceStubTests.m` | `PDSCLIInputHelper` prompt parsing, `PDSCLIAccountManager` lookup |

### Priority 8 — Remaining infrastructure

| Source file | Test strategy |
|---|---|
| `Sources/Auth/Session.m` | Extend `Tests/Auth/SessionStoreTests.m`: add `testSessionRoundTrip` and `testExpiredSessionIsRejected` |
| `Sources/Auth/TOTPGenerator.m`, `TOTPService.m` | Existing `TOTPTests.m` covers generator; add `testTOTPServiceEnrollment` and `testTOTPServiceVerification` to a new `PDSTOTPServiceTests.m` |
| `Sources/Auth/PDSNonceManager.m` | Add to `Tests/Auth/PDSReplayCacheTests.m`: `testNonceIsConsumedOnFirstUse`, `testNonceIsRejectedOnReuse` |
| `Sources/Auth/PDSKeyManagerFactory.m` | `Tests/Auth/PDSKeyManagerFactoryTests.m`: `testFactoryReturnsPlatformKeyManager` |
| `Sources/Compat/Foundation/NSDataCompat.m` | `Tests/Compat/NSDataCompatTests.m`: `testBase64URLEncoding`, `testConstantTimeComparison` |
| `Sources/Core/ATProtoBase32.m` | Extend `Tests/Core/Base58Tests.m` or new file: RFC 4648 vectors |
| `Sources/Core/ATProtoValidator.m` | Extend `Tests/Core/ProtocolCompileTests.m`: valid/invalid AT-URI, NSID, DID |
| `Sources/Core/NSDateFormatter+ATProto.m` | Extend `Tests/Core/NSDateFormatterATProtoTests.m`: known timestamp → ISO8601 string round-trip |
| `Sources/Core/Repositories/*.m` | These are behind `PDSAccountManager`/`PDSActorStore` — extend existing tests to hit the repository layer with direct init |
| `Sources/Debug/PDSLogger.m` | Extend `Tests/Debug/PDSLoggerPerformanceTests.m`: `testLoggerDoesNotCrashOnNilMessage`, `testLogLevelFiltering` |
| `Sources/Lexicon/*.m` (6 files) | Extend `Tests/Lexicon/LexiconValidationTests.m` with direct `ATProtoLexiconRegistry` and `ATProtoLexiconValidator` tests |
| `Sources/PLC/PLCMetrics.m`, `PLCMockStore.m`, `PLCPersistentStore.m` | Extend `Tests/PLC/PLCStoreTests.m`: metrics increment, mock store operations |
| `Sources/OAuthProvider/OAuthProvider.m` | Extend `Tests/Auth/OAuth2Tests.m`: `testOAuthProviderRegistersClient`, `testOAuthProviderRejectsInvalidRedirectURI` |
| `Sources/PDSAuth/PDSAuth.m` | Extend `Tests/Auth/OAuth2HandlerTests.m` |
| `Sources/AuthVerifier/AuthVerifier.m` | New `Tests/Auth/AuthVerifierTests.m` |
| `Sources/Blob/PDSDiskBlobProvider.m` | Extend `Tests/Blob/BlobStorageTests.m`: `testDiskProviderStoreAndRetrieve`, `testDiskProviderDeleteNonExistent` |
| `Sources/App/Services/PDSRelayService.m` | Extend `Tests/Sync/RelayClientTests.m` |
| `Sources/App/NodeInfo/*.m` (3 files) | Extend `Tests/App/NodeInfo/NodeInfoTests.m`: add provider and schema tests |
| `Sources/App/OAuthDemo/OAuthDemoHandler.m` | Extend `Tests/App/OAuthDemo/OAuthDemoHandlerConfigurationTests.m` |
| `Sources/Admin/PDSAdminHandler.m`, `PDSInstallerCommand.m` | Extend `Tests/Admin/PDSAdminControllerTests.m` |
| `Sources/AppView/RecordLifecycleHandler.m` | New `Tests/AppView/RecordLifecycleTests.m` |
| `Sources/Database/PDSRepositoryFactory.m` | New `Tests/Database/PDSRepositoryFactoryTests.m` |
| `Sources/Network/XrpcAppBskyMethods.m` etc. (8 Xrpc*.m files) | These are covered by integration tests; add per-file smoke tests in the existing `XrpcIntegrationTests.m` |
| `Sources/Network/SSLPinningManager.m` | Extend `Tests/Network/SSLPinningTests.m` |
| `Sources/Network/XrpcProxyHandler.m` | Extend `Tests/Network/XrpcProxyTests.m` |

---

## Part 3 — Implementation order

| Phase | Files / tasks | Notes |
|---|---|---|
| **A** | Extend `CryptoTests.m` (§1.1) | Foundation; other tests depend on AES-GCM |
| **A** | Extend `JWTTests.m` (§1.2) | Validates RFC 7519 audience fix |
| **A** | Extend `PLCRotationKeyManagerTests.m` (§1.4) | Validates migration code |
| **A** | Extend `ActorStoreTests.m` (§1.5) | Validates migration code |
| **A** | Extend `FeedServiceTests.m` (§1.3) | Validates SHA-256 crash fix |
| **B** | `PDSBiometricKeychainTests.m` (§2 P1) | Apple-only; needs real Keychain |
| **B** | `PDSAppleKeyManagerTests.m` (§2 P1) | Apple-only |
| **B** | `PKCEUtilTests.m`, `DPoPUtilTests.m`, `Base32UtilsTests.m` (§2 P1) | Pure logic, no platform deps |
| **C** | `TIDTests.m`, extend `ATProtoCoreTests.m` (§2 P2) | Pure logic |
| **C** | `AuthCryptoTests.m`, `Secp256k1ExtendedTests.m` (§2 P2) | Pure crypto |
| **D** | `HttpRequestTests.m` (§2 P3) | Pure parsing logic |
| **D** | Extend `PDSNetworkTransportTests.m` (§2 P3) | Requires Apple Network.framework |
| **E** | CAR and CBOR extensions (§2 P4) | Pure serialization |
| **F** | Database layer (§2 P5) | Integration-style, need temp SQLite |
| **G** | Service/handler layer, CLI, infrastructure (§2 P6–P8) | Mix of unit and integration |

---

## Part 4 — GNUstep compatibility checklist for new tests

Every new test file must:

1. Use the conditional include guard:
   ```objc
   #ifdef __APPLE__
   #import <XCTest/XCTest.h>
   #else
   #import "Compat/XCTest/XCTest.h"
   #endif
   ```

2. Wrap Apple-only tests (`Security.framework`, `LocalAuthentication`, `Network.framework`, AppKit) in `#if defined(__APPLE__)` or use `XCTSkip` at runtime.

3. Use `NSTemporaryDirectory()` + UUID for all file/directory paths created in tests — never hard-code `/tmp`.

4. Use `XCTSkip` (not `XCTFail`) when required hardware (Secure Enclave, biometrics) is unavailable.

---

## Summary counts

| Category | New test methods | New test files |
|---|---|---|
| Gaps in existing files (Part 1) | ~28 | 0 |
| New files, Priority 1 (security) | ~35 | 6 |
| New files, Priority 2 (core types) | ~25 | 4 |
| New files, Priority 3–8 (network, DB, services, infra) | ~60 | ~20 |
| **Total** | **~148** | **~30** |

Completing all phases brings source-file coverage from **64% → 100%**.
