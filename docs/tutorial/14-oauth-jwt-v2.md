# Chapter 14: OAuth 2.1 & JWT Authentication

In the previous chapter, we implemented our database layer for storing AT Protocol data—repositories, records, and blobs. But how do users prove they're authorized to access or modify that data? How does a client application authenticate with your PDS?

This chapter introduces **OAuth 2.1** (the authorization framework) and **JWT** (JSON Web Tokens) for session management. Together, they provide secure, standard authentication for AT Protocol applications.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Understand the OAuth 2.1 authorization code flow with PKCE
- Parse and construct JWT tokens with proper encoding
- Mint access and refresh tokens with secp256k1 signatures
- Verify token signatures and expiration
- Implement token refresh and rotation for security
- Handle common authentication error scenarios

## Prerequisites

This chapter assumes you understand:
- **secp256k1 cryptography** - signing and verification (Chapter 8)
- **DIDs** - decentralized identifiers for user identity (Chapter 9)
- **HTTP request/response handling** - server basics (Chapter 11)
- **Base64 encoding** - data encoding concepts (Chapter 4)

If you're not comfortable with these, especially secp256k1 signing, review those chapters first.

---

## The Problem: Secure API Access

### Why Authentication Matters

Imagine your PDS receives these requests:
```
POST /xrpc/com.atproto.repo.createRecord
{
  "repo": "did:plc:alice123",
  "collection": "app.bsky.feed.post",
  "record": { "text": "Hello world" }
}
```

**Questions:**
- Is this request really from Alice?
- Is the client authorized to post on Alice's behalf?
- How do we prevent replay attacks?
- What if Alice's password is stolen?

Without authentication, anyone could:
- Post as any user
- Delete others' content
- Access private data
- Impersonate accounts

### Traditional Approaches (And Why They're Not Enough)

**Session cookies:**
- Tied to web browsers only
- Don't work for mobile apps or third-party clients
- Hard to share across domains

**API keys:**
- No standard format
- Usually long-lived (security risk)
- No fine-grained permissions

**Username/password on every request:**
- Password exposed repeatedly
- No way to revoke specific client access
- Can't delegate permission to third-party apps

### The Solution: OAuth 2.1 + JWT

**OAuth 2.1** provides:
- Standard authorization flow
- Secure token exchange
- Fine-grained scopes (permissions)
- Third-party app support

**JWT (JSON Web Tokens)** provides:
- Self-contained tokens (no database lookup needed)
- Cryptographic signatures (tamper-proof)
- Expiration built-in
- Standard format across systems

**Together:** Clients authenticate once, receive a signed token, use it for all subsequent requests until expiration.

---

## Understanding JWT Structure

### The Three Parts

A JWT consists of three Base64URL-encoded parts separated by dots:

```
eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJkaWQ6cGxjOnBkczEyMyIsInN1YiI6ImRpZDpwbGM6YWxpY2UxMjMiLCJleHAiOjE3MDAwMDAwMDB9.MEUCIQDx...signature...
└──────────────────────────────┘ └────────────────────────────────────────────────────────────────────────────┘ └───────────────┘
          Header                                          Payload                                                 Signature
```

**Structure:**
```
header.payload.signature
  │      │        │
  ▼      ▼        ▼
base64url(JSON) . base64url(JSON) . base64url(bytes)
```

Let's break down each part.

---

## Part 1: The Header

### What It Contains

The header describes the token format and signing algorithm:

```json
{
  "alg": "ES256K",     // Algorithm: ECDSA with secp256k1
  "typ": "JWT",        // Type: JSON Web Token
  "kid": "signing-key" // Key ID: which key was used
}
```

**Field breakdown:**

| Field | Purpose | Value for AT Protocol |
|-------|---------|----------------------|
| `alg` | Signing algorithm | `ES256K` (secp256k1 ECDSA) |
| `typ` | Token type | `JWT` |
| `kid` | Key identifier | DID of signing key (optional) |

### Why ES256K?

AT Protocol uses **ES256K** because:
- Uses secp256k1 (same as DIDs and Bitcoin)
- Generates compact signatures (64 bytes)
- Fast verification
- Compatible with our existing crypto stack from Chapter 8

**Other common algorithms (not used in AT Protocol):**
- `RS256`: RSA signatures (larger, slower)
- `HS256`: HMAC with shared secret (symmetric, not public key)
- `ES256`: ECDSA with P-256 curve (different curve than secp256k1)

### Encoding the Header

```objc
// Create header dictionary
NSDictionary *header = @{
    @"alg": @"ES256K",
    @"typ": @"JWT"
};

// Serialize to JSON
NSData *headerJSON = [NSJSONSerialization dataWithJSONObject:header
                                                     options:0
                                                       error:nil];

// Encode with Base64URL
NSString *encodedHeader = [self base64URLEncode:headerJSON];
// Result: "eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ"
```

**Note:** Standard Base64 uses `+/=`, but Base64URL uses `-_` (no padding) to be URL-safe.

---

## Part 2: The Payload (Claims)

### What It Contains

The payload holds **claims**—assertions about the user and token:

```json
{
  "iss": "did:plc:pds123",           // Issuer: who issued this token (PDS)
  "sub": "did:plc:alice456",         // Subject: who this token represents (user)
  "aud": "https://api.example.com",  // Audience: who should accept this token
  "exp": 1700000000,                 // Expiration: Unix timestamp
  "iat": 1699996400,                 // Issued at: Unix timestamp
  "scope": "atproto transition:generic" // Scopes: permissions
}
```

### Standard JWT Claims

| Claim | Name | Purpose | Example |
|-------|------|---------|---------|
| `iss` | Issuer | Who created the token | `did:plc:your-pds` |
| `sub` | Subject | Who the token is about | `did:plc:alice456` |
| `aud` | Audience | Who should accept it | `https://api.example.com` |
| `exp` | Expiration | When it expires | `1700000000` (Unix timestamp) |
| `iat` | Issued At | When it was created | `1699996400` (Unix timestamp) |
| `nbf` | Not Before | Not valid before this time | `1699996400` (optional) |

### AT Protocol Custom Claims

| Claim | Purpose | Example |
|-------|---------|---------|
| `scope` | OAuth permissions | `"atproto transition:generic"` |
| `cnf` | Confirmation (DPoP) | Key thumbprint for DPoP binding |

### The Intuition: A Signed Ticket

Think of a JWT like a **concert ticket**:
- **Issuer (`iss`):** Ticketmaster (who printed it)
- **Subject (`sub`):** Your name (who it's for)
- **Audience (`aud`):** The venue (where it's valid)
- **Expiration (`exp`):** The concert date (when it expires)
- **Signature:** Hologram/watermark (proves authenticity)

Just like a ticket, the JWT is self-contained—the bouncer (API server) can verify it without calling Ticketmaster (no database lookup).

### Encoding the Payload

```objc
// Calculate expiration (1 hour from now)
NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
NSTimeInterval expiration = now + 3600;

// Create payload dictionary
NSDictionary *payload = @{
    @"iss": @"did:plc:your-pds",
    @"sub": @"did:plc:alice456",
    @"iat": @((long)now),
    @"exp": @((long)expiration),
    @"scope": @"atproto transition:generic"
};

// Serialize to JSON
NSData *payloadJSON = [NSJSONSerialization dataWithJSONObject:payload
                                                      options:0
                                                        error:nil];

// Encode with Base64URL
NSString *encodedPayload = [self base64URLEncode:payloadJSON];
```

**Important:** Expiration should be:
- **Access tokens:** Short-lived (1-2 hours)
- **Refresh tokens:** Long-lived (days to months)

---

## Part 3: The Signature

### What It Is

The signature proves:
1. **Authenticity:** Token was created by someone with the private key
2. **Integrity:** Token hasn't been tampered with

**How it's created:**
```
signing_input = base64url(header) + "." + base64url(payload)
hash = SHA256(signing_input)
signature = sign(hash, private_key)  // secp256k1 ECDSA
```

### Why Sign Header + Payload?

If we only signed the payload:
- Attacker could change `alg` to `none` (no signature required)
- Or change `alg` to `HS256` and use public key as HMAC secret

**By signing both parts together**, we ensure the algorithm and payload can't be modified.

### Creating the Signature

```objc
// 1. Build signing input
NSString *signingInput = [NSString stringWithFormat:@"%@.%@",
                          encodedHeader, encodedPayload];

// 2. Hash the signing input (SHA-256)
NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
unsigned char hash[CC_SHA256_DIGEST_LENGTH];
CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, hash);
NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

// 3. Sign with secp256k1 private key
NSError *error = nil;
NSData *signature = [[Secp256k1 shared] signHash:hashData
                                  withPrivateKey:privateKey
                                           error:&error];

// 4. Base64URL encode the signature
NSString *encodedSignature = [self base64URLEncode:signature];
```

**Result:** A 64-byte signature (secp256k1 produces compact signatures).

### The Complete JWT

```objc
NSString *jwt = [NSString stringWithFormat:@"%@.%@.%@",
                 encodedHeader, encodedPayload, encodedSignature];

// Example:
// eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJkaWQ6cGxjOnBkczEyMyIsInN1YiI6ImRpZDpwbGM6YWxpY2UxMjMiLCJleHAiOjE3MDAwMDAwMDB9.MEUCIQDxR3q...
```

---

## Base64URL Encoding (URL-Safe Base64)

### The Problem with Standard Base64

Standard Base64 uses these characters:
```
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=
                                                                   │││
                                                                   └┴┴─ Problems in URLs
```

**Problems:**
- `+` and `/` have special meaning in URLs
- `=` used for padding (ugly in URLs)

**Example:**
```
Standard Base64: "hello+world/test=="
In URL: ?token=hello+world/test==
         │      └────────────┘
         │      Browser might mangle this!
         └─ Query parameter
```

### The Solution: Base64URL

**Base64URL changes:**
- Replace `+` with `-`
- Replace `/` with `_`
- Remove `=` padding

```
Standard:  hello+world/test==
Base64URL: hello-world_test    ← Safe in URLs
```

### Implementation

```objc
+ (NSString *)base64URLEncode:(NSData *)data {
    // 1. Standard Base64 encode
    NSString *base64 = [data base64EncodedStringWithOptions:0];

    // 2. Make URL-safe
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

    // 3. Remove padding
    base64 = [base64 stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"="]];

    return base64;
}

+ (NSData *)base64URLDecode:(NSString *)string {
    // 1. Restore standard Base64 characters
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-"
                            withString:@"+"
                               options:0
                                 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_"
                            withString:@"/"
                               options:0
                                 range:NSMakeRange(0, base64.length)];

    // 2. Add padding back (must be multiple of 4)
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }

    // 3. Decode
    return [[NSData alloc] initWithBase64EncodedString:base64
                                               options:0];
}
```

**Padding calculation:**
Base64 output length must be multiple of 4. If not:
- 1 byte short → add `=`
- 2 bytes short → add `==`
- 3 bytes short → impossible (Base64 encodes 3 bytes → 4 chars)

---

## Implementing JWT Classes

### Version 1: Basic Structure

Let's start with the core data structures:

```objc
// JWT.h
@interface JWTHeader : NSObject
@property (nonatomic, copy) NSString *alg;   // Algorithm ("ES256K")
@property (nonatomic, copy) NSString *typ;   // Type ("JWT")
@property (nonatomic, copy, nullable) NSString *kid;  // Key ID (optional)

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface JWTPayload : NSObject
@property (nonatomic, copy) NSString *iss;      // Issuer
@property (nonatomic, copy) NSString *sub;      // Subject
@property (nonatomic, copy, nullable) NSString *aud;  // Audience (optional)
@property (nonatomic, strong) NSDate *exp;      // Expiration
@property (nonatomic, strong) NSDate *iat;      // Issued at
@property (nonatomic, copy, nullable) NSString *scope;  // OAuth scopes

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface JWT : NSObject
@property (nonatomic, strong, readonly) JWTHeader *header;
@property (nonatomic, strong, readonly) JWTPayload *payload;
@property (nonatomic, copy, readonly) NSString *encodedSignature;

+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error;
- (NSString *)encodedToken;
- (NSString *)signingInput;
@end
```

**What this provides:**
- Type-safe representation of JWT parts
- Serialization to/from dictionaries
- Token encoding/decoding

**Limitations:**
- No signing or verification
- No validation logic
- Just data structures

### Version 2: Add Parsing

Now let's parse JWT tokens:

```objc
@implementation JWT

+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error {
    // 1. Split on dots
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"JWT must have 3 parts separated by dots"}];
        }
        return nil;
    }

    // 2. Decode header
    NSData *headerData = [self base64URLDecode:parts[0]];
    NSDictionary *headerDict = [NSJSONSerialization JSONObjectWithData:headerData
                                                               options:0
                                                                 error:error];
    if (!headerDict) return nil;
    JWTHeader *header = [JWTHeader fromDictionary:headerDict];

    // 3. Decode payload
    NSData *payloadData = [self base64URLDecode:parts[1]];
    NSDictionary *payloadDict = [NSJSONSerialization JSONObjectWithData:payloadData
                                                                options:0
                                                                  error:error];
    if (!payloadDict) return nil;
    JWTPayload *payload = [JWTPayload fromDictionary:payloadDict];

    // 4. Store signature (keep encoded)
    NSString *encodedSignature = parts[2];

    return [[JWT alloc] initWithHeader:header
                               payload:payload
                     encodedSignature:encodedSignature];
}

- (NSString *)encodedToken {
    // Reconstruct the token
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:[self.header toDictionary]
                                                         options:0
                                                           error:nil];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[self.payload toDictionary]
                                                          options:0
                                                            error:nil];

    return [NSString stringWithFormat:@"%@.%@.%@",
            [JWT base64URLEncode:headerData],
            [JWT base64URLEncode:payloadData],
            self.encodedSignature];
}

- (NSString *)signingInput {
    // The part that gets signed: header.payload
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:[self.header toDictionary]
                                                         options:0
                                                           error:nil];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[self.payload toDictionary]
                                                          options:0
                                                            error:nil];

    return [NSString stringWithFormat:@"%@.%@",
            [JWT base64URLEncode:headerData],
            [JWT base64URLEncode:payloadData]];
}

@end
```

**What changed:**
- Can parse JWT strings into structured objects
- Can reconstruct tokens from parts
- Provides signing input for verification

### The Production Implementation: JWT Minting

Here's the full JWT minting implementation:

```objc
// JWTMinter.h
@interface JWTMinter : NSObject

@property (nonatomic, copy) NSString *issuer;           // PDS DID
@property (nonatomic, strong) NSData *privateKey;       // secp256k1 private key
@property (nonatomic, assign) NSTimeInterval accessTokenExpiration;   // Default: 3600s
@property (nonatomic, assign) NSTimeInterval refreshTokenExpiration;  // Default: 2592000s (30 days)

- (nullable JWT *)mintAccessTokenForDID:(NSString *)userDID
                                 handle:(NSString *)handle
                                 scopes:(NSArray<NSString *> *)scopes
                                  error:(NSError **)error;

- (nullable JWT *)mintRefreshTokenForDID:(NSString *)userDID
                                  handle:(NSString *)handle
                                  scopes:(NSArray<NSString *> *)scopes
                                   error:(NSError **)error;

@end
```

```objc
// JWTMinter.m
@implementation JWTMinter

- (instancetype)init {
    if (self = [super init]) {
        self.accessTokenExpiration = 3600;         // 1 hour
        self.refreshTokenExpiration = 2592000;     // 30 days
    }
    return self;
}

- (nullable JWT *)mintAccessTokenForDID:(NSString *)userDID
                                 handle:(NSString *)handle
                                 scopes:(NSArray<NSString *> *)scopes
                                  error:(NSError **)error {
    return [self mintTokenForDID:userDID
                          handle:handle
                          scopes:scopes
                      expiration:self.accessTokenExpiration
                       tokenType:@"access"
                           error:error];
}

- (nullable JWT *)mintRefreshTokenForDID:(NSString *)userDID
                                  handle:(NSString *)handle
                                  scopes:(NSArray<NSString *> *)scopes
                                   error:(NSError **)error {
    return [self mintTokenForDID:userDID
                          handle:handle
                          scopes:scopes
                      expiration:self.refreshTokenExpiration
                       tokenType:@"refresh"
                           error:error];
}

- (nullable JWT *)mintTokenForDID:(NSString *)userDID
                           handle:(NSString *)handle
                           scopes:(NSArray<NSString *> *)scopes
                       expiration:(NSTimeInterval)expiration
                        tokenType:(NSString *)type
                            error:(NSError **)error {
    // 1. Build header
    JWTHeader *header = [[JWTHeader alloc] init];
    header.alg = @"ES256K";
    header.typ = @"JWT";
    // Optional: header.kid = self.issuer;  // Key identifier

    // 2. Build payload with timestamps
    NSDate *now = [NSDate date];
    NSDate *exp = [NSDate dateWithTimeIntervalSinceNow:expiration];

    JWTPayload *payload = [[JWTPayload alloc] init];
    payload.iss = self.issuer;          // PDS DID
    payload.sub = userDID;              // User DID
    payload.iat = now;                  // Issued at
    payload.exp = exp;                  // Expiration
    payload.scope = [scopes componentsJoinedByString:@" "];

    // 3. Create signing input (header.payload)
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:[header toDictionary]
                                                         options:0
                                                           error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[payload toDictionary]
                                                          options:0
                                                            error:error];
    if (!headerData || !payloadData) return nil;

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@",
                              [JWT base64URLEncode:headerData],
                              [JWT base64URLEncode:payloadData]];

    // 4. Hash the signing input (SHA-256)
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    // 5. Sign with secp256k1
    NSData *signature = [[Secp256k1 shared] signHash:hashData
                                      withPrivateKey:self.privateKey
                                               error:error];
    if (!signature) {
        NSLog(@"Failed to sign JWT: %@", *error);
        return nil;
    }

    // 6. Base64URL encode the signature
    NSString *encodedSignature = [JWT base64URLEncode:signature];

    // 7. Create and return JWT object
    return [[JWT alloc] initWithHeader:header
                               payload:payload
                     encodedSignature:encodedSignature];
}

@end
```

**Breaking this down:**

**Lines 1-22:** Token type methods
- `mintAccessToken`: Short-lived (1 hour), for API access
- `mintRefreshToken`: Long-lived (30 days), for renewing access tokens
- Both delegate to common `mintTokenForDID` method

**Lines 24-34:** Header and payload construction
- Header always uses `ES256K` (secp256k1)
- Payload includes issuer (PDS), subject (user), timestamps, scopes

**Lines 36-43:** Signing input
- Serialize header and payload to JSON
- Base64URL encode each part
- Concatenate with dot: `header.payload`

**Lines 45-49:** Hashing
- SHA-256 hash the signing input
- secp256k1 requires 32-byte hash input
- This is the same pattern we used for DIDs in Chapter 9

**Lines 51-57:** Signing
- Use secp256k1 to sign the hash
- Private key must match the issuer's signing key
- Signature is 64 bytes (32-byte r + 32-byte s components)

**Lines 59-65:** Final JWT construction
- Base64URL encode the signature
- Create JWT object with all three parts

💡 **Key Insight:** The token is self-contained—it includes all information needed for verification. No database lookup required!

⚠️ **Watch Out:** Never put sensitive data (passwords, private keys) in JWT payload. It's Base64-encoded, not encrypted—anyone can decode and read it.

---

## JWT Verification

### The Verification Process

To verify a JWT:
1. **Parse** the token into parts
2. **Check expiration** (is it still valid?)
3. **Check issuer** (is it from a trusted source?)
4. **Verify signature** (was it signed by issuer's private key?)

```objc
// JWTVerifier.h
@interface JWTVerifier : NSObject

@property (nonatomic, copy) NSString *expectedIssuer;  // Expected PDS DID
@property (nonatomic, strong) NSData *publicKey;       // Issuer's public key

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;

@end
```

```objc
// JWTVerifier.m
@implementation JWTVerifier

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error {
    // 1. Check expiration
    if ([jwt.payload.exp compare:[NSDate date]] == NSOrderedAscending) {
        // Token is expired (exp < now)
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorTokenExpired
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Token expired",
                                         @"expiration": jwt.payload.exp,
                                         @"now": [NSDate date]
                                     }];
        }
        return NO;
    }

    // 2. Check issuer
    if (![jwt.payload.iss isEqualToString:self.expectedIssuer]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidIssuer
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Invalid issuer",
                                         @"expected": self.expectedIssuer,
                                         @"actual": jwt.payload.iss
                                     }];
        }
        return NO;
    }

    // 3. Validate algorithm
    if (![jwt.header.alg isEqualToString:@"ES256K"]) {
        if (error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidAlgorithm
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Unsupported algorithm",
                                         @"algorithm": jwt.header.alg
                                     }];
        }
        return NO;
    }

    // 4. Verify signature
    NSString *signingInput = [jwt signingInput];  // "header.payload"
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    // Hash the signing input
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    // Decode the signature
    NSData *signature = [JWT base64URLDecode:jwt.encodedSignature];

    // Verify with secp256k1
    BOOL valid = [[Secp256k1 shared] verifySignature:signature
                                             forHash:hashData
                                       withPublicKey:self.publicKey
                                               error:error];

    if (!valid) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:JWTErrorDomain
                                         code:JWTErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Signature verification failed"}];
        }
        return NO;
    }

    return YES;  // All checks passed!
}

@end
```

**Breaking this down:**

**Lines 4-18:** Expiration check
- Compare expiration date to current time
- If expired, return error with details
- **Security:** Prevents replay of old tokens

**Lines 20-32:** Issuer validation
- Ensure token was issued by expected PDS
- Prevents tokens from other systems being used
- **Security:** Prevents token substitution attacks

**Lines 34-44:** Algorithm validation
- Must be ES256K (secp256k1)
- **Critical security check:** Prevents "none" algorithm attack
- Attacker could change `alg` to `"none"` and remove signature

**Lines 46-73:** Signature verification
- Reconstruct signing input (header.payload)
- Hash with SHA-256
- Decode signature from Base64URL
- Verify using issuer's public key
- **Security:** Proves token authenticity and integrity

💡 **Key Insight:** Verification requires only the public key. The PDS can verify tokens without accessing the database—this is why JWTs are "stateless."

---

## OAuth 2.1 Authorization Code Flow

### The Complete Flow

```
┌─────────┐                                           ┌─────────┐
│         │                                           │         │
│  User   │                                           │   PDS   │
│ (Alice) │                                           │ (Server)│
└────┬────┘                                           └────┬────┘
     │                                                     │
     │  1. Initiate OAuth (redirect to /oauth/authorize)  │
     ├────────────────────────────────────────────────────►│
     │     client_id, redirect_uri, scope, code_challenge │
     │                                                     │
     │  2. Login & Consent UI                             │
     │◄────────────────────────────────────────────────────┤
     │                                                     │
     │  3. User authenticates and approves                │
     ├────────────────────────────────────────────────────►│
     │     (username, password, approval)                  │
     │                                                     │
     │  4. Redirect to callback with authorization code   │
     │◄────────────────────────────────────────────────────┤
     │     redirect_uri?code=AUTH_CODE                    │
     │                                                     │
┌────▼────┐                                           ┌────▼────┐
│         │                                           │         │
│ Client  │  5. Exchange code for tokens             │   PDS   │
│   App   ├───────────────────────────────────────────►        │
│         │     POST /oauth/token                     │         │
│         │     code, code_verifier, client_id        │         │
│         │                                           │         │
│         │  6. Tokens response                       │         │
│         │◄───────────────────────────────────────────┤         │
│         │     access_token, refresh_token, expires_in│         │
└─────────┘                                           └─────────┘
```

### Step 1: Authorization Request

Client initiates OAuth by redirecting user to PDS:

```
GET /oauth/authorize?
    response_type=code&
    client_id=https://app.example.com&
    redirect_uri=https://app.example.com/callback&
    scope=atproto+transition:generic&
    code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&
    code_challenge_method=S256&
    state=abc123
```

**Parameters:**

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `response_type` | Always `code` for auth code flow | `code` |
| `client_id` | Identifies the client app | `https://app.example.com` |
| `redirect_uri` | Where to send auth code | `https://app.example.com/callback` |
| `scope` | Requested permissions | `atproto transition:generic` |
| `code_challenge` | PKCE challenge (Base64URL) | `E9Melhoa2Ow...` |
| `code_challenge_method` | How challenge was created | `S256` (SHA-256) |
| `state` | Anti-CSRF token | `abc123` (random) |

### Step 2-3: User Authentication & Consent

PDS shows login UI, user authenticates, approves scopes.

### Step 4: Authorization Code Issued

PDS redirects back to client with code:

```
https://app.example.com/callback?
    code=SplxlOBeZQQYbYS6WxSbIA&
    state=abc123
```

**Authorization code:**
- Short-lived (5-10 minutes)
- Single-use only
- Bound to PKCE verifier

### Step 5: Token Exchange

Client exchanges code for tokens:

```http
POST /oauth/token HTTP/1.1
Host: pds.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&
code=SplxlOBeZQQYbYS6WxSbIA&
client_id=https://app.example.com&
redirect_uri=https://app.example.com/callback&
code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
```

### Step 6: Token Response

PDS returns tokens:

```json
{
  "access_token": "eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ.ey...",
  "refresh_token": "eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ.ey...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "atproto transition:generic"
}
```

---

## PKCE (Proof Key for Code Exchange)

### The Problem: Authorization Code Interception

Without PKCE, an attacker could:
1. Intercept the authorization code
2. Exchange it for tokens
3. Access user's account

**Scenario:**
```
User's phone → Authorization code → Malicious app intercepts → Exchanges for tokens
```

### The Solution: PKCE

**PKCE binds the authorization code to the client** using a cryptographic challenge.

**How it works:**

```
Client generates:
  code_verifier = random 43-128 character string

Client computes:
  code_challenge = BASE64URL(SHA256(code_verifier))

Authorization request:
  Include code_challenge

Token exchange:
  Include code_verifier

PDS validates:
  SHA256(received_code_verifier) == stored_code_challenge
```

### Implementing PKCE

```objc
// Generate code verifier (random string)
+ (NSString *)generateCodeVerifier {
    // 43-128 characters, URL-safe
    NSUInteger length = 64;  // Common choice
    NSMutableData *randomData = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, length, randomData.mutableBytes);

    return [[self base64URLEncode:randomData] substringToIndex:86];  // 86 chars ≈ 64 bytes
}

// Compute code challenge
+ (NSString *)computeCodeChallenge:(NSString *)verifier {
    // SHA-256 hash the verifier
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    // Base64URL encode the hash
    return [self base64URLEncode:hashData];
}

// Verify code verifier matches challenge
+ (BOOL)verifyCodeVerifier:(NSString *)verifier
                 challenge:(NSString *)challenge {
    NSString *computed = [self computeCodeChallenge:verifier];
    return [computed isEqualToString:challenge];
}
```

**Example:**

```objc
// Client side (before authorization):
NSString *verifier = [OAuth generateCodeVerifier];
// Result: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

NSString *challenge = [OAuth computeCodeChallenge:verifier];
// Result: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

// Store verifier securely, send challenge in auth request

// Server side (during token exchange):
BOOL valid = [OAuth verifyCodeVerifier:receivedVerifier
                             challenge:storedChallenge];
// Only the client that initiated auth has the correct verifier
```

💡 **Key Insight:** Even if an attacker intercepts the authorization code, they can't exchange it without the code verifier (which never leaves the client).

---

## Implementing OAuth Token Endpoint

### The Handler

```objc
// OAuth2Handler.h
@interface OAuth2Handler : NSObject

@property (nonatomic, strong) JWTMinter *jwtMinter;
@property (nonatomic, strong) PDSDatabase *database;

- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response;

@end
```

```objc
// OAuth2Handler.m
@implementation OAuth2Handler

- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response {
    NSDictionary *body = [request formBody];  // Parse application/x-www-form-urlencoded
    NSString *grantType = body[@"grant_type"];

    if ([grantType isEqualToString:@"authorization_code"]) {
        [self handleAuthorizationCodeGrant:body response:response];
    } else if ([grantType isEqualToString:@"refresh_token"]) {
        [self handleRefreshTokenGrant:body response:response];
    } else {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"unsupported_grant_type",
            @"error_description": @"Only authorization_code and refresh_token supported"
        }];
    }
}

- (void)handleAuthorizationCodeGrant:(NSDictionary *)body
                            response:(HttpResponse *)response {
    // 1. Extract parameters
    NSString *code = body[@"code"];
    NSString *clientId = body[@"client_id"];
    NSString *redirectUri = body[@"redirect_uri"];
    NSString *codeVerifier = body[@"code_verifier"];

    // 2. Validate authorization code
    NSError *error = nil;
    AuthorizationCode *authCode = [self.database getAuthorizationCode:code error:&error];

    if (!authCode) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_grant",
            @"error_description": @"Invalid or expired authorization code"
        }];
        return;
    }

    // 3. Validate PKCE
    if (![OAuth verifyCodeVerifier:codeVerifier challenge:authCode.codeChallenge]) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_grant",
            @"error_description": @"Code verifier does not match challenge"
        }];
        return;
    }

    // 4. Validate client_id and redirect_uri match
    if (![clientId isEqualToString:authCode.clientId] ||
        ![redirectUri isEqualToString:authCode.redirectUri]) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_grant",
            @"error_description": @"Client ID or redirect URI mismatch"
        }];
        return;
    }

    // 5. Mint tokens
    JWT *accessToken = [self.jwtMinter mintAccessTokenForDID:authCode.userDID
                                                      handle:authCode.handle
                                                      scopes:authCode.scopes
                                                       error:&error];

    JWT *refreshToken = [self.jwtMinter mintRefreshTokenForDID:authCode.userDID
                                                         handle:authCode.handle
                                                         scopes:authCode.scopes
                                                          error:&error];

    if (!accessToken || !refreshToken) {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"server_error",
            @"error_description": @"Failed to mint tokens"
        }];
        return;
    }

    // 6. Invalidate authorization code (single-use)
    [self.database deleteAuthorizationCode:code error:nil];

    // 7. Return tokens
    response.statusCode = 200;
    [response setJsonBody:@{
        @"access_token": [accessToken encodedToken],
        @"refresh_token": [refreshToken encodedToken],
        @"token_type": @"Bearer",
        @"expires_in": @3600,
        @"scope": [authCode.scopes componentsJoinedByString:@" "]
    }];
}

@end
```

**Breaking this down:**

**Lines 1-19:** Grant type routing
- Support two grant types: `authorization_code` (initial) and `refresh_token` (renewal)
- Return error for unsupported types

**Lines 21-40:** Parameter extraction and code validation
- Extract code, client_id, redirect_uri, code_verifier from request
- Look up authorization code in database
- Return error if code not found or expired

**Lines 42-52:** PKCE verification
- Compute SHA-256 of code_verifier
- Compare to stored code_challenge
- **Critical security check:** Prevents code interception attacks

**Lines 54-65:** Client validation
- Ensure client_id and redirect_uri match what was registered
- Prevents token substitution attacks

**Lines 67-83:** Token minting
- Create access token (short-lived)
- Create refresh token (long-lived)
- Return error if minting fails

**Lines 85-86:** Authorization code invalidation
- **Single-use:** Delete code after successful exchange
- Prevents replay attacks

**Lines 88-96:** Success response
- Return both tokens
- Include expiration time
- Specify token type ("Bearer" for Authorization header)

---

## Refresh Token Flow

### Why Refresh Tokens?

**Problem:** Access tokens are short-lived (1 hour). Users shouldn't have to log in every hour!

**Solution:** Refresh tokens let clients get new access tokens without re-authentication.

```
Access token expires (1 hour) → Use refresh token → Get new access token
```

### Implementing Refresh Grant

```objc
- (void)handleRefreshTokenGrant:(NSDictionary *)body
                       response:(HttpResponse *)response {
    // 1. Extract and parse refresh token
    NSString *refreshTokenString = body[@"refresh_token"];
    NSError *error = nil;
    JWT *refreshToken = [JWT jwtWithToken:refreshTokenString error:&error];

    if (!refreshToken) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_grant",
            @"error_description": @"Invalid refresh token format"
        }];
        return;
    }

    // 2. Verify refresh token
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.expectedIssuer = self.jwtMinter.issuer;
    verifier.publicKey = self.jwtMinter.publicKey;  // Derive from private key

    if (![verifier verifyJWT:refreshToken error:&error]) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_grant",
            @"error_description": [NSString stringWithFormat:@"Token verification failed: %@",
                                   error.localizedDescription]
        }];
        return;
    }

    // 3. Check token hasn't been revoked
    if ([self.database isRefreshTokenRevoked:refreshTokenString error:nil]) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_grant",
            @"error_description": @"Refresh token has been revoked"
        }];
        return;
    }

    // 4. Mint new access token (same subject and scopes)
    NSArray *scopes = [refreshToken.payload.scope componentsSeparatedByString:@" "];
    JWT *newAccessToken = [self.jwtMinter mintAccessTokenForDID:refreshToken.payload.sub
                                                          handle:nil  // Could fetch from DB
                                                          scopes:scopes
                                                           error:&error];

    if (!newAccessToken) {
        response.statusCode = 500;
        [response setJsonBody:@{
            @"error": @"server_error",
            @"error_description": @"Failed to mint access token"
        }];
        return;
    }

    // 5. Optional: Rotate refresh token (recommended for security)
    JWT *newRefreshToken = [self.jwtMinter mintRefreshTokenForDID:refreshToken.payload.sub
                                                            handle:nil
                                                            scopes:scopes
                                                             error:&error];

    if (newRefreshToken) {
        // Revoke old refresh token
        [self.database revokeRefreshToken:refreshTokenString error:nil];
    }

    // 6. Return new tokens
    response.statusCode = 200;
    NSMutableDictionary *responseBody = [@{
        @"access_token": [newAccessToken encodedToken],
        @"token_type": @"Bearer",
        @"expires_in": @3600
    } mutableCopy];

    if (newRefreshToken) {
        responseBody[@"refresh_token"] = [newRefreshToken encodedToken];
    }

    [response setJsonBody:responseBody];
}
```

**Breaking this down:**

**Lines 1-15:** Parse refresh token
- Extract token string from request
- Parse into JWT object
- Return error if malformed

**Lines 17-29:** Verify refresh token
- Check signature with PDS public key
- Validate expiration
- Ensure issuer matches

**Lines 31-39:** Revocation check
- Check database for revoked tokens
- **Security:** Users can revoke tokens when devices are lost
- Return error if revoked

**Lines 41-53:** Mint new access token
- Same subject (user DID) as refresh token
- Same scopes (permissions)
- Fresh expiration (1 hour from now)

**Lines 55-67:** Refresh token rotation (optional but recommended)
- Issue new refresh token
- Revoke old refresh token
- **Security:** Limits damage if refresh token leaks

**Lines 69-82:** Success response
- Return new access token
- Optionally return new refresh token
- Client replaces old tokens with new ones

💡 **Key Insight:** Refresh token rotation means each refresh token is single-use. If an attacker tries to reuse a revoked token, the PDS detects the compromise.

---

## Common Mistakes

### Mistake 1: Not Validating Algorithm

❌ **What people do:**
```objc
// WRONG: Trust header without validation
JWT *jwt = [JWT jwtWithToken:tokenString error:nil];
// Directly verify without checking algorithm
[self verifySignature:jwt];
```

**Why this fails:**
- Attacker changes `alg` to `"none"` (no signature required)
- Or changes to `"HS256"` and uses public key as HMAC secret
- Signature verification bypassed!

✅ **Correct approach:**
```objc
// RIGHT: Validate algorithm before verification
if (![jwt.header.alg isEqualToString:@"ES256K"]) {
    return NO;  // Reject token
}
// Only then verify signature
```

**Why this works:**
- Ensures only expected algorithm is accepted
- Prevents algorithm substitution attacks
- Critical security measure!

### Mistake 2: Long-Lived Access Tokens

❌ **What people do:**
```objc
// WRONG: Access token valid for 30 days
self.accessTokenExpiration = 30 * 24 * 60 * 60;  // 30 days
```

**Why this fails:**
- If token leaks, attacker has 30 days of access
- No way to revoke access without database lookups (defeats JWT purpose)
- Increases blast radius of compromise

✅ **Correct approach:**
```objc
// RIGHT: Short-lived access tokens, long-lived refresh tokens
self.accessTokenExpiration = 3600;          // 1 hour
self.refreshTokenExpiration = 30 * 24 * 3600;  // 30 days
```

**Why this works:**
- Leaked access token expires quickly
- Refresh tokens can be revoked in database
- Balance between security and user experience

### Mistake 3: Including Sensitive Data in JWT

❌ **What people do:**
```objc
// WRONG: Storing password in payload
payload.password = user.passwordHash;  // DON'T DO THIS!
```

**Why this fails:**
- JWT payload is Base64-encoded, **not encrypted**
- Anyone can decode and read it:
  ```
  atob("eyJwYXNzd29yZCI6InNlY3JldCJ9")  // → {"password":"secret"}
  ```
- Sensitive data exposed to anyone with token

✅ **Correct approach:**
```objc
// RIGHT: Only include necessary, non-sensitive claims
payload.sub = user.did;        // ✓ Public identifier
payload.scope = @"atproto";    // ✓ Public permission
// Never include passwords, keys, or private data
```

**Why this works:**
- JWTs are for authentication, not encryption
- Only include data that's okay to be public
- Sensitive data stays server-side

### Mistake 4: Not Checking Expiration

❌ **What people do:**
```objc
// WRONG: Only verify signature
BOOL valid = [self verifySignature:jwt];
if (valid) {
    // Grant access without checking expiration!
}
```

**Why this fails:**
- Expired tokens still have valid signatures
- Attacker can reuse old tokens indefinitely
- No time-based access control

✅ **Correct approach:**
```objc
// RIGHT: Check expiration BEFORE verifying signature
if ([jwt.payload.exp compare:[NSDate date]] == NSOrderedAscending) {
    return NO;  // Expired
}

// Then verify signature
BOOL valid = [self verifySignature:jwt];
```

**Why this works:**
- Expiration check is quick (no crypto)
- Fail fast on expired tokens
- Prevents replay of old valid tokens

---

## Token Lifecycle Visualization

```
┌─────────────────────────────────────────────────────────────────┐
│                     Token Lifecycle                             │
└─────────────────────────────────────────────────────────────────┘

1. Initial Authentication
   User → OAuth Flow → Authorization Code → Token Exchange

   Result: access_token (1h) + refresh_token (30d)

2. Using Access Token
   Client → API Request with "Authorization: Bearer <access_token>"
   Server → Verify token → Grant access

   Repeat for ~1 hour

3. Access Token Expires
   Client → API Request
   Server → Returns 401 Unauthorized (token expired)

4. Refresh Flow
   Client → POST /oauth/token with refresh_token
   Server → Verify refresh token → Mint new access token

   Result: new access_token (1h) + new refresh_token (30d)

5. Refresh Token Expires or Revoked
   Client → POST /oauth/token
   Server → Returns 401 Unauthorized (refresh token invalid)

   User must re-authenticate (back to step 1)

┌─────────────────────────────────────────────────────────────────┐
│                       Token Security                            │
└─────────────────────────────────────────────────────────────────┘

✓ Access Token:
  - Short-lived (1 hour)
  - Stateless (no database lookup)
  - Sent on every request
  - Higher exposure risk → shorter lifetime

✓ Refresh Token:
  - Long-lived (30 days)
  - Can be revoked (database-backed)
  - Sent rarely (only for refresh)
  - Lower exposure risk → longer lifetime okay
```

---

## Putting It All Together: Complete Example

### Scenario: User Signs In to Third-Party App

```objc
// === CLIENT SIDE ===

// 1. Generate PKCE challenge
NSString *codeVerifier = [OAuth generateCodeVerifier];
NSString *codeChallenge = [OAuth computeCodeChallenge:codeVerifier];
NSString *state = [[NSUUID UUID] UUIDString];

// 2. Redirect user to PDS authorization endpoint
NSURL *authURL = [NSURL URLWithString:[NSString stringWithFormat:
    @"https://pds.example.com/oauth/authorize?"
    @"response_type=code&"
    @"client_id=https://myapp.example.com&"
    @"redirect_uri=https://myapp.example.com/callback&"
    @"scope=atproto+transition:generic&"
    @"code_challenge=%@&"
    @"code_challenge_method=S256&"
    @"state=%@",
    codeChallenge, state]];

[[NSWorkspace sharedWorkspace] openURL:authURL];

// 3. Handle callback (user approved, PDS redirected back)
// URL: https://myapp.example.com/callback?code=AUTH_CODE&state=...

- (void)handleCallback:(NSString *)authCode state:(NSString *)returnedState {
    // Verify state matches (CSRF protection)
    if (![returnedState isEqualToString:state]) {
        NSLog(@"State mismatch! Possible CSRF attack.");
        return;
    }

    // 4. Exchange authorization code for tokens
    NSDictionary *tokenRequest = @{
        @"grant_type": @"authorization_code",
        @"code": authCode,
        @"client_id": @"https://myapp.example.com",
        @"redirect_uri": @"https://myapp.example.com/callback",
        @"code_verifier": codeVerifier  // PKCE verification
    };

    [self postJSON:@"https://pds.example.com/oauth/token"
              body:tokenRequest
        completion:^(NSDictionary *response, NSError *error) {
            if (error) {
                NSLog(@"Token exchange failed: %@", error);
                return;
            }

            // 5. Store tokens securely
            NSString *accessToken = response[@"access_token"];
            NSString *refreshToken = response[@"refresh_token"];

            [self.keychain storeAccessToken:accessToken];
            [self.keychain storeRefreshToken:refreshToken];

            NSLog(@"Authentication successful!");
        }];
}

// === SERVER SIDE (PDS) ===

- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response {
    NSDictionary *body = [request formBody];
    NSString *code = body[@"code"];
    NSString *codeVerifier = body[@"code_verifier"];

    // 1. Look up authorization code
    AuthorizationCode *authCode = [self.database getAuthorizationCode:code];
    if (!authCode) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"invalid_grant"}];
        return;
    }

    // 2. Verify PKCE
    if (![OAuth verifyCodeVerifier:codeVerifier challenge:authCode.codeChallenge]) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"invalid_grant"}];
        return;
    }

    // 3. Mint tokens
    JWT *accessToken = [self.jwtMinter mintAccessTokenForDID:authCode.userDID
                                                      handle:authCode.handle
                                                      scopes:authCode.scopes
                                                       error:nil];
    JWT *refreshToken = [self.jwtMinter mintRefreshTokenForDID:authCode.userDID
                                                         handle:authCode.handle
                                                         scopes:authCode.scopes
                                                          error:nil];

    // 4. Invalidate authorization code
    [self.database deleteAuthorizationCode:code error:nil];

    // 5. Return tokens
    response.statusCode = 200;
    [response setJsonBody:@{
        @"access_token": [accessToken encodedToken],
        @"refresh_token": [refreshToken encodedToken],
        @"token_type": @"Bearer",
        @"expires_in": @3600
    }];
}

// === CLIENT USING ACCESS TOKEN ===

- (void)makeAPIRequest {
    NSString *accessToken = [self.keychain getAccessToken];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://pds.example.com/xrpc/com.atproto.repo.getRecord"]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken]
   forHTTPHeaderField:@"Authorization"];

    [self sendRequest:request completion:^(NSData *data, NSError *error) {
        // Handle response
    }];
}
```

**Flow summary:**
1. Client generates PKCE verifier/challenge
2. Redirects user to PDS for authentication
3. User logs in and approves
4. PDS redirects back with authorization code
5. Client exchanges code + verifier for tokens
6. Client stores tokens securely
7. Client uses access token for API requests
8. When access token expires, client uses refresh token to get new one

---

## Exercises

### 📝 Exercise 1: Decode a JWT by Hand

Given this JWT:
```
eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJkaWQ6cGxjOnBkczEyMyIsInN1YiI6ImRpZDpwbGM6YWxpY2UxMjMiLCJleHAiOjE3MDAwMDAwMDB9.signature_here
```

**Tasks:**
1. Split into three parts
2. Base64URL decode the header
3. Base64URL decode the payload
4. What algorithm is used?
5. Who issued this token?
6. When does it expire?

<details>
<summary>Hint</summary>

- Split on `.` characters
- Use an online Base64 decoder (add padding if needed)
- `exp` is a Unix timestamp (seconds since 1970)

</details>

<details>
<summary>Solution</summary>

**Part 1 (Header):**
```
eyJhbGciOiJFUzI1NksiLCJ0eXAiOiJKV1QifQ
→ {"alg":"ES256K","typ":"JWT"}
```

**Part 2 (Payload):**
```
eyJpc3MiOiJkaWQ6cGxjOnBkczEyMyIsInN1YiI6ImRpZDpwbGM6YWxpY2UxMjMiLCJleHAiOjE3MDAwMDAwMDB9
→ {"iss":"did:plc:pds123","sub":"did:plc:alice123","exp":1700000000}
```

**Answers:**
1. Algorithm: ES256K (secp256k1)
2. Issuer: did:plc:pds123
3. Expiration: 1700000000 → November 14, 2023

</details>

### 📝 Exercise 2: Implement Expiration Check

Write a method that checks if a JWT has expired:

```objc
- (BOOL)isJWTExpired:(JWT *)jwt {
    // Your code here
}
```

**Requirements:**
- Return YES if expired
- Return NO if still valid
- Handle edge case where exp is exactly now

<details>
<summary>Hint</summary>

Compare `jwt.payload.exp` to `[NSDate date]` using `compare:`.

</details>

<details>
<summary>Solution</summary>

```objc
- (BOOL)isJWTExpired:(JWT *)jwt {
    NSDate *now = [NSDate date];
    NSComparisonResult result = [jwt.payload.exp compare:now];

    // exp < now → Expired
    // exp >= now → Still valid
    return (result == NSOrderedAscending);
}
```

**Explanation:**
- `NSOrderedAscending`: exp < now (expired)
- `NSOrderedSame`: exp == now (treat as expired for safety)
- `NSOrderedDescending`: exp > now (valid)

</details>

### 📝 Exercise 3: Design Token Rotation Strategy

**Scenario:** You're implementing a mobile app. The app stores tokens on device.

**Design questions:**
1. Where should you store the refresh token? (Plaintext file? Encrypted? Keychain?)
2. When should you refresh the access token? (Wait for 401? Proactively before expiration?)
3. What happens if the refresh token expires while app is backgrounded?

**Consider:**
- Security vs convenience tradeoffs
- Background task limitations
- Network failure scenarios

<details>
<summary>Hint</summary>

**Storage:** Use system keychain (Keychain Services on iOS/macOS) for secure storage.

**Proactive refresh:** Check token expiration before each request, refresh if < 5 minutes remaining.

**Background expiration:** On app foreground, check token validity. If expired, prompt user to re-authenticate.

</details>

---

## Connection to AT Protocol

### How OAuth & JWT Enable Federation

In AT Protocol, OAuth and JWT are critical for:

1. **Client Authentication**
   - Mobile apps, web apps, third-party clients
   - Standard OAuth flow works across all client types
   - No passwords stored on devices

2. **Cross-PDS Operations**
   - User on pds-a.example.com can authenticate to app on pds-b.example.com
   - JWT issuer (`iss`) identifies which PDS minted the token
   - Signature verifies token authenticity

3. **Scoped Permissions**
   - `atproto`: Full AT Protocol access
   - `transition:generic`: Transitional generic scope
   - Future: Fine-grained scopes per-operation

4. **Stateless Verification**
   - AppViews can verify JWTs without calling PDS
   - Reduces latency and load
   - Scales better than session-based auth

### DID Integration

DIDs and JWTs work together:

```
JWT Payload:
{
  "iss": "did:plc:pds-did",      // PDS that issued token
  "sub": "did:plc:user-did"      // User the token represents
}

Verification:
1. Resolve issuer DID → Get PDS's signing key
2. Verify JWT signature with that key
3. Check subject DID matches requested repo
```

This cryptographically binds tokens to DIDs—no centralized identity provider needed!

---

## Summary

In this chapter, you learned:

- ✅ **JWT structure:** Three Base64URL-encoded parts (header.payload.signature)
- ✅ **Base64URL encoding:** URL-safe variant of Base64 without `+/=` characters
- ✅ **Token minting:** Creating JWTs with secp256k1 signatures
- ✅ **Token verification:** Checking expiration, issuer, and cryptographic signature
- ✅ **OAuth 2.1 flow:** Authorization code with PKCE for secure client authentication
- ✅ **Refresh tokens:** Long-lived tokens for renewing expired access tokens
- ✅ **Token rotation:** Revoking old refresh tokens for security
- ✅ **Common mistakes:** Algorithm validation, token lifetime, sensitive data

## Key Takeaways

1. **JWTs are self-contained but not encrypted:** Anyone can decode and read the payload. Never put sensitive data in JWTs—they're for authentication, not encryption.

2. **Short access tokens + long refresh tokens balances security and UX:** Compromised access tokens expire quickly. Refresh tokens can be revoked centrally while still providing long sessions.

3. **PKCE prevents authorization code interception:** By binding the code to a cryptographic verifier, only the legitimate client can exchange it for tokens—even if an attacker intercepts the code.

## Looking Ahead

In **Chapter 15**, we'll bring everything together to build a **Complete Personal Data Server**—integrating all the pieces we've built into a fully functional AT Protocol PDS.

You'll learn how to:
- Wire together HTTP server, XRPC, database, and authentication
- Implement complete XRPC handlers for repos and records
- Deploy a production PDS with monitoring
- Test federation with other PDSes

This is the culmination of everything we've learned—a working implementation of the AT Protocol!

---

**Files Referenced in This Chapter:**
- [JWT.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/JWT.h) - JWT data structures
- [JWT.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/JWT.m) - JWT implementation
- [OAuth2Handler.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/OAuth2Handler.h) - OAuth flow handler
- [Secp256k1.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/Secp256k1.h) - Signing (Chapter 8)

**Further Reading:**
- [OAuth 2.1 Specification](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-10) - Latest OAuth standard
- [RFC 7519: JWT](https://datatracker.ietf.org/doc/html/rfc7519) - JSON Web Token specification
- [RFC 7636: PKCE](https://datatracker.ietf.org/doc/html/rfc7636) - Proof Key for Code Exchange
- [AT Protocol Auth Spec](https://atproto.com/specs/oauth) - AT Protocol's OAuth implementation
- [JWT.io](https://jwt.io/) - Online JWT decoder and debugger

---

## Appendix: OAuth Error Codes

### Standard OAuth 2.1 Errors

| Error Code | Meaning | When to Use |
|------------|---------|-------------|
| `invalid_request` | Malformed request | Missing required parameters |
| `invalid_client` | Client authentication failed | Wrong client_id or secret |
| `invalid_grant` | Grant is invalid or expired | Bad authorization code or refresh token |
| `unauthorized_client` | Client not authorized | Client not registered for this grant type |
| `unsupported_grant_type` | Grant type not supported | Unsupported grant_type parameter |
| `invalid_scope` | Requested scope invalid | Unknown or forbidden scope |
| `access_denied` | User denied authorization | User clicked "Deny" on consent screen |
| `server_error` | Internal server error | Unexpected error on server side |

### Example Error Response

```json
{
  "error": "invalid_grant",
  "error_description": "Authorization code expired",
  "error_uri": "https://docs.example.com/oauth/errors#invalid_grant"
}
```

**Best practices:**
- Always include `error` and `error_description`
- Use standard error codes for interoperability
- Log detailed errors server-side, return generic errors to client
- Include `error_uri` for documentation links
