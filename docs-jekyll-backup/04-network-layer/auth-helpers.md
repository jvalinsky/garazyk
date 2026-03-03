# Authentication Helpers

## Overview

The `XrpcAuthHelper` provides centralized authentication logic for XRPC endpoints. It handles JWT token verification, DPoP proof validation, and DID extraction from Authorization headers.

## Responsibilities

- Extract and validate DIDs from Authorization headers
- Support Bearer tokens (JWT) and DPoP tokens
- Verify JWT signatures with algorithm selection
- Validate DPoP proofs and thumbprint binding
- Handle DPoP nonce challenges
- Reject takedown accounts
- Enforce admin authorization

## Authentication Flow

```
Authorization Header
    │
    ├─ Bearer \<JWT\>
    │   ├─ Parse JWT
    │   ├─ Verify signature
    │   ├─ Check expiration
    │   └─ Extract DID
    │
    └─ DPoP \<JWT\>
        ├─ Parse DPoP proof
        ├─ Verify DPoP signature
        ├─ Check nonce
        ├─ Parse access token
        ├─ Verify access token signature
        ├─ Verify thumbprint binding
        └─ Extract DID
```

## Key Methods

### Extract DID from Authorization Header

```objc
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request;
```

Extracts and validates DID from Authorization header.

**Parameters:**
- `authHeader`: Authorization header value (e.g., "Bearer \<token\>" or "DPoP \<token\>")
- `jwtMinter`: JWT minter for signature verification
- `adminController`: Admin controller for takedown checks
- `request`: HTTP request for DPoP URL construction

**Returns:** Authenticated DID or nil on failure

**Implementation Details (from XrpcAuthHelper.m):**

The helper supports both Bearer tokens and DPoP tokens:

```objc
// Parse Bearer or DPoP token
NSString *token = nil;
BOOL isDPoP = NO;
if ([authHeader hasPrefix:@"Bearer "]) {
    token = [authHeader substringFromIndex:7];
    if ([request headerForKey:@"DPoP"].length > 0) {
        isDPoP = YES; // Some clients send Bearer but attach a DPoP header
    }
} else if ([authHeader hasPrefix:@"DPoP "]) {
    token = [authHeader substringFromIndex:5];
    isDPoP = YES;
} else {
    return nil;
}
```

For DPoP verification, it validates the proof and extracts the thumbprint:

```objc
// DPoP verification
NSString *dpopThumbprint = nil;
if (isDPoP) {
    NSString *dpopProof = [request headerForKey:@"DPoP"];
    if (dpopProof.length == 0) {
        PDS_LOG_AUTH_WARN(@"Missing DPoP header for DPoP authorization");
        return nil;
    }

    NSURL *dpopURL = XrpcAuthExpectedDPoPURL(request, jwtMinter);
    if (!dpopURL) {
        PDS_LOG_AUTH_WARN(@"Unable to construct DPoP URL for request");
        return nil;
    }

    // Verify DPoP proof
    NSError *dpopError = nil;
    if (![OAuth2DPoPProof verifyProof:dpopProof
                               method:request.methodString
                                  url:dpopURL
                                nonce:nil
                         requireNonce:[PDSConfiguration sharedConfiguration].requireDPoPNonce
                        outThumbprint:&dpopThumbprint
                                error:&dpopError]) {
        // Handle DPoP nonce challenge
        if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
            if (response) {
                response.statusCode = HttpStatusUnauthorized;
                NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
                if (nonce.length > 0) {
                    [response setHeader:nonce forKey:@"DPoP-Nonce"];
                }
                [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
                [response setJsonBody:@{
                    @"error": @"use_dpop_nonce",
                    @"message": @"DPoP nonce required"
                }];
            }
            return nil;
        }
        return nil;
    }
}
```

JWT verification with custom audience handling:

```objc
// Parse the JWT token
NSError *parseError = nil;
JWT *jwt = [JWT jwtWithToken:token error:&parseError];
if (!jwt || parseError) {
    return nil;
}

// Create verifier and set expected issuer
JWTVerifier *verifier = [[JWTVerifier alloc] init];
if (jwtMinter) {
    verifier.keyManager = jwtMinter.keyManager;
    verifier.publicKey = jwtMinter.publicKey;
}

PDSConfiguration *configuration = [PDSConfiguration sharedConfiguration];
NSString *expectedIssuer = jwtMinter.issuer ?: [configuration canonicalIssuerWithPortHint:0];
verifier.expectedIssuer = expectedIssuer;
verifier.allowedAlgorithms = [self allowedAlgorithmsForMinter:jwtMinter];

// Verify the JWT
NSError *verifyError = nil;
BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
if (!isValid || verifyError) {
    return nil;
}

// Custom Audience Verification (supports did:web variants)
NSString *tokenAud = jwt.payload.aud;
if (tokenAud) {
    BOOL validAud = [tokenAud isEqualToString:expectedIssuer];
    if (!validAud) {
        NSURL *issuerURL = [NSURL URLWithString:expectedIssuer];
        if (issuerURL.host) {
            NSString *didWebHost = [NSString stringWithFormat:@"did:web:%@", issuerURL.host];
            NSString *didWebHostPort = nil;
            if (issuerURL.port) {
                didWebHostPort = [NSString stringWithFormat:@"did:web:%@%%3A%@", issuerURL.host, issuerURL.port];
            }
            if ([tokenAud isEqualToString:didWebHost] || (didWebHostPort && [tokenAud isEqualToString:didWebHostPort])) {
                validAud = YES;
            }
        }
    }
    if (!validAud) {
        return nil;
    }
}
```

DPoP binding verification:

```objc
// Enforce DPoP binding
NSString *tokenJkt = jwt.payload.cnf[@"jkt"];
if (isDPoP) {
    if (!tokenJkt) {
        PDS_LOG_AUTH_WARN(@"DPoP authorization used with non-DPoP-bound token");
        return nil;
    }
    if (![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
        PDS_LOG_AUTH_WARN(@"DPoP thumbprint mismatch");
        return nil;
    }
} else if (tokenJkt) {
    PDS_LOG_AUTH_WARN(@"DPoP-bound token sent as Bearer token");
    return nil;
}
```

Takedown account rejection:

```objc
// Extract DID from subject claim
NSString *did = jwt.payload.sub;
if (!did || ![did hasPrefix:@"did:"]) {
    return nil;
}

// Check takedown status
NSError *takedownError = nil;
BOOL isTakedown = [adminController isAccountTakedownActive:did error:&takedownError];
if (takedownError) {
    return nil;
}
if (isTakedown) {
    PDS_LOG_AUTH_WARN(@"Rejected request for suspended account %@", did);
    return nil;
}

return did;
```

**Example Usage:**
```objc
NSString *authHeader = [request headerForName:@"Authorization"];
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];

if (!did) {
    [XrpcErrorHelper setAuthenticationError:response];
    return;
}
```

### Extract DID with Response

```objc
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;
```

Extracts DID and can set error responses (e.g., DPoP nonce challenge).

**Example:**
```objc
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request
                                               response:response];

if (!did) {
    // Response already set with error details
    return;
}
```

### Extract DID from PDSController

```objc
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                     controller:(PDSController *)controller
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;
```

Convenience method that extracts jwtMinter and adminController from controller.

**Example:**
```objc
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                             controller:controller
                                                request:request
                                               response:response];
```

### Authorize Admin Request

```objc
+ (BOOL)authorizeAdminRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;
```

Authorizes admin request by validating authentication and admin privileges.

**Parameters:**
- `request`: HTTP request containing Authorization header
- `response`: HTTP response for setting error details
- `serviceDatabases`: Service databases for account lookups
- `jwtMinter`: JWT minter for signature verification
- `adminController`: Admin controller for takedown checks

**Returns:** YES if authorized, NO if authentication or authorization failed

**Example:**
```objc
BOOL authorized = [XrpcAuthHelper authorizeAdminRequest:request
                                                response:response
                                        serviceDatabases:serviceDatabases
                                               jwtMinter:jwtMinter
                                         adminController:adminController];

if (!authorized) {
    // Response already set with error
    return;
}

// Proceed with admin operation
```

## Bearer Token Authentication

### JWT Format

Bearer tokens are JWT (JSON Web Tokens) with three parts:

```
Bearer eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkaWQ6cGxjOnVzZXIxMjMiLCJleHAiOjE2MzE1NTUyMDB9.signature
       └─ Header ─────────────────────────────────────────────────────────────────────────────────────────────────────┘
                 └─ Payload ──────────────────────────────────────────────────────────────────────────────────────────┘
                                                                                                                      └─ Signature ┘
```

### JWT Claims

Standard JWT claims:

| Claim | Purpose |
|-------|---------|
| `sub` | Subject (user's DID) |
| `aud` | Audience (PDS identifier) |
| `exp` | Expiration time (Unix timestamp) |
| `iat` | Issued at (Unix timestamp) |
| `alg` | Algorithm (ES256, RS256, etc.) |

**Example JWT payload:**
```json
{
  "sub": "did:plc:user123",
  "aud": "did:web:pds.example.com",
  "exp": 1631555200,
  "iat": 1631551600
}
```

### Verification Process

1. Parse JWT header to get algorithm
2. Extract public key for algorithm
3. Verify signature using public key
4. Check expiration time
5. Validate audience claim
6. Extract and return DID from subject claim

## DPoP Authentication

### DPoP Format

DPoP (Demonstration of Proof-of-Possession) uses two tokens:

```
Authorization: DPoP \<access_token\>
DPoP: \<dpop_proof\>
```

### DPoP Proof Structure

DPoP proof is a JWT with:

```json
{
  "typ": "dpop+jwt",
  "alg": "ES256",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "...",
    "y": "..."
  }
}
```

Payload:

```json
{
  "jti": "unique-id",
  "htm": "POST",
  "htu": "https://pds.example.com/xrpc/com.atproto.repo.createRecord",
  "iat": 1631551600,
  "exp": 1631551660,
  "nonce": "server-provided-nonce"
}
```

### DPoP Verification

1. Parse DPoP proof JWT
2. Verify DPoP signature using embedded public key
3. Check DPoP timestamp (within 60 seconds)
4. Verify HTTP method matches `htm` claim
5. Verify URL matches `htu` claim
6. Check nonce if provided
7. Extract public key thumbprint
8. Parse access token
9. Verify access token signature
10. Verify thumbprint binding in access token
11. Extract and return DID

### DPoP Nonce Challenge

If DPoP verification fails due to missing nonce:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: DPoP error="use_dpop_nonce"
DPoP-Nonce: server-generated-nonce
Content-Type: application/json

{
  "error": "AuthRequired",
  "message": "DPoP nonce required"
}
```

Client must retry with nonce in DPoP proof.

## Takedown Account Rejection

The helper checks if an account is under takedown:

```objc
// In extractDIDFromAuthHeader:
if ([adminController isAccountTakenDown:did]) {
    // Reject authentication
    return nil;
}
```

Takedown accounts cannot authenticate even with valid tokens.

## Admin Authorization

The helper can verify admin privileges:

```objc
BOOL authorized = [XrpcAuthHelper authorizeAdminRequest:request
                                                response:response
                                        serviceDatabases:serviceDatabases
                                               jwtMinter:jwtMinter
                                         adminController:adminController];
```

This checks:
1. Valid authentication
2. Admin account status
3. Admin permissions

## Error Handling

### Authentication Failures

| Error | Cause | Response |
|-------|-------|----------|
| Missing header | No Authorization header | 401 Unauthorized |
| Invalid format | Malformed header | 401 Unauthorized |
| Invalid token | Malformed JWT | 401 Unauthorized |
| Expired token | Token past expiration | 401 Unauthorized |
| Invalid signature | Signature verification failed | 401 Unauthorized |
| Invalid nonce | DPoP nonce mismatch | 401 with DPoP-Nonce header |
| Takedown account | Account under takedown | 401 Unauthorized |

### DPoP Nonce Challenge

When DPoP nonce is missing or invalid:

```objc
response.statusCode = 401;
[response setHeaderValue:@"DPoP error=\"use_dpop_nonce\"" 
               forName:@"WWW-Authenticate"];
[response setHeaderValue:generatedNonce forName:@"DPoP-Nonce"];
```

## Best Practices

1. **Token Validation**
   - Always verify signatures
   - Check expiration times
   - Validate audience claims
   - Reject takedown accounts

2. **DPoP Handling**
   - Implement nonce challenge
   - Verify method and URL
   - Check timestamp freshness
   - Validate thumbprint binding

3. **Error Responses**
   - Use appropriate HTTP status codes
   - Include error details in response
   - Set DPoP-Nonce header when needed
   - Log authentication failures

4. **Performance**
   - Cache public keys
   - Reuse JWT verification
   - Minimize cryptographic operations
   - Use connection pooling

## Common Patterns

### Simple Bearer Token Authentication

```objc
NSString *authHeader = [request headerForName:@"Authorization"];
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];

if (!did) {
    [XrpcErrorHelper setAuthenticationError:response];
    return;
}

// Proceed with authenticated request
```

### DPoP Authentication with Nonce Challenge

```objc
NSString *authHeader = [request headerForName:@"Authorization"];
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request
                                               response:response];

if (!did) {
    // Response already set with error or nonce challenge
    return;
}

// Proceed with authenticated request
```

### Admin Authorization

```objc
BOOL authorized = [XrpcAuthHelper authorizeAdminRequest:request
                                                response:response
                                        serviceDatabases:serviceDatabases
                                               jwtMinter:jwtMinter
                                         adminController:adminController];

if (!authorized) {
    // Response already set with error
    return;
}

// Proceed with admin operation
```

### Optional Authentication

```objc
NSString *authHeader = [request headerForName:@"Authorization"];
NSString *did = nil;

if (authHeader) {
    did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                        jwtMinter:jwtMinter
                                  adminController:adminController
                                          request:request];
}

// Proceed with or without authentication
// (some endpoints allow both)
```

## See Also

- [XRPC Dispatch](./xrpc-dispatch.md)
- [Domain Methods](./domain-methods.md)
- [Error Handling](./error-handling.md)
- [JWT Tokens](../06-authentication/jwt-tokens.md)
- [OAuth 2.0 with DPoP](../06-authentication/oauth2-dpop.md)
