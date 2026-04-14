---
title: JWT Client Authentication Implementation Plan
---

# JWT Client Authentication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement JWT client authentication for confidential OAuth clients in the ATProto PDS, enabling secure client authentication using signed JWT assertions.

**Architecture:** Extend the existing OAuth2 and JWT infrastructure to support private_key_jwt client authentication method. Add JWKS endpoint for public key distribution, client assertion generation, and validation of signed client assertions during token requests.

**Tech Stack:** Objective-C, JWT framework (existing), OAuth2 framework (existing), Secp256k1 cryptography (existing)

## Task 1: Extend JWT Framework for Client Assertions

**Files:**
- Modify: `Garazyk/Garazyk/Auth/JWT.h`
- Modify: `Garazyk/Garazyk/Auth/JWT.m`

**Step 1: Add client assertion JWT creation method**

```objective-c
@interface JWTMinter (ClientAssertions)

- (NSString *)createClientAssertionForClientID:(NSString *)clientID
                                      audience:(NSString *)audience
                                         error:(NSError **)error;

@end
```

**Step 2: Implement client assertion creation**

Add method implementation that creates a JWT with client-specific claims for OAuth client authentication.

**Step 3: Add JWT verification for client assertions**

```objective-c
@interface JWTVerifier (ClientAssertions)

- (BOOL)verifyClientAssertion:(JWT *)jwt
                  forClientID:(NSString *)clientID
                      audience:(NSString *)audience
                        error:(NSError **)error;

@end
```

**Step 4: Test client assertion creation and verification**

Run unit tests to verify JWT client assertion functionality works correctly.

## Task 2: Add JWKS (JSON Web Key Set) Support

**Files:**
- Create: `Garazyk/Garazyk/Auth/JWKS.h`
- Create: `Garazyk/Garazyk/Auth/JWKS.m`
- Modify: `Garazyk/Garazyk/Auth/OAuth2Server.h`
- Modify: `Garazyk/Garazyk/Auth/OAuth2Server.m`

**Step 1: Create JWKS data structures**

Define JWK (JSON Web Key) and JWKS (JSON Web Key Set) classes with ES256 key support.

**Step 2: Implement JWKS endpoint in OAuth2Server**

Add JWKS URI endpoint that serves public keys for client authentication validation.

**Step 3: Add client key registration and storage**

Extend OAuth2Server to store and manage client public keys for validation.

**Step 4: Test JWKS endpoint and key retrieval**

Verify JWKS endpoint returns properly formatted key sets.

## Task 3: Extend OAuth2 for private_key_jwt Authentication

**Files:**
- Modify: `Garazyk/Garazyk/Auth/OAuth2.h`
- Modify: `Garazyk/Garazyk/Auth/OAuth2.m`
- Modify: `Garazyk/Garazyk/Auth/OAuth2TokenRequest.h`
- Modify: `Garazyk/Garazyk/Auth/OAuth2TokenRequest.m`

**Step 1: Add client assertion fields to OAuth2TokenRequest**

Add `client_assertion` and `client_assertion_type` parameters to token request handling.

**Step 2: Implement private_key_jwt authentication method**

Add validation logic to verify client assertions during token requests.

**Step 3: Update token request processing**

Modify token endpoint to accept and validate JWT client authentication.

**Step 4: Test private_key_jwt token requests**

Verify end-to-end client authentication flow with signed assertions.

## Task 4: Add Session Binding to Authentication Keys

**Files:**
- Modify: `Garazyk/Garazyk/Auth/Session.h`
- Modify: `Garazyk/Garazyk/Auth/Session.m`
- Modify: `Garazyk/Garazyk/Auth/OAuth2Server.h`
- Modify: `Garazyk/Garazyk/Auth/OAuth2Server.m`

**Step 1: Add key binding to session objects**

Extend Session class to store and track authentication key information.

**Step 2: Implement key binding during authentication**

Bind client authentication keys to sessions for security validation.

**Step 3: Add key validation for session operations**

Ensure session operations validate against bound authentication keys.

**Step 4: Test session key binding**

Verify that sessions are properly bound to authentication keys.

## Task 5: Implement Error Handling

**Files:**
- Modify: `Garazyk/Garazyk/Auth/OAuth2.h`
- Modify: `Garazyk/Garazyk/Auth/OAuth2.m`
- Modify: `Garazyk/Garazyk/Auth/JWT.h`
- Modify: `Garazyk/Garazyk/Auth/JWT.m`

**Step 1: Add OAuth2 client authentication errors**

Add specific error codes for client authentication failures.

**Step 2: Add JWT client assertion validation errors**

Add detailed error codes for client assertion validation failures.

**Step 3: Implement error propagation**

Ensure errors are properly propagated through the authentication flow.

**Step 4: Test error handling scenarios**

Verify proper error responses for various authentication failure cases.

## Task 6: Add Integration Tests and Documentation

**Files:**
- Create: `Garazyk/Garazyk/Auth/OAuthJWTClientAuthTests.m`
- Modify: `docs/README.md`

**Step 1: Create  test suite**

Add tests for all JWT client authentication scenarios.

**Step 2: Test full authentication flow**

Verify end-to-end JWT client authentication works correctly.

**Step 3: Add usage documentation**

Document how to configure and use JWT client authentication.

**Step 4: Update API documentation**

Document new OAuth2 client authentication endpoints and parameters.

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [OAuth2 Documentation](../../oauth2/README) - OAuth2 implementation details
- [Security Docs](../../security/README) - Security-related documentation