# PKCE (Proof Key for Code Exchange)

PKCE (RFC 7636) protects the authorization code flow from interception attacks by binding the code to a client-generated secret.

## Overview

PKCE prevents an attacker who intercepts the authorization code from exchanging it for tokens. The client generates a `code_verifier` and sends its SHA-256 hash (`code_challenge`) during authorization. When exchanging the code, the client proves possession of the original verifier.

```
┌─────────┐                    ┌─────────┐                    ┌─────────┐
│  Client │                    │   PDS   │                    │  Atta.. │
└────┬────┘                    └────┬────┘                    └────┬────┘
     │                              │                              │
     │ 1. Generate code_verifier    │                              │
     │    (random 32 bytes)         │                              │
     │                              │                              │
     │ 2. Compute code_challenge    │                              │
     │    = BASE64URL(SHA256(v))    │                              │
     │                              │                              │
     │ GET /oauth/authorize         │                              │
     │   ?code_challenge=E9Mel...   │                              │
     │   &code_challenge_method=S256│                              │
     │─────────────────────────────>│                              │
     │                              │                              │
     │                              │  Store challenge             │
     │                              │  with auth code              │
     │                              │                              │
     │    302 redirect?code=ABC     │◄──── Intercepts code ────────│
     │<─────────────────────────────│                              │
     │                              │                              │
     │ POST /oauth/token            │                              │
     │   code_verifier=dBjf...      │                              │
     │─────────────────────────────>│                              │
     │                              │                              │
     │                              │  Verify:                     │
     │                              │  SHA256(verifier) == stored  │
     │                              │  challenge?                  │
     │                              │                              │
     │         access_token         │     ❌ Attacker lacks       │
     │<─────────────────────────────│        verifier             │
     │                              │                              │
```

## Implementation

### Files

| File | Purpose |
|------|---------|
| `ATProtoPDS/Sources/Auth/PKCEUtil.m` | Code verifier/challenge generation |
| `ATProtoPDS/Sources/Auth/PKCEUtil.h` | Public API declaration |
| `ATProtoPDS/Sources/Auth/OAuth2.m` | PKCE verification in token exchange |
| `ATProtoPDS/Sources/Auth/OAuth2Handler.m` | PKCE enforcement for public clients |

### PKCEUtil API

```objc
@interface PKCEUtil : NSObject

+ (NSString *)generateCodeVerifier;
+ (NSString *)generateCodeChallengeWithVerifier:(NSString *)verifier;
+ (BOOL)verifyCodeChallenge:(NSString *)challenge withVerifier:(NSString *)verifier;

@end
```

## Code Verifier Generation

The code verifier is a cryptographically random string using the unreserved URL characters:

```
CharacterSet: [A-Z] [a-z] [0-9] - . _ ~
Length: 43-128 characters
```

### Implementation

```objc
+ (NSString *)generateCodeVerifier {
    NSData *randomData = [CryptoUtils randomBytes:32];
    return [CryptoUtils base64URLEncode:randomData];
}
```

32 random bytes → Base64URL encoding → 43 characters (minimum valid length).

### Example

```
Random bytes (hex):  7c3e8f2a1b9c4d5e6f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e
Base64URL encoded:   HD6PKhucTV5vChssPU5fanuMHx8qO0vF5uT4qbDB4u4
```

## Code Challenge Generation

The code challenge is the SHA-256 hash of the verifier, Base64URL encoded:

```
code_challenge = BASE64URL(SHA256(code_verifier))
```

### Implementation

```objc
+ (NSString *)generateCodeChallengeWithVerifier:(NSString *)verifier {
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    if (!verifierData) return nil;
    NSData *hashData = [CryptoUtils sha256:verifierData];
    return [CryptoUtils base64URLEncode:hashData];
}
```

### Example

```
verifier:   dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
challenge:  E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
```

## Verification Algorithm

During token exchange, the server verifies the client possesses the original verifier:

```objc
+ (BOOL)verifyCodeChallenge:(NSString *)challenge withVerifier:(NSString *)verifier {
    NSString *expectedChallenge = [self generateCodeChallengeWithVerifier:verifier];
    return [challenge isEqualToString:expectedChallenge];
}
```

### Verification Flow (OAuth2.m)

```objc
// In processAuthorizationCodeGrant:
if (request.codeVerifier && codeData[@"code_challenge"]) {
    NSString *expectedChallenge = codeData[@"code_challenge"];
    NSString *method = codeData[@"code_challenge_method"] ?: @"plain";
    
    // URL-decode the code_verifier (browsers may encode it)
    NSString *codeVerifier = [request.codeVerifier stringByRemovingPercentEncoding];
    
    if (![self verifyCodeVerifier:codeVerifier 
                        challenge:expectedChallenge 
                          method:method]) {
        // Return invalid_grant error
        return;
    }
}
```

## Enforcement

### Public Client Requirement

Public clients (no `client_secret`) MUST use PKCE:

```objc
// In handleAuthorizeRequest (OAuth2Handler.m):
BOOL isPublicClient = (client[@"client_secret"] == nil);
if (isPublicClient && (!authRequest.codeChallenge || authRequest.codeChallenge.length == 0)) {
    response.statusCode = 400;
    [response setJsonBody:@{
        @"error": @"invalid_request",
        @"error_description": @"code_challenge required for public clients"
    }];
    return;
}
```

### Challenge Storage

The challenge is stored with the authorization code data:

```objc
// In handleAuthorizationRequest (OAuth2.m):
NSMutableDictionary *codeData = [NSMutableDictionary dictionary];
codeData[@"client_id"] = request.clientID;
codeData[@"redirect_uri"] = request.redirectURI;
if (request.codeChallenge) {
    codeData[@"code_challenge"] = request.codeChallenge;
}
if (request.codeChallengeMethod) {
    codeData[@"code_challenge_method"] = request.codeChallengeMethod;
}
```

### Method Default

If `code_challenge_method` is omitted, it defaults to `S256`:

```objc
NSString *method = codeData[@"code_challenge_method"] ?: @"S256";
```

## RFC 7636 Test Vector

RFC 7636 provides test vectors for implementation verification:

| Parameter | Value |
|-----------|-------|
| `code_verifier` | `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` |
| `code_challenge` | `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM` |
| `code_challenge_method` | `S256` |

### Verification Steps

1. Decode verifier from Base64URL: 32 bytes
2. Compute SHA-256 hash: 32 bytes
3. Encode hash with Base64URL: 43 characters
4. Compare with expected challenge

## Parameters

### Authorization Request

```
GET /oauth/authorize?
    client_id=my-app&
    redirect_uri=https://app.example.com/callback&
    response_type=code&
    scope=atproto&
    state=random-state&
    code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&
    code_challenge_method=S256
```

### Token Request

```
POST /oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&
code=authorization-code&
redirect_uri=https://app.example.com/callback&
client_id=my-app&
code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
```

## Security Properties

### Authorization Code Interception Protection

Without PKCE, an attacker who intercepts the authorization code (e.g., via browser history, network sniffing on HTTP, or malicious app) can exchange it for tokens.

PKCE prevents this because:
1. The challenge is sent during authorization (public, visible to attacker)
2. The verifier is sent during token exchange (protected by TLS)
3. Without the verifier, the intercepted code is useless

### Replay Protection

Authorization codes are single-use. After successful exchange, the code is deleted:

```objc
[self removeAuthorizationCode:request.code];
```

### Binding to Client Instance

Each client instance generates its own verifier, ensuring:
- Codes cannot be transferred between sessions
- Stolen codes from one device cannot be used on another

## Threat Model

### Mitigated Threats

| Threat | Mitigation |
|--------|------------|
| Authorization code interception | Verifier required for exchange |
| Code injection attacks | Challenge bound to specific verifier |
| Mixed attack (partial interception) | Verifier never exposed in redirect |
| Replay attacks | Single-use codes |

### Attack Scenario

```
1. Client generates verifier (secret)
2. Client sends challenge (public) to server
3. Server issues code, stores challenge
4. Attacker intercepts code (from redirect URL)
5. Attacker attempts token exchange:
   - Without verifier: REJECTED
   - With guessed verifier: ~2^256 search space (infeasible)
```

## Error Responses

### Missing Challenge (Public Client)

```json
{
  "error": "invalid_request",
  "error_description": "code_challenge required for public clients"
}
```

### Invalid Verifier

```json
{
  "error": "invalid_grant",
  "error_description": "Invalid code verifier"
}
```

### Code Expired

```json
{
  "error": "invalid_grant",
  "error_description": "Authorization code expired"
}
```

## Code Lifespan

Authorization codes expire after 10 minutes (600 seconds):

```objc
NSTimeInterval codeAge = [[NSDate date] timeIntervalSince1970] - [codeData[@"created_at"] doubleValue];
if (codeAge > 600) {
    [self removeAuthorizationCode:request.code];
    // Return expired error
}
```

## Implementation Checklist

- [x] Generate cryptographically random verifier (32 bytes)
- [x] Base64URL encode verifier (no padding)
- [x] Compute SHA-256 hash of verifier
- [x] Base64URL encode hash for challenge
- [x] Enforce PKCE for public clients
- [x] Store challenge with authorization code
- [x] Verify verifier during token exchange
- [x] Constant-time string comparison (via `isEqualToString`)
- [x] Single-use code enforcement
- [x] Code expiration (600 seconds)

## References

- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 6749 - OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749)
- [OAuth 2.0 Security Best Current Practice](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics)

## Related Documentation

- [OAuth 2.0 Overview](./README.md)
- [Authorization Flow](./authorization-flow.md)
- [Token Management](./token-management.md)
- [Security Considerations](./security.md)
