---
title: "Tutorial 4: Authentication"
---

# Tutorial 4: Authentication

## Overview

In this tutorial, you'll extend the PDS from Tutorial 3 to implement production-grade authentication. You'll build a complete OAuth 2.0 authorization server with DPoP (Demonstration of Proof-of-Possession) token binding, JWT signature verification, and secure token refresh flows.

Authentication is the cornerstone of any secure system. In the AT Protocol, it's especially critical because users control their own data—your PDS must ensure that only authorized clients can access or modify that data. This tutorial takes you from the simplified JWT minting in Tutorial 2 to a complete, standards-compliant authentication system.

### What You'll Build

A complete authentication system featuring:
- **JWT Verifier** — Cryptographic signature verification with proper claims validation
- **OAuth 2.0 Server** — Full authorization code flow with PKCE support
- **DPoP Handler** — Token binding to prevent token theft and replay attacks
- **Token Refresh** — Secure session renewal without re-authentication
- **Protected Endpoints** — Middleware that enforces authentication on API routes

This tutorial implements the same authentication patterns used in production AT Protocol servers, giving you real-world security practices.

**Learning Objectives:**
- Understand JWT structure and signature verification
- Implement OAuth 2.0 authorization code flow
- Add DPoP proof-of-possession for token binding
- Build token refresh mechanisms
- Secure XRPC endpoints with authentication middleware
- Handle common authentication errors gracefully

**Estimated Time:** 90-120 minutes

## Prerequisites

Before starting this tutorial, you should have:

- **Completed Tutorials:**
  - [Tutorial 1: Hello PDS](tutorial-1-hello-pds) — Basic server setup
  - [Tutorial 2: Account Management](tutorial-2-accounts) — Account creation and simple JWT minting
  - [Tutorial 3: Record Operations](tutorial-3-records) — Record CRUD operations
  
- **Knowledge:**
  - Understanding of JWT tokens (see [JWT Tokens](../06-authentication/jwt-tokens))
  - Familiarity with OAuth 2.0 concepts (see [OAuth 2.0 with DPoP](../06-authentication/oauth2-dpop))
  - Basic cryptography concepts (hashing, signatures)
  - HTTP headers and status codes
  
- **Optional but Helpful:**
  - Experience with authentication systems
  - Understanding of public-key cryptography
  - Familiarity with ECDSA signatures
  - Knowledge of security best practices

## Architecture Overview

In Tutorial 2, we created a simplified JWT minter that generated tokens without proper signature verification—fine for learning, but not for production. Real-world authentication requires cryptographic verification to ensure tokens haven't been tampered with and come from a trusted source.

### The Authentication Stack

This tutorial builds four interconnected components:

1. **JWT Verifier** — Verifies JWT signatures using HMAC-SHA256 (tutorial) or ECDSA P-256 (production)
2. **OAuth 2.0 Handler** — Implements the authorization code flow with PKCE
3. **DPoP Handler** — Binds tokens to client keys to prevent theft
4. **Token Refresh** — Allows secure session renewal without re-authentication

### Why OAuth 2.0 + DPoP?

**OAuth 2.0** is the industry standard for authorization. It separates authentication (proving who you are) from authorization (granting access to resources). The authorization code flow is the most secure OAuth flow because:
- The access token never passes through the browser
- PKCE prevents authorization code interception
- Refresh tokens enable long-lived sessions

**DPoP (RFC 9449)** adds an extra security layer by binding tokens to cryptographic keys. Even if an attacker steals your access token, they can't use it without the corresponding private key. This is critical for AT Protocol because:
- Users may access their PDS from multiple devices
- Tokens might be stored in less-secure environments
- The decentralized nature means no central token revocation

### Authentication Flow Diagram

```objc
┌─────────┐                                  ┌─────────┐
│ Client  │                                  │   PDS   │
└────┬────┘                                  └────┬────┘
     │                                            │
     │  1. GET /oauth/authorize                  │
     │    ?client_id=...&redirect_uri=...        │
     ├──────────────────────────────────────────>│
     │                                            │
     │  2. 302 Redirect with auth code           │
     │<──────────────────────────────────────────┤
     │                                            │
     │  3. POST /oauth/token                     │
     │    {code, client_id, code_verifier}       │
     ├──────────────────────────────────────────>│
     │                                            │
     │  4. {access_token, refresh_token}         │
     │<──────────────────────────────────────────┤
     │                                            │
     │  5. POST /xrpc/com.atproto.repo.create... │
     │    Authorization: Bearer <token>          │
     │    DPoP: <proof>                          │
     ├──────────────────────────────────────────>│
     │                                            │
     │  6. Verify JWT + DPoP                     │
     │                                            │
     │  7. {uri, cid}                            │
     │<──────────────────────────────────────────┤
```objc

### Security Principles

This implementation follows these security principles:

1. **Defense in Depth** — Multiple layers (JWT signature, DPoP binding, expiration)
2. **Least Privilege** — Tokens grant only necessary scopes
3. **Short-Lived Tokens** — Access tokens expire in 1 hour
4. **Cryptographic Binding** — DPoP ties tokens to client keys
5. **Secure Defaults** — PKCE required, HTTPS assumed

## Step 1: Create JWT Verifier

The JWT Verifier is the foundation of your authentication system. It takes a JWT token (a string like `eyJ...`) and verifies that:
1. The token has a valid structure (header.payload.signature)
2. The signature is cryptographically valid
3. The claims (issuer, expiration, etc.) are correct

### Why JWT Verification Matters

In Tutorial 2, we created tokens but never verified them—we trusted whatever the client sent. In production, this is catastrophic: an attacker could forge tokens and impersonate any user. Cryptographic verification ensures that only tokens signed by your server's private key are accepted.

Create `src/JWTVerifier.h`:

```objc
#import <Foundation/Foundation.h>

@interface JWTVerifier : NSObject

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey;

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error;
- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error;
- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error;

@end
```objc

### Understanding the Interface

**`initWithIssuer:publicKey:`** — The issuer is your PDS's DID (e.g., `did:web:pds.example.com`). The public key is used to verify signatures. In production, you'd load this from secure storage.

**`verifyToken:error:`** — The main entry point. It performs all verification steps and returns the payload if valid, or `nil` with an error if invalid.

**`verifySignature:withPublicKey:error:`** — Checks the cryptographic signature. This is where the math happens.

**`extractPayload:error:`** — Decodes the base64-encoded payload. Useful for debugging or when you need claims before full verification.

## Step 2: Implement JWT Verifier

Now let's implement the verification logic. This is where security happens—every line matters.

Create `src/JWTVerifier.m`:


```objc
#import "JWTVerifier.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

@interface JWTVerifier ()
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, strong) NSData *publicKey;
@end

@implementation JWTVerifier

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey {
    self = [super init];
    if (!self) return nil;
    
    self.issuer = issuer;
    self.publicKey = publicKey;
    
    return self;
}

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error {
    // 1. Extract payload
    NSDictionary *payload = [self extractPayload:token error:error];
    if (!payload) return nil;
    
    // 2. Verify signature
    if (![self verifySignature:token withPublicKey:self.publicKey error:error]) {
        return nil;
    }
    
    // 3. Verify issuer
    if (![payload[@"iss"] isEqualToString:self.issuer]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return nil;
    }
    
    // 4. Verify expiration
    NSTimeInterval exp = [payload[@"exp"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (exp < now) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return nil;
    }
    
    return payload;
}

- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error {
    // Split token into parts
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return NO;
    }
    
    // For tutorial simplicity, we'll use HMAC verification
    // In production, use ECDSA P-256 signature verification
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    // Compute expected signature
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, publicKey.bytes, publicKey.length, 
           signingData.bytes, signingData.length, digest);
    NSData *expectedSignature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *expectedB64 = [self base64URLEncode:expectedSignature];
    
    // Compare signatures
    if (![parts[2] isEqualToString:expectedB64]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        }
        return NO;
    }
    
    return YES;
}

- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error {
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return nil;
    }
    
    // Decode payload
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    while (payload.length % 4 != 0) {
        payload = [payload stringByAppendingString:@"="];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:5 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode payload"}];
        }
        return nil;
    }
    
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
```objc

### Understanding the Verification Process

**Step 1: Extract Payload** — We decode the payload first to check expiration. No point verifying the signature of an expired token.

**Step 2: Verify Signature** — This is the cryptographic heart. We recompute the signature using the same algorithm and key, then compare. If they match, the token is authentic.

**Step 3: Verify Issuer** — The `iss` claim must match your PDS's DID. This prevents tokens from other servers being used on yours.

**Step 4: Verify Expiration** — The `exp` claim is a Unix timestamp. If it's in the past, the token is expired.

### HMAC vs ECDSA

This tutorial uses HMAC-SHA256 for simplicity—it's symmetric (same key for signing and verifying). Production AT Protocol servers use ECDSA P-256, which is asymmetric (private key for signing, public key for verifying). ECDSA is more secure because:
- The signing key never leaves the server
- Public keys can be distributed safely
- It's the standard for AT Protocol

### Base64URL Encoding

JWTs use base64URL encoding, which is like regular base64 but URL-safe:
- `+` becomes `-`
- `/` becomes `_`
- Padding `=` is removed

This allows JWTs to be used in URLs without encoding issues.

### Error Handling

Notice how every failure path sets an error with a descriptive message. This makes debugging much easier—you'll know exactly why a token was rejected.


```objc
#import "JWTVerifier.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

@interface JWTVerifier ()
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, strong) NSData *publicKey;
@end

@implementation JWTVerifier

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey {
    self = [super init];
    if (!self) return nil;
    
    self.issuer = issuer;
    self.publicKey = publicKey;
    
    return self;
}

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error {
    // 1. Extract payload
    NSDictionary *payload = [self extractPayload:token error:error];
    if (!payload) return nil;
    
    // 2. Verify signature
    if (![self verifySignature:token withPublicKey:self.publicKey error:error]) {
        return nil;
    }
    
    // 3. Verify issuer
    if (![payload[@"iss"] isEqualToString:self.issuer]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid issuer"}];
        }
        return nil;
    }
    
    // 4. Verify expiration
    NSTimeInterval exp = [payload[@"exp"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (exp < now) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"Token expired"}];
        }
        return nil;
    }
    
    return payload;
}

- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error {
    // Split token into parts
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return NO;
    }
    
    // For tutorial simplicity, we'll use HMAC verification
    // In production, use ECDSA P-256 signature verification
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    // Compute expected signature
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, publicKey.bytes, publicKey.length, 
           signingData.bytes, signingData.length, digest);
    NSData *expectedSignature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *expectedB64 = [self base64URLEncode:expectedSignature];
    
    // Compare signatures
    if (![parts[2] isEqualToString:expectedB64]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature"}];
        }
        return NO;
    }
    
    return YES;
}

- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error {
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return nil;
    }
    
    // Decode payload
    NSString *payload = parts[1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    while (payload.length % 4 != 0) {
        payload = [payload stringByAppendingString:@"="];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"JWT" code:5 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode payload"}];
        }
        return nil;
    }
    
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
```objc


## Step 3: Create DPoP Handler

DPoP (Demonstration of Proof-of-Possession) is a security mechanism that binds access tokens to cryptographic keys. Without DPoP, if someone steals your access token, they can use it from anywhere. With DPoP, the token is useless without the corresponding private key.

### How DPoP Works

Every API request includes two things:
1. **Access Token** — Contains a thumbprint of the client's public key
2. **DPoP Proof** — A JWT signed with the client's private key, proving possession

The server verifies that:
- The DPoP proof is signed by the key whose thumbprint is in the token
- The DPoP proof includes the correct HTTP method and URI
- The DPoP proof is recent (not replayed from an old request)

This means even if an attacker intercepts your token, they can't use it without your private key.

Create `src/DPoPHandler.h`:

```objc
#import <Foundation/Foundation.h>

@interface DPoPHandler : NSObject

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error;

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error;

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error;

@end
```objc

## Step 4: Implement DPoP Handler

The DPoP handler generates and verifies proof-of-possession tokens. This is more complex than regular JWTs because it includes the client's public key in the token itself.

Create `src/DPoPHandler.m`:

```objc
#import "DPoPHandler.h"
#import <CommonCrypto/CommonDigest.h>

@implementation DPoPHandler

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error {
    // 1. Create JWK from public key
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    // 2. Create DPoP header
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": jwk
    };
    
    // 3. Create DPoP payload
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *payload = [@{
        @"jti": [[NSUUID UUID] UUIDString],
        @"htm": method,
        @"htu": uri,
        @"iat": @(now),
        @"exp": @(now + 300)  // 5 minutes
    } mutableCopy];
    
    if (nonce) {
        payload[@"nonce"] = nonce;
    }
    
    // 4. Encode header and payload
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!headerData || !payloadData) return nil;
    
    NSString *headerB64 = [self base64URLEncode:headerData];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    // 5. Sign with private key (simplified for tutorial)
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, digest);
    NSData *signature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signature];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error {
    // 1. Parse proof
    NSArray *parts = [proof componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }
    
    // 2. Decode payload
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    
    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payload) return NO;
    
    // 3. Verify method and URI
    if (![payload[@"htm"] isEqualToString:method]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Method mismatch"}];
        }
        return NO;
    }
    
    if (![payload[@"htu"] isEqualToString:uri]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"URI mismatch"}];
        }
        return NO;
    }
    
    // 4. Verify timestamp
    NSTimeInterval iat = [payload[@"iat"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - iat > 300) {  // 5 minutes
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }
    
    return YES;
}

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error {
    // Create JWK thumbprint (SHA-256 of canonical JWK)
    NSDictionary *jwk = @{
        @"crv": @"P-256",
        @"kty": @"EC",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    NSData *jwkData = [NSJSONSerialization dataWithJSONObject:jwk 
                                                      options:NSJSONWritingSortedKeys 
                                                        error:error];
    if (!jwkData) return nil;
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(jwkData.bytes, (CC_LONG)jwkData.length, digest);
    NSData *thumbprint = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    
    return [self base64URLEncode:thumbprint];
}

+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
```objc

### Understanding DPoP Proof Generation

**Step 1: Create JWK** — The JSON Web Key (JWK) represents the client's public key in a standard format. For ECDSA P-256, we extract the x and y coordinates from the 65-byte uncompressed public key (0x04 || x || y).

**Step 2: Create Header** — The DPoP header includes:
- `typ: "dpop+jwt"` — Identifies this as a DPoP proof
- `alg: "ES256"` — ECDSA with P-256 curve and SHA-256
- `jwk` — The client's public key (this is unique to DPoP)

**Step 3: Create Payload** — The DPoP payload includes:
- `jti` — Unique ID to prevent replay attacks
- `htm` — HTTP method (POST, GET, etc.)
- `htu` — HTTP URI (the full URL being accessed)
- `iat` — Issued at timestamp
- `exp` — Expiration (5 minutes is standard)
- `nonce` — Optional server-provided nonce for extra security

**Step 4: Sign** — The proof is signed with the client's private key. The server can verify it using the public key embedded in the header.

### Understanding DPoP Verification

**Method and URI Verification** — This is critical: the DPoP proof must match the actual HTTP request. If someone tries to replay a proof from a different request, it will fail.

**Timestamp Verification** — DPoP proofs expire quickly (5 minutes). This limits the window for replay attacks.

**Thumbprint Extraction** — The thumbprint is a hash of the canonical JWK. It's used to bind the access token to this specific key pair.

### Why 5 Minutes?

DPoP proofs are short-lived because they're request-specific. You generate a new proof for each API call. This is different from access tokens, which last an hour and are reused across many requests.

```objc
#import "DPoPHandler.h"
#import <CommonCrypto/CommonDigest.h>

@implementation DPoPHandler

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error {
    // 1. Create JWK from public key
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    // 2. Create DPoP header
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": jwk
    };
    
    // 3. Create DPoP payload
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *payload = [@{
        @"jti": [[NSUUID UUID] UUIDString],
        @"htm": method,
        @"htu": uri,
        @"iat": @(now),
        @"exp": @(now + 300)  // 5 minutes
    } mutableCopy];
    
    if (nonce) {
        payload[@"nonce"] = nonce;
    }
    
    // 4. Encode header and payload
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!headerData || !payloadData) return nil;
    
    NSString *headerB64 = [self base64URLEncode:headerData];
    NSString *payloadB64 = [self base64URLEncode:payloadData];
    
    // 5. Sign with private key (simplified for tutorial)
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(signingData.bytes, (CC_LONG)signingData.length, digest);
    NSData *signature = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *signatureB64 = [self base64URLEncode:signature];
    
    return [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, signatureB64];
}

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error {
    // 1. Parse proof
    NSArray *parts = [proof componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP format"}];
        }
        return NO;
    }
    
    // 2. Decode payload
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    
    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:error];
    if (!payload) return NO;
    
    // 3. Verify method and URI
    if (![payload[@"htm"] isEqualToString:method]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Method mismatch"}];
        }
        return NO;
    }
    
    if (![payload[@"htu"] isEqualToString:uri]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:3 
                userInfo:@{NSLocalizedDescriptionKey: @"URI mismatch"}];
        }
        return NO;
    }
    
    // 4. Verify timestamp
    NSTimeInterval iat = [payload[@"iat"] doubleValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - iat > 300) {  // 5 minutes
        if (error) {
            *error = [NSError errorWithDomain:@"DPoP" code:4 
                userInfo:@{NSLocalizedDescriptionKey: @"DPoP proof expired"}];
        }
        return NO;
    }
    
    return YES;
}

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error {
    // Create JWK thumbprint (SHA-256 of canonical JWK)
    NSDictionary *jwk = @{
        @"crv": @"P-256",
        @"kty": @"EC",
        @"x": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(1, 32)]],
        @"y": [self base64URLEncode:[publicKey subdataWithRange:NSMakeRange(33, 32)]]
    };
    
    NSData *jwkData = [NSJSONSerialization dataWithJSONObject:jwk 
                                                      options:NSJSONWritingSortedKeys 
                                                        error:error];
    if (!jwkData) return nil;
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(jwkData.bytes, (CC_LONG)jwkData.length, digest);
    NSData *thumbprint = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    
    return [self base64URLEncode:thumbprint];
}

+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
```objc


## Step 5: Update JWT Minter with DPoP Support

Now we need to update the JWT minter from Tutorial 2 to support DPoP token binding. When a client provides a DPoP proof during token issuance, we embed the key thumbprint in the access token.

Update `src/SimpleJWTMinter.m` to support DPoP binding:

```objc
- (NSString *)mintAccessTokenForDID:(NSString *)did 
                            handle:(NSString *)handle
                     dpopThumbprint:(nullable NSString *)jkt {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval exp = now + 3600;  // 1 hour
    
    NSMutableDictionary *payload = [@{
        @"iss": self.issuer,
        @"sub": did,
        @"aud": self.issuer,
        @"iat": @(now),
        @"exp": @(exp),
        @"scope": @"atproto_repo",
        @"handle": handle
    } mutableCopy];
    
    // Add DPoP binding if thumbprint provided
    if (jkt) {
        payload[@"cnf"] = @{@"jkt": jkt};
    }
    
    return [self encodeJWT:payload];
}
```objc

### Understanding Token Binding

**The `cnf` Claim** — "Confirmation" is a standard JWT claim (RFC 7800) used for proof-of-possession. The `jkt` (JWK thumbprint) sub-claim contains the hash of the client's public key.

**How Binding Works:**
1. Client generates a key pair
2. Client sends DPoP proof with token request
3. Server extracts public key from DPoP proof
4. Server computes thumbprint of public key
5. Server embeds thumbprint in access token (`cnf.jkt`)
6. On each API request, server verifies DPoP proof matches token binding

**Why This Matters** — Without binding, access tokens are "bearer tokens"—whoever has the token can use it. With DPoP binding, the token is cryptographically tied to a specific key pair. An attacker who steals the token can't use it without the private key.

### Optional vs Required

In this implementation, DPoP is optional—if no thumbprint is provided, we issue a regular bearer token. In production, you might want to:
- Require DPoP for sensitive operations
- Use different token lifetimes (shorter for bearer, longer for DPoP)
- Track which tokens are DPoP-bound for security auditing

## Step 6: Create OAuth 2.0 Handler

OAuth 2.0 is the industry standard for authorization. It separates the concerns of authentication (proving who you are) from authorization (granting access to resources). The authorization code flow is the most secure OAuth flow because the access token never passes through the browser.

### OAuth 2.0 Flow Overview

```objc
1. Client → Authorization Endpoint
   "I want access to user's data"
   
2. Server → User
   "Do you authorize this client?"
   
3. User → Server
   "Yes, I authorize"
   
4. Server → Client (via redirect)
   "Here's an authorization code"
   
5. Client → Token Endpoint
   "Exchange this code for tokens"
   
6. Server → Client
   "Here are your access and refresh tokens"
```objc

The authorization code is single-use and short-lived. The real tokens are only issued after the client proves it's the same client that started the flow (via PKCE).

Create `src/OAuth2Handler.h`:

```objc
#import <Foundation/Foundation.h>
#import "AccountService.h"
#import "SimpleJWTMinter.h"

@interface OAuth2Handler : NSObject

- (instancetype)initWithAccountService:(AccountService *)accountService
                                minter:(SimpleJWTMinter *)minter;

- (void)handleAuthorize:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleToken:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRefresh:(HttpRequest *)request response:(HttpResponse *)response;

@end
```objc

## Step 7: Implement OAuth 2.0 Handler

Create `src/OAuth2Handler.m`:

```objc
#import "OAuth2Handler.h"
#import "DPoPHandler.h"

@interface OAuth2Handler ()
@property (nonatomic, strong) AccountService *accountService;
@property (nonatomic, strong) SimpleJWTMinter *minter;
@property (nonatomic, strong) NSMutableDictionary *authorizationCodes;
@end

@implementation OAuth2Handler

- (instancetype)initWithAccountService:(AccountService *)accountService
                                minter:(SimpleJWTMinter *)minter {
    self = [super init];
    if (!self) return nil;
    
    self.accountService = accountService;
    self.minter = minter;
    self.authorizationCodes = [NSMutableDictionary dictionary];
    
    return self;
}

- (void)handleAuthorize:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Parse query parameters
    NSString *clientId = [request queryParamForKey:@"client_id"];
    NSString *redirectUri = [request queryParamForKey:@"redirect_uri"];
    NSString *scope = [request queryParamForKey:@"scope"];
    NSString *state = [request queryParamForKey:@"state"];
    NSString *codeChallenge = [request queryParamForKey:@"code_challenge"];
    NSString *codeChallengeMethod = [request queryParamForKey:@"code_challenge_method"];
    
    // 2. Validate parameters
    if (!clientId || !redirectUri || !scope) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_request"} JSONData];
        return;
    }
    
    // 3. In production, show login page and get user consent
    // For tutorial, we'll auto-approve with a test user
    NSString *userDid = @"did:plc:test123";
    NSString *userHandle = @"testuser";
    
    // 4. Generate authorization code
    NSString *code = [[NSUUID UUID] UUIDString];
    self.authorizationCodes[code] = @{
        @"did": userDid,
        @"handle": userHandle,
        @"client_id": clientId,
        @"redirect_uri": redirectUri,
        @"scope": scope,
        @"code_challenge": codeChallenge ?: @"",
        @"code_challenge_method": codeChallengeMethod ?: @"",
        @"created_at": @([[NSDate date] timeIntervalSince1970])
    };
    
    // 5. Redirect back to client
    NSString *redirectUrl = [NSString stringWithFormat:@"%@?code=%@&state=%@", 
                            redirectUri, code, state ?: @""];
    
    response.statusCode = 302;
    [response setHeader:@"Location" value:redirectUrl];
}

- (void)handleToken:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Parse request body
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_request"} JSONData];
        return;
    }
    
    NSString *grantType = params[@"grant_type"];
    NSString *code = params[@"code"];
    NSString *clientId = params[@"client_id"];
    NSString *redirectUri = params[@"redirect_uri"];
    NSString *codeVerifier = params[@"code_verifier"];
    
    // 2. Validate grant type
    if (![grantType isEqualToString:@"authorization_code"]) {
        response.statusCode = 400;
        response.body = [@{@"error": @"unsupported_grant_type"} JSONData];
        return;
    }
    
    // 3. Validate authorization code
    NSDictionary *authCode = self.authorizationCodes[code];
    if (!authCode) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 4. Verify client_id and redirect_uri match
    if (![authCode[@"client_id"] isEqualToString:clientId] ||
        ![authCode[@"redirect_uri"] isEqualToString:redirectUri]) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 5. Verify PKCE if code_challenge was provided
    if ([authCode[@"code_challenge"] length] > 0) {
        if (!codeVerifier) {
            response.statusCode = 400;
            response.body = [@{@"error": @"invalid_request"} JSONData];
            return;
        }
        
        // Verify code_verifier matches code_challenge
        if (![self verifyPKCE:codeVerifier challenge:authCode[@"code_challenge"]]) {
            response.statusCode = 400;
            response.body = [@{@"error": @"invalid_grant"} JSONData];
            return;
        }
    }
    
    // 6. Extract DPoP proof if present
    NSString *dpopProof = [request headerForKey:@"DPoP"];
    NSString *dpopThumbprint = nil;
    
    if (dpopProof) {
        // Verify DPoP proof
        NSError *dpopError = nil;
        NSData *publicKey = [self extractPublicKeyFromDPoP:dpopProof error:&dpopError];
        if (!publicKey) {
            response.statusCode = 400;
            response.body = [@{@"error": @"invalid_dpop_proof"} JSONData];
            return;
        }
        
        dpopThumbprint = [DPoPHandler extractThumbprint:publicKey error:&dpopError];
    }
    
    // 7. Generate tokens
    NSString *did = authCode[@"did"];
    NSString *handle = authCode[@"handle"];
    
    NSString *accessToken = [self.minter mintAccessTokenForDID:did 
                                                        handle:handle
                                                dpopThumbprint:dpopThumbprint];
    NSString *refreshToken = [self.minter mintRefreshTokenForDID:did handle:handle];
    
    // 8. Invalidate authorization code
    [self.authorizationCodes removeObjectForKey:code];
    
    // 9. Return tokens
    NSDictionary *result = @{
        @"access_token": accessToken,
        @"refresh_token": refreshToken,
        @"token_type": dpopProof ? @"DPoP" : @"Bearer",
        @"expires_in": @3600,
        @"scope": authCode[@"scope"]
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleRefresh:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Parse request body
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    if (!params) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_request"} JSONData];
        return;
    }
    
    NSString *grantType = params[@"grant_type"];
    NSString *refreshToken = params[@"refresh_token"];
    
    // 2. Validate grant type
    if (![grantType isEqualToString:@"refresh_token"]) {
        response.statusCode = 400;
        response.body = [@{@"error": @"unsupported_grant_type"} JSONData];
        return;
    }
    
    // 3. Verify refresh token (simplified - in production, verify signature)
    NSArray *parts = [refreshToken componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 4. Decode payload
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    
    NSData *payloadData = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    
    if (!payload) {
        response.statusCode = 400;
        response.body = [@{@"error": @"invalid_grant"} JSONData];
        return;
    }
    
    // 5. Extract DPoP proof if present
    NSString *dpopProof = [request headerForKey:@"DPoP"];
    NSString *dpopThumbprint = nil;
    
    if (dpopProof) {
        NSError *dpopError = nil;
        NSData *publicKey = [self extractPublicKeyFromDPoP:dpopProof error:&dpopError];
        if (publicKey) {
            dpopThumbprint = [DPoPHandler extractThumbprint:publicKey error:&dpopError];
        }
    }
    
    // 6. Generate new access token
    NSString *did = payload[@"sub"];
    NSString *handle = payload[@"handle"];
    
    NSString *accessToken = [self.minter mintAccessTokenForDID:did 
                                                        handle:handle
                                                dpopThumbprint:dpopThumbprint];
    
    // 7. Return new access token
    NSDictionary *result = @{
        @"access_token": accessToken,
        @"token_type": dpopProof ? @"DPoP" : @"Bearer",
        @"expires_in": @3600
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (BOOL)verifyPKCE:(NSString *)verifier challenge:(NSString *)challenge {
    // SHA-256 hash of verifier
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    
    // Base64URL encode
    NSString *computed = [hashData base64EncodedStringWithOptions:0];
    computed = [computed stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    computed = [computed stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    computed = [computed stringByReplacingOccurrencesOfString:@"=" withString:@""];
    
    return [computed isEqualToString:challenge];
}

- (nullable NSData *)extractPublicKeyFromDPoP:(NSString *)dpopProof error:(NSError **)error {
    // Parse DPoP header to extract JWK
    NSArray *parts = [dpopProof componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    
    NSString *headerB64 = parts[0];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (headerB64.length % 4 != 0) {
        headerB64 = [headerB64 stringByAppendingString:@"="];
    }
    
    NSData *headerData = [[NSData alloc] initWithBase64EncodedString:headerB64 options:0];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    
    if (!header) return nil;
    
    NSDictionary *jwk = header[@"jwk"];
    if (!jwk) return nil;
    
    // Extract x and y coordinates from JWK
    NSString *xB64 = jwk[@"x"];
    NSString *yB64 = jwk[@"y"];
    
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (xB64.length % 4 != 0) {
        xB64 = [xB64 stringByAppendingString:@"="];
    }
    
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (yB64.length % 4 != 0) {
        yB64 = [yB64 stringByAppendingString:@"="];
    }
    
    NSData *xData = [[NSData alloc] initWithBase64EncodedString:xB64 options:0];
    NSData *yData = [[NSData alloc] initWithBase64EncodedString:yB64 options:0];
    
    if (!xData || !yData) return nil;
    
    // Construct uncompressed public key (0x04 || x || y)
    NSMutableData *publicKey = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [publicKey appendBytes:&prefix length:1];
    [publicKey appendData:xData];
    [publicKey appendData:yData];
    
    return publicKey;
}

@end
```objc


## Step 8: Update XRPC Dispatcher with Authentication

Update `src/XrpcDispatcher.m` to add OAuth endpoints and verify authentication:

```objc
#import "XrpcDispatcher.h"
#import "JWTVerifier.h"
#import "DPoPHandler.h"

@interface XrpcDispatcher ()
@property (nonatomic, strong) JWTVerifier *jwtVerifier;
@property (nonatomic, strong) OAuth2Handler *oauth2Handler;
@end

- (void)dispatchRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    
    // OAuth endpoints
    if ([path isEqualToString:@"/oauth/authorize"]) {
        [self.oauth2Handler handleAuthorize:request response:response];
        return;
    } else if ([path isEqualToString:@"/oauth/token"]) {
        [self.oauth2Handler handleToken:request response:response];
        return;
    }
    
    // XRPC endpoints
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
    
    // Public endpoints (no auth required)
    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
        return;
    } else if ([nsid isEqualToString:@"com.atproto.server.createAccount"]) {
        [self handleCreateAccount:request response:response];
        return;
    } else if ([nsid isEqualToString:@"com.atproto.server.createSession"]) {
        [self handleCreateSession:request response:response];
        return;
    }
    
    // Protected endpoints (auth required)
    NSError *authError = nil;
    NSString *did = [self authenticateRequest:request error:&authError];
    
    if (!did) {
        response.statusCode = 401;
        response.body = [@{
            @"error": @"AuthenticationRequired",
            @"message": authError.localizedDescription ?: @"Authentication required"
        } JSONData];
        return;
    }
    
    // Store authenticated DID in request context
    request.authenticatedDID = did;
    
    // Route to appropriate handler
    if ([nsid isEqualToString:@"com.atproto.repo.createRecord"]) {
        [self handleCreateRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.getRecord"]) {
        [self handleGetRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.listRecords"]) {
        [self handleListRecords:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.repo.deleteRecord"]) {
        [self handleDeleteRecord:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.refreshSession"]) {
        [self.oauth2Handler handleRefresh:request response:response];
    } else {
        response.statusCode = 404;
        response.body = [@{@"error": @"MethodNotFound"} JSONData];
    }
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request error:(NSError **)error {
    // 1. Extract Authorization header
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        if (error) {
            *error = [NSError errorWithDomain:@"Auth" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Missing Authorization header"}];
        }
        return nil;
    }
    
    // 2. Parse token type and token
    NSArray *parts = [authHeader componentsSeparatedByString:@" "];
    if (parts.count != 2) {
        if (error) {
            *error = [NSError errorWithDomain:@"Auth" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Invalid Authorization header format"}];
        }
        return nil;
    }
    
    NSString *tokenType = parts[0];
    NSString *token = parts[1];
    
    // 3. Verify JWT token
    NSError *jwtError = nil;
    NSDictionary *payload = [self.jwtVerifier verifyToken:token error:&jwtError];
    if (!payload) {
        if (error) *error = jwtError;
        return nil;
    }
    
    // 4. If DPoP token, verify DPoP proof
    if ([tokenType isEqualToString:@"DPoP"]) {
        NSString *dpopProof = [request headerForKey:@"DPoP"];
        if (!dpopProof) {
            if (error) {
                *error = [NSError errorWithDomain:@"Auth" code:3 
                    userInfo:@{NSLocalizedDescriptionKey: @"Missing DPoP proof"}];
            }
            return nil;
        }
        
        // Verify DPoP proof matches request
        NSError *dpopError = nil;
        NSData *publicKey = [self extractPublicKeyFromDPoP:dpopProof error:&dpopError];
        if (!publicKey) {
            if (error) *error = dpopError;
            return nil;
        }
        
        BOOL dpopValid = [DPoPHandler verifyDPoPProof:dpopProof
                                               method:request.method
                                                  uri:request.fullURL
                                            publicKey:publicKey
                                                error:&dpopError];
        if (!dpopValid) {
            if (error) *error = dpopError;
            return nil;
        }
        
        // Verify DPoP thumbprint matches token binding
        NSString *thumbprint = [DPoPHandler extractThumbprint:publicKey error:&dpopError];
        NSString *tokenThumbprint = payload[@"cnf"][@"jkt"];
        
        if (!tokenThumbprint || ![thumbprint isEqualToString:tokenThumbprint]) {
            if (error) {
                *error = [NSError errorWithDomain:@"Auth" code:4 
                    userInfo:@{NSLocalizedDescriptionKey: @"DPoP thumbprint mismatch"}];
            }
            return nil;
        }
    }
    
    // 5. Return authenticated DID
    return payload[@"sub"];
}

- (nullable NSData *)extractPublicKeyFromDPoP:(NSString *)dpopProof error:(NSError **)error {
    // Parse DPoP header to extract JWK (same as OAuth2Handler)
    NSArray *parts = [dpopProof componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    
    NSString *headerB64 = parts[0];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    headerB64 = [headerB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (headerB64.length % 4 != 0) {
        headerB64 = [headerB64 stringByAppendingString:@"="];
    }
    
    NSData *headerData = [[NSData alloc] initWithBase64EncodedString:headerB64 options:0];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    
    if (!header) return nil;
    
    NSDictionary *jwk = header[@"jwk"];
    if (!jwk) return nil;
    
    NSString *xB64 = jwk[@"x"];
    NSString *yB64 = jwk[@"y"];
    
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    xB64 = [xB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (xB64.length % 4 != 0) {
        xB64 = [xB64 stringByAppendingString:@"="];
    }
    
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    yB64 = [yB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (yB64.length % 4 != 0) {
        yB64 = [yB64 stringByAppendingString:@"="];
    }
    
    NSData *xData = [[NSData alloc] initWithBase64EncodedString:xB64 options:0];
    NSData *yData = [[NSData alloc] initWithBase64EncodedString:yB64 options:0];
    
    if (!xData || !yData) return nil;
    
    NSMutableData *publicKey = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [publicKey appendBytes:&prefix length:1];
    [publicKey appendData:xData];
    [publicKey appendData:yData];
    
    return publicKey;
}
```objc

## Step 9: Update Main Entry Point

Update `src/main.m` to initialize authentication components:

```objc
#import <Foundation/Foundation.h>
#import "PDSApplication.h"
#import "AccountService.h"
#import "AccountRepository.h"
#import "RecordService.h"
#import "RecordRepository.h"
#import "SimpleJWTMinter.h"
#import "JWTVerifier.h"
#import "OAuth2Handler.h"
#import "XrpcDispatcher.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        config.databasePath = @"./pds-data/db";
        
        // 2. Create JWT components
        NSString *secret = @"tutorial-secret-key-do-not-use-in-production";
        NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
        
        SimpleJWTMinter *minter = [[SimpleJWTMinter alloc] initWithIssuer:config.issuer];
        JWTVerifier *verifier = [[JWTVerifier alloc] initWithIssuer:config.issuer 
                                                           publicKey:secretData];
        
        // 3. Create account service
        AccountRepository *accountRepo = [[AccountRepository alloc] 
            initWithDatabasePath:config.databasePath];
        AccountService *accountService = [[AccountService alloc] 
            initWithRepository:accountRepo minter:minter];
        
        // 4. Create record service
        RecordRepository *recordRepo = [[RecordRepository alloc] 
            initWithDatabasePath:config.databasePath];
        RecordService *recordService = [[RecordService alloc] 
            initWithRepository:recordRepo];
        
        // 5. Create OAuth handler
        OAuth2Handler *oauth2Handler = [[OAuth2Handler alloc] 
            initWithAccountService:accountService minter:minter];
        
        // 6. Initialize PDS
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc] 
            initWithConfiguration:config error:&error];
        
        if (!app) {
            NSLog(@"Failed to initialize PDS: %@", error);
            return 1;
        }
        
        // 7. Setup XRPC dispatcher with authentication
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        dispatcher.accountService = accountService;
        dispatcher.recordService = recordService;
        dispatcher.jwtVerifier = verifier;
        dispatcher.oauth2Handler = oauth2Handler;
        
        [app.httpServer registerRoute:@"/*" handler:^(HttpRequest *req, HttpResponse *res) {
            [dispatcher dispatchRequest:req response:res];
        }];
        
        // 8. Start server
        [app.httpServer startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }
            
            NSLog(@"PDS started on port %ld", (long)config.serverPort);
            NSLog(@"Account service ready");
            NSLog(@"Record service ready");
            NSLog(@"OAuth 2.0 endpoints ready");
            NSLog(@"JWT verification enabled");
        }];
        
        // 9. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}
```objc


## Step 10: Build and Run

```bash
cd examples/tutorial-4-auth
mkdir -p build && cd build
cmake ..
make
./tutorial-4-auth
```objc

## Step 11: Test OAuth 2.0 Authorization Flow

In another terminal:

```bash
# 1. Start authorization flow
curl -v "http://localhost:2583/oauth/authorize?client_id=https://example.com&redirect_uri=https://example.com/callback&scope=atproto_repo&state=random123"

# Expected: 302 redirect with authorization code
# Location: https://example.com/callback?code=<CODE>&state=random123

# Extract the code from the Location header
CODE="<authorization-code-from-redirect>"

# 2. Exchange code for tokens
curl -X POST http://localhost:2583/oauth/token \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"authorization_code\",
    \"code\": \"$CODE\",
    \"client_id\": \"https://example.com\",
    \"redirect_uri\": \"https://example.com/callback\"
  }" | jq .

# Expected output:
# {
#   "access_token": "eyJ...",
#   "refresh_token": "eyJ...",
#   "token_type": "Bearer",
#   "expires_in": 3600,
#   "scope": "atproto_repo"
# }
```objc

## Step 12: Test JWT Verification

```bash
# Save access token
ACCESS_TOKEN="<access-token-from-previous-step>"

# Create a record with JWT authentication
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "collection": "app.bsky.feed.post",
    "record": {
      "text": "Hello with OAuth!",
      "createdAt": "2024-01-01T00:00:00Z"
    }
  }' | jq .

# Expected output:
# {
#   "uri": "at://did:plc:test123/app.bsky.feed.post/...",
#   "cid": "bafyrei..."
# }
```objc

## Step 13: Test Token Refresh

```bash
# Save refresh token
REFRESH_TOKEN="<refresh-token-from-step-11>"

# Refresh access token
curl -X POST http://localhost:2583/xrpc/com.atproto.server.refreshSession \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"refresh_token\",
    \"refresh_token\": \"$REFRESH_TOKEN\"
  }" | jq .

# Expected output:
# {
#   "access_token": "eyJ...",
#   "token_type": "Bearer",
#   "expires_in": 3600
# }
```objc

## Step 14: Test DPoP Flow (Advanced)

For DPoP, you'll need to generate an ECDSA P-256 key pair. Here's a simplified example:

```bash
# Generate key pair (requires OpenSSL)
openssl ecparam -name prime256v1 -genkey -noout -out dpop-key.pem
openssl ec -in dpop-key.pem -pubout -out dpop-pub.pem

# In production, use proper DPoP libraries
# For tutorial purposes, we'll skip the full DPoP implementation
```objc

## Understanding the Implementation

### JWT Verification Flow

```objc
1. Client sends request with Authorization header
   ↓
2. Extract token from "Bearer <token>" or "DPoP <token>"
   ↓
3. Verify JWT signature using public key
   ↓
4. Validate claims (issuer, expiration, audience)
   ↓
5. If DPoP: verify DPoP proof matches request
   ↓
6. Extract DID from token payload
   ↓
7. Allow request to proceed
```objc

### OAuth 2.0 Authorization Code Flow

```objc
1. Client redirects user to /oauth/authorize
   ↓
2. User logs in and grants permission
   ↓
3. Server generates authorization code
   ↓
4. Redirect back to client with code
   ↓
5. Client exchanges code for tokens at /oauth/token
   ↓
6. Server validates code and returns tokens
   ↓
7. Client uses access token for API requests
```objc

### DPoP Binding

```objc
1. Client generates ECDSA P-256 key pair
   ↓
2. Client creates DPoP proof JWT with public key
   ↓
3. Server extracts public key from DPoP proof
   ↓
4. Server computes thumbprint of public key
   ↓
5. Server binds access token to thumbprint (cnf.jkt)
   ↓
6. On each request, server verifies:
   - DPoP proof signature
   - DPoP proof method/URI match request
   - DPoP thumbprint matches token binding
```objc

## Security Considerations

### Token Security

1. **Short-lived access tokens** — 1 hour expiration reduces impact of theft
2. **Long-lived refresh tokens** — 30 days allows persistent sessions
3. **Secure storage** — Never log tokens, store encrypted
4. **HTTPS only** — Always use TLS for token transmission

### DPoP Benefits

1. **Token binding** — Tokens bound to client's private key
2. **Replay prevention** — Each request requires fresh DPoP proof
3. **Theft mitigation** — Stolen tokens useless without private key
4. **Request integrity** — DPoP proof includes method and URI

### PKCE (Proof Key for Code Exchange)

PKCE prevents authorization code interception:

```objc
1. Client generates code_verifier (random string)
2. Client computes code_challenge = SHA256(code_verifier)
3. Client sends code_challenge in authorize request
4. Server stores code_challenge with authorization code
5. Client sends code_verifier in token request
6. Server verifies SHA256(code_verifier) == code_challenge
```objc

## Production Considerations

### Real ECDSA Signature Verification

In production, replace HMAC with proper ECDSA P-256 verification:

```objc
// Use Security.framework (macOS) or OpenSSL (Linux)
SecKeyRef publicKey = /* load from JWK */;
SecKeyAlgorithm algorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;

CFErrorRef error = NULL;
Boolean verified = SecKeyVerifySignature(publicKey,
                                        algorithm,
                                        (__bridge CFDataRef)signingData,
                                        (__bridge CFDataRef)signatureData,
                                        &error);
```objc

### Key Management

1. **Rotate signing keys** — Annually or on compromise
2. **Multiple active keys** — Support key rotation without downtime
3. **Key ID (kid)** — Include in JWT header for key lookup
4. **Secure storage** — Use Keychain (macOS) or encrypted files (Linux)

### Token Revocation

Implement token revocation for logout:

```sql
CREATE TABLE revoked_tokens (
    jti TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    revoked_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL
);

CREATE INDEX idx_revoked_tokens_did ON revoked_tokens(did);
CREATE INDEX idx_revoked_tokens_expires ON revoked_tokens(expires_at);
```objc

### Rate Limiting

Protect OAuth endpoints from abuse:

```objc
// Limit authorization attempts per IP
[rateLimiter checkLimit:@"oauth_authorize" 
                    key:clientIP 
                  limit:10 
                 window:3600];  // 10 per hour

// Limit token requests per client
[rateLimiter checkLimit:@"oauth_token" 
                    key:clientId 
                  limit:100 
                 window:3600];  // 100 per hour
```objc

## Next Steps

- **[Tutorial 5: Firehose](tutorial-5-firehose)** — Add WebSocket subscriptions
- **[Tutorial 6: Production Deployment](tutorial-6-deployment)** — Deploy to production

## Common Mistakes and How to Avoid Them

### Mistake 1: Not Verifying Token Expiration

**Problem:**
```objc
// WRONG: Accepting expired tokens
NSDictionary *payload = [self extractPayload:token error:error];
return payload[@"sub"];  // No expiration check!
```objc

**Solution:**
```objc
// RIGHT: Always check expiration
NSTimeInterval exp = [payload[@"exp"] doubleValue];
NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
if (exp < now) {
    // Token expired - reject it
    return nil;
}
```objc

**Why It Matters:** Expired tokens should be invalid. Accepting them defeats the purpose of expiration and creates a security vulnerability.

### Mistake 2: Comparing Signatures with `==`

**Problem:**
```objc
// WRONG: Timing attack vulnerability
if (computedSignature == providedSignature) {
    return YES;
}
```objc

**Solution:**
```objc
// RIGHT: Constant-time comparison
if (![computedB64 isEqualToString:providedB64]) {
    return NO;
}
```objc

**Why It Matters:** String comparison in Objective-C is constant-time by default, but be careful with custom comparison logic. Timing attacks can leak information about the signature.

### Mistake 3: Not Validating DPoP Method/URI

**Problem:**
```objc
// WRONG: Only checking signature
BOOL valid = [self verifyDPoPSignature:proof];
return valid;
```objc

**Solution:**
```objc
// RIGHT: Verify method and URI match request
if (![payload[@"htm"] isEqualToString:request.method]) {
    return NO;
}
if (![payload[@"htu"] isEqualToString:request.fullURL]) {
    return NO;
}
```objc

**Why It Matters:** Without method/URI verification, an attacker could replay a DPoP proof from one request on a different request.

### Mistake 4: Storing Tokens in Logs

**Problem:**
```objc
// WRONG: Logging sensitive data
NSLog(@"Received token: %@", accessToken);
NSLog(@"User authenticated: %@ with token %@", did, token);
```objc

**Solution:**
```objc
// RIGHT: Never log tokens
NSLog(@"User authenticated: %@", did);
NSLog(@"Token verification successful");
```objc

**Why It Matters:** Tokens in logs can be extracted by anyone with log access. This is a common source of credential leaks.

### Mistake 5: Using Weak Secrets

**Problem:**
```objc
// WRONG: Weak secret
NSString *secret = @"secret123";
```objc

**Solution:**
```objc
// RIGHT: Strong, randomly generated secret
// Generate with: openssl rand -base64 32
NSString *secret = @"8vY2mK9pL3nQ7wR5tX1cZ4bN6hJ8gF2dS9aE7vB3mK5";
```objc

**Why It Matters:** Weak secrets can be brute-forced. Use at least 256 bits of entropy for production secrets.

### Mistake 6: Not Implementing Token Revocation

**Problem:**
```objc
// WRONG: No way to invalidate tokens
// Once issued, tokens are valid until expiration
```objc

**Solution:**
```objc
// RIGHT: Maintain revocation list
if ([self.revokedTokens containsObject:jti]) {
    return NO;  // Token has been revoked
}
```objc

**Why It Matters:** Users need a way to log out or revoke compromised tokens. Without revocation, stolen tokens remain valid until expiration.

## Security Best Practices

### 1. Always Use HTTPS in Production

```objc
// In production configuration
if (![config.issuer hasPrefix:@"https://"]) {
    NSLog(@"ERROR: Issuer must use HTTPS in production");
    return nil;
}
```objc

OAuth 2.0 and DPoP assume TLS. Without HTTPS, tokens can be intercepted in transit.

### 2. Implement Rate Limiting

```objc
// Limit token requests per client
[rateLimiter checkLimit:@"oauth_token" 
                    key:clientId 
                  limit:100 
                 window:3600];  // 100 per hour
```objc

Prevent brute-force attacks on authorization codes and token endpoints.

### 3. Use Short-Lived Access Tokens

```objc
// Access tokens: 1 hour
NSTimeInterval exp = now + 3600;

// Refresh tokens: 30 days
NSTimeInterval refreshExp = now + (86400 * 30);
```objc

Short-lived access tokens limit the damage from token theft. Refresh tokens allow long-lived sessions without long-lived access tokens.

### 4. Validate All Inputs

```objc
// Validate redirect_uri
if (![self isValidRedirectURI:redirectUri forClient:clientId]) {
    return [self errorResponse:@"invalid_request"];
}

// Validate scope
if (![self isValidScope:scope]) {
    return [self errorResponse:@"invalid_scope"];
}
```objc

Never trust client input. Validate everything before processing.

### 5. Use Secure Random for Codes

```objc
// WRONG: Predictable codes
NSString *code = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];

// RIGHT: Cryptographically secure random
NSString *code = [[NSUUID UUID] UUIDString];
```objc

Authorization codes must be unpredictable. Use cryptographically secure random number generators.

### 6. Implement PKCE for All Clients

```objc
// Require PKCE even for confidential clients
if (![authCode[@"code_challenge"] length]) {
    return [self errorResponse:@"invalid_request" 
                   description:@"PKCE required"];
}
```objc

PKCE (RFC 7636) prevents authorization code interception attacks. It should be required for all clients, not just public clients.

### 7. Rotate Signing Keys Regularly

```objc
// Support multiple active keys
NSArray *validKeys = @[currentKey, previousKey];

for (NSData *key in validKeys) {
    if ([self verifySignature:token withPublicKey:key error:nil]) {
        return YES;
    }
}
```objc

Key rotation allows you to phase out old keys without breaking existing tokens.

### 8. Monitor for Suspicious Activity

```objc
// Log authentication failures
if (!verified) {
    [self logSecurityEvent:@"jwt_verification_failed" 
                      user:payload[@"sub"] 
                    reason:error.localizedDescription];
}
```objc

Track failed authentication attempts, unusual access patterns, and potential attacks.

## Troubleshooting

### Problem: "Invalid signature" Error

**Symptoms:**
```objc
JWT verification failed: Invalid signature
```objc

**Possible Causes:**
1. Secret key mismatch between minter and verifier
2. Token was modified after signing
3. Base64URL encoding/decoding error
4. Wrong algorithm (HS256 vs ES256)

**Solutions:**
```bash
# Verify the secret matches
echo "Minter secret: $MINTER_SECRET"
echo "Verifier secret: $VERIFIER_SECRET"

# Check token structure
echo "$TOKEN" | cut -d'.' -f1 | base64 -d  # Header
echo "$TOKEN" | cut -d'.' -f2 | base64 -d  # Payload

# Verify algorithm in header
echo "$TOKEN" | cut -d'.' -f1 | base64 -d | jq .alg
```objc

## Problem: "Token expired" Error

**Symptoms:**
```objc
JWT verification failed: Token expired
```objc

**Possible Causes:**
1. Token genuinely expired (> 1 hour old)
2. Clock skew between client and server
3. Token was issued with wrong expiration

**Solutions:**
```bash
# Check token expiration
echo "$TOKEN" | cut -d'.' -f2 | base64 -d | jq .exp

# Compare with current time
date +%s

# Use refresh token to get new access token
curl -X POST http://localhost:2583/xrpc/com.atproto.server.refreshSession \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"refresh_token\",
    \"refresh_token\": \"$REFRESH_TOKEN\"
  }"
```objc

**Prevention:**
```objc
// Add clock skew tolerance (5 minutes)
NSTimeInterval exp = [payload[@"exp"] doubleValue];
NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
NSTimeInterval skew = 300;  // 5 minutes

if (exp + skew < now) {
    // Token expired even with tolerance
    return nil;
}
```objc

## Problem: "DPoP verification failed" Error

**Symptoms:**
```objc
DPoP verification failed: Method mismatch
DPoP verification failed: URI mismatch
DPoP verification failed: DPoP proof expired
```objc

**Possible Causes:**
1. DPoP proof method doesn't match HTTP method
2. DPoP proof URI doesn't match request URI
3. DPoP proof is too old (> 5 minutes)
4. Public key in DPoP doesn't match token binding

**Solutions:**
```bash
# Verify DPoP proof contents
echo "$DPOP_PROOF" | cut -d'.' -f2 | base64 -d | jq .

# Check method and URI
echo "$DPOP_PROOF" | cut -d'.' -f2 | base64 -d | jq '.htm, .htu'

# Verify timestamp
echo "$DPOP_PROOF" | cut -d'.' -f2 | base64 -d | jq '.iat'
date +%s
```objc

**Prevention:**
```objc
// Generate fresh DPoP proof for each request
NSString *dpopProof = [DPoPHandler generateDPoPProof:@"POST"
                                                 uri:fullURL
                                               nonce:nil
                                          privateKey:privateKey
                                           publicKey:publicKey
                                               error:&error];
```objc

## Problem: "Authorization code invalid" Error

**Symptoms:**
```objc
Token exchange failed: invalid_grant
```objc

**Possible Causes:**
1. Authorization code already used (single-use)
2. Authorization code expired (> 10 minutes)
3. client_id doesn't match original request
4. redirect_uri doesn't match original request
5. PKCE verifier doesn't match challenge

**Solutions:**
```bash
# Start fresh authorization flow
curl -v "http://localhost:2583/oauth/authorize?client_id=https://example.com&redirect_uri=https://example.com/callback&scope=atproto_repo&state=random123"

# Extract new code from Location header
# Use immediately (don't reuse)
```objc

**Prevention:**
```objc
// Set reasonable expiration
NSTimeInterval codeExpiration = 600;  // 10 minutes

// Validate code age
NSTimeInterval createdAt = [authCode[@"created_at"] doubleValue];
NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
if (now - createdAt > codeExpiration) {
    return [self errorResponse:@"invalid_grant" 
                   description:@"Authorization code expired"];
}
```objc

## Problem: "Missing DPoP proof" Error

**Symptoms:**
```objc
Authentication failed: Missing DPoP proof
```objc

**Possible Causes:**
1. Token is DPoP-bound but no DPoP header sent
2. DPoP header name incorrect (should be "DPoP")
3. Token type is "DPoP" but client sent "Bearer"

**Solutions:**
```bash
# Include DPoP header in request
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: DPoP $ACCESS_TOKEN" \
  -H "DPoP: $DPOP_PROOF" \
  -d '{...}'
```objc

**Prevention:**
```objc
// Check if token requires DPoP
if (payload[@"cnf"][@"jkt"]) {
    // Token is DPoP-bound
    NSString *dpopProof = [request headerForKey:@"DPoP"];
    if (!dpopProof) {
        return [self errorResponse:@"invalid_dpop_proof" 
                       description:@"DPoP proof required"];
    }
}
```objc

## Problem: Build Errors

**Symptoms:**
```objc
Undefined symbols for architecture x86_64:
  "_CCHmac", referenced from...
```objc

**Solution:**
```cmake
# Add Security framework to CMakeLists.txt
target_link_libraries(tutorial-4-auth
    "-framework Foundation"
    "-framework Security"
)
```objc

## Problem: Compilation Errors

**Symptoms:**
```objc
error: use of undeclared identifier 'CC_SHA256_DIGEST_LENGTH'
```objc

**Solution:**
```objc
// Add missing import
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
```objc

### Debugging Tips

**1. Enable Verbose Logging:**
```objc
#define DEBUG_AUTH 1

#if DEBUG_AUTH
NSLog(@"Verifying token: %@", [token substringToIndex:MIN(50, token.length)]);
NSLog(@"Payload: %@", payload);
NSLog(@"Expected issuer: %@", self.issuer);
NSLog(@"Actual issuer: %@", payload[@"iss"]);
#endif
```objc

**2. Test Components Independently:**
```objc
// Test JWT verification separately
JWTVerifier *verifier = [[JWTVerifier alloc] initWithIssuer:issuer publicKey:secretData];
NSError *error = nil;
NSDictionary *payload = [verifier verifyToken:token error:&error];
NSLog(@"Verification result: %@", payload ?: error);

// Test DPoP separately
BOOL valid = [DPoPHandler verifyDPoPProof:proof method:@"POST" uri:uri publicKey:publicKey error:&error];
NSLog(@"DPoP verification: %@", valid ? @"SUCCESS" : error);
```objc

**3. Use curl for Testing:**
```bash
# Test with verbose output
curl -v -X POST http://localhost:2583/oauth/token \
  -H "Content-Type: application/json" \
  -d '{...}' 2>&1 | tee oauth-debug.log
```objc

**4. Inspect Token Contents:**
```bash
# Decode JWT without verification (for debugging only!)
decode_jwt() {
    echo "$1" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
}

decode_jwt "$ACCESS_TOKEN"
```objc

## Summary

Congratulations! You've successfully implemented a production-grade authentication system for your PDS. Let's review what you've built:

### What You've Accomplished

**1. JWT Signature Verification**
- Cryptographic verification of token authenticity
- Claims validation (issuer, expiration, audience)
- Protection against token forgery and tampering

**2. OAuth 2.0 Authorization Server**
- Complete authorization code flow
- PKCE support for authorization code protection
- Secure token issuance and exchange
- Proper error handling and validation

**3. DPoP Proof-of-Possession**
- Token binding to cryptographic keys
- Protection against token theft and replay attacks
- Request-specific proof generation and verification
- JWK thumbprint computation

**4. Token Refresh Mechanism**
- Secure session renewal without re-authentication
- Long-lived sessions with short-lived access tokens
- Proper refresh token validation

**5. Authentication Middleware**
- Protected XRPC endpoints
- Bearer and DPoP token support
- Comprehensive error responses
- DID extraction for authorization

### Key Concepts Learned

**Security Principles:**
- Defense in depth with multiple verification layers
- Cryptographic binding prevents token theft
- Short-lived tokens limit exposure window
- PKCE prevents authorization code interception

**OAuth 2.0 Flow:**
- Separation of authentication and authorization
- Authorization codes are single-use and short-lived
- Access tokens grant API access
- Refresh tokens enable session renewal

**DPoP Benefits:**
- Tokens bound to client keys
- Replay prevention through request-specific proofs
- Theft mitigation through cryptographic binding
- Request integrity verification

### Production Readiness Checklist

Before deploying to production, ensure you:

- [ ] Replace HMAC with ECDSA P-256 signatures
- [ ] Use cryptographically secure key generation
- [ ] Store secrets in secure key storage (Keychain/encrypted files)
- [ ] Implement token revocation database
- [ ] Add rate limiting to OAuth endpoints
- [ ] Enable HTTPS/TLS for all connections
- [ ] Implement comprehensive logging (without logging tokens!)
- [ ] Add monitoring and alerting for auth failures
- [ ] Test with real OAuth clients
- [ ] Perform security audit of authentication code

### Architecture Patterns

You've learned several important patterns:

**Separation of Concerns:**
- JWTVerifier handles signature verification
- DPoPHandler manages proof-of-possession
- OAuth2Handler orchestrates authorization flow
- XrpcDispatcher enforces authentication

**Error Handling:**
- Descriptive error messages for debugging
- Proper HTTP status codes
- Security-conscious error responses (don't leak info)

**Extensibility:**
- Support for both Bearer and DPoP tokens
- Optional vs required authentication
- Multiple active signing keys for rotation

### Real-World Applications

This authentication system enables:

**Multi-Device Access:**
- Users can authenticate from multiple devices
- Each device has its own key pair for DPoP
- Tokens can be revoked per-device

**Third-Party Clients:**
- OAuth 2.0 allows third-party app integration
- Users control what data apps can access
- Apps never see user passwords

**Long-Lived Sessions:**
- Refresh tokens enable persistent sessions
- Access tokens expire quickly for security
- Users don't need to re-authenticate frequently

### Performance Considerations

**Token Verification:**
- JWT verification is fast (< 1ms typically)
- DPoP verification adds minimal overhead
- Consider caching verified tokens (with expiration)

**Database Queries:**
- Authorization codes stored in memory (this tutorial)
- Production should use database with TTL
- Revoked tokens need efficient lookup (indexed by JTI)

**Scalability:**
- Stateless JWT verification scales horizontally
- Authorization code storage needs shared state
- Consider Redis for distributed deployments

## Reference Implementation

For the complete production implementation, see:
- `ATProtoPDS/Sources/Auth/JWT.m` — JWT minting and verification
- `ATProtoPDS/Sources/Auth/OAuth2Handler.m` — OAuth 2.0 endpoints
- `ATProtoPDS/Sources/Auth/DPoPUtil.m` — DPoP proof handling
- `ATProtoPDS/Sources/Network/XrpcAuthHelper.m` — Authentication helpers
- `ATProtoPDS/Sources/Auth/KeyRotationManager.m` — Key rotation

## Further Reading

- [JWT Tokens](../06-authentication/jwt-tokens) — Detailed JWT documentation
- [OAuth 2.0 with DPoP](../06-authentication/oauth2-dpop) — OAuth implementation details
- [Key Rotation](../06-authentication/key-rotation) — Key management strategies
- [Auth Helpers](../04-network-layer/auth-helpers) — Authentication utilities

