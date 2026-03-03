# OAuth 2.0 & OIDC Tests

Tests for OAuth 2.0 authorization flows, PKCE, DPoP, and session management.

## Test Classes

### OAuth2Tests
**File:** `Tests/Auth/OAuth2Tests.m`

**Purpose:** Core OAuth2 server token refresh and rotation flows.

#### How It Works

The test class creates an `OAuth2Server` instance in `setUp` and tests the refresh token lifecycle. Sessions are manually constructed and inserted into `activeSessions` dictionary to simulate authenticated users:

```objc
Session *session = [[Session alloc] initWithDID:@"did:plc:test"
                                         handle:@"test.bsky.social"
                                          scope:@"atproto"];
self.server.activeSessions[session.sessionID] = session;
```

The tests use XCTest expectations (`XCTestExpectation`) to handle the async completion-based API:

```objc
XCTestExpectation *expectation = [self expectationWithDescription:@"Refresh token"];
[self.server refreshAccessToken:refreshToken completion:^(NSString *accessToken, NSError *error) {
    // assertions here
    [expectation fulfill];
}];
[self waitForExpectationsWithTimeout:5.0 handler:nil];
```

#### Why It Matters

**Token Rotation prevents replay attacks.** If a refresh token is leaked, an attacker could use it once before the legitimate client notices. By rotating the token on each refresh, the legitimate client's next attempt fails, alerting them to the breach.

**Test Methods:**

| Method | What It Verifies |
|--------|------------------|
| `testRefreshToken` | Valid refresh token produces new access token |
| `testRefreshTokenInvalid` | Invalid tokens are rejected with error |
| `testRefreshTokenRotation` | Refresh token changes after each use |

---

### OAuth2HandlerTests
**File:** `Tests/Auth/OAuth2HandlerTests.m`

**Purpose:** HTTP request handling for OAuth endpoints including DPoP nonce challenges.

#### How It Works

Tests construct `HttpRequest` objects directly with method, path, headers, and body, then pass them to handler methods:

```objc
HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                               methodString:@"POST"
                                                       path:@"/oauth/token"
                                                queryString:@""
                                                queryParams:@{}
                                                    headers:@{@"dpop": proof.jwt}
                                                       body:[body dataUsingEncoding:NSUTF8StringEncoding]
                                             remoteAddress:@"127.0.0.1"];
HttpResponse *response = [[HttpResponse alloc] init];
[self.handler handleTokenRequest:request response:response];
```

**DPoP Testing** uses a fixed P-256 key for reproducible proofs:

```objc
// Create fixed key from known hex bytes (deterministic for testing)
SecKeyRef privateKey = oauth2HandlerCreateFixedP256PrivateKey(&error);
DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"POST"
                                             uri:@"http://localhost:2583/oauth/token"
                                          nonce:nil
                                            key:privateKey
                                          error:&error];
```

#### Why It Matters

**DPoP Nonce Challenges** prevent replay attacks by requiring the client to include a server-issued nonce in each proof. Without this, an attacker could replay a captured DPoP-bound request.

**Redirect URI handling** must correctly handle both query string cases:
- `http://example.com/callback?code=xyz` → append with `&`
- `http://example.com/callback` → append with `?`

**Test Methods:**

| Method | Security Property |
|--------|-------------------|
| `testTokenRequestRejectsInvalidClientSecret` | Confidential client authentication |
| `testAuthorizeRejectsMissingState` | CSRF protection |
| `testTokenRequestReturnsDPoPNonceChallengeWhenNonceMissing` | Nonce challenge flow |
| `testAuthorizeRedirectWithExistingQueryString` | Correct URL construction |

---

### OAuthDPoPTests
**File:** `Tests/Auth/OAuthDPoPTests.m`

**Purpose:** DPoP (Demonstrating Proof-of-Possession) proof generation and verification.

#### How It Works

Tests generate fresh P-256 key pairs for each test run:

```objc
NSDictionary *attributes = @{
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrKeySizeInBits: @256
};
_privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
_publicKey = SecKeyCopyPublicKey(_privateKey);
```

The proof structure is validated by decoding the JWT:

```objc
NSArray *parts = [token.jwt componentsSeparatedByString:@"."];
NSString *headerB64 = parts[0];
// Decode base64url, parse JSON
NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil];
XCTAssertEqualObjects(header[@"typ"], @"dpop+jwt");
XCTAssertEqualObjects(header[@"alg"], @"ES256");
```

#### Why It Matters

**Binding tokens to keys** prevents token theft. Even if an access token is stolen, it cannot be used without the corresponding private key.

**htm/htu claims** bind the proof to a specific HTTP method and URL, preventing proof reuse across different endpoints.

**Test Methods:**

| Method | Binding Verified |
|--------|------------------|
| `testDPoPHtmBinding` | HTTP method (htm) must match |
| `testDPoPHtuBinding` | URL (htu) must match |
| `testDPoPNonceChallenge` | Server nonce must be included |

---

### OAuthPKCETests
**File:** `Tests/Auth/OAuthPKCETests.m`

**Purpose:** PKCE (Proof Key for Code Exchange) challenge generation and verification.

#### How It Works

Uses RFC 7636 Appendix B test vector for deterministic verification:

```objc
NSString *verifier = @"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
NSString *expectedChallenge = @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
XCTAssertEqualObjects(challenge, expectedChallenge);
```

The challenge is computed as:
```
challenge = BASE64URL(SHA256(verifier))
```

#### Why It Matters

**PKCE protects public clients** (native apps, SPAs) that cannot securely store a client secret. Without PKCE, an attacker who intercepts the authorization code can exchange it for tokens.

**Test Methods:**

| Method | What It Verifies |
|--------|------------------|
| `testPKCES256Challenge` | Matches RFC test vector |
| `testPKCEVerifierMinLength` | >= 43 characters |
| `testPKCEVerifierMaxLength` | <= 128 characters |
| `testPKCEVerifierMismatch` | Wrong verifier rejected |

---

### SessionStoreTests
**File:** `Tests/Auth/SessionStoreTests.m`

**Purpose:** Session lifecycle management with JWT access tokens.

#### How It Works

Creates a fresh `SessionStore` with a configured `JWTMinter` using secp256k1:

```objc
self.minter = [[JWTMinter alloc] init];
self.minter.signingAlgorithm = @"ES256K";

Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
self.minter.privateKey = keyPair.privateKey;
self.store.minter = self.minter;
```

Validates that access tokens are proper JWTs:

```objc
- (void)assertValidJWTAccessToken:(NSString *)accessToken {
    JWT *jwt = [JWT jwtWithToken:accessToken error:&error];
    XCTAssertNotNil(jwt, @"Access token should parse as JWT");
    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertTrue(verified, @"JWT access token should verify");
}
```

**Persistence test** verifies SQLite storage survives process restart:

```objc
SessionStore *store1 = [[SessionStore alloc] initWithDatabasePath:dbPath];
Session *session = [store1 createSessionForDID:@"did:example:123" ...];

SessionStore *store2 = [[SessionStore alloc] initWithDatabasePath:dbPath];
Session *retrieved = [store2 getSessionByAccessToken:accessToken error:&error];
XCTAssertNotNil(retrieved, @"Session should persist across store instances");
```

#### Why It Matters

**JWT access tokens** are stateless - the server doesn't need to look them up on each request. The signature proves authenticity.

**Refresh token rotation** ensures that if a refresh token is leaked, it can only be used once before the legitimate client's attempt fails.

**Test Methods:**

| Method | What It Verifies |
|--------|------------------|
| `testCreateSessionForDID` | Session with valid JWT |
| `testRefreshSession` | Token rotation |
| `testRevokeSession` | All tokens invalidated |
| `testSessionPersistsAcrossStoreInstances` | SQLite persistence |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/OAuth2Tests
./build/tests/AllTests -only-testing:AllTests/OAuth2HandlerTests
./build/tests/AllTests -only-testing:AllTests/OAuthDPoPTests
./build/tests/AllTests -only-testing:AllTests/OAuthPKCETests
./build/tests/AllTests -only-testing:AllTests/SessionStoreTests
```

## Security Considerations

1. **DPoP Nonce Challenges**: Server issues nonces to prevent replay; clients must include in subsequent proofs
2. **PKCE Enforcement**: Public clients MUST use S256 challenge method
3. **Token Rotation**: Refresh tokens rotate to prevent replay if leaked
4. **Algorithm Restriction**: JWT verifier rejects `none` algorithm
5. **Cross-Client Protection**: Tokens cannot be revoked by other clients

## Related Documentation

- [Folder README](README) - Identity & authentication tests overview
- [Test Index](../README) - Main test documentation index
- [OAuth2 Architecture](../../oauth2/architecture) - OAuth2 system architecture
- [Authorization Flow](../../oauth2/authorization-flow) - OAuth2 authorization process
- [DPoP Implementation](../../oauth2/dpop) - DPoP proof specification
- [PKCE](../../oauth2/pkce) - Proof Key for Code Exchange
- [Token Management](../../oauth2/token-management) - Token lifecycle
- [Security Hardening Tests](../05-security/hardening) - Token security testing
- [Security Tests](../05-security/README) - Security test documentation
