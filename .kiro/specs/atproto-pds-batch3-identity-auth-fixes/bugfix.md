# Bugfix Requirements Document

## Introduction

The AT Protocol PDS has two critical identity and authentication issues that break federation, signature verification, and JWT client compatibility:

**Issue A1: identity.resolveDid returns synthetic DID documents with placeholder keys** - The resolveDid helper function in XrpcMethodRegistry.m (lines 200-231) constructs synthetic DID documents for local accounts when PLC resolution fails, but omits the verificationMethod array entirely. This breaks federated consumers that need to verify signatures or resolve identity, as they cannot obtain the account's actual public key.

**Issue B1: Session tokens inconsistently JWT vs UUID** - PDSAccountService.m has three code paths (lines 167, 270, 335) that generate refresh tokens using `[[NSUUID UUID] UUIDString]` instead of JWTs. While access tokens are correctly generated as JWTs (with proper fallback error handling when minter is nil), refresh tokens remain UUIDs. This creates inconsistency in the token system and breaks JWT-based refresh flows.

These bugs prevent proper repository synchronization, signature verification, and authentication token handling across federated servers.

## Bug Analysis

### Current Behavior (Defect)

**Issue A1: identity.resolveDid returns synthetic DID documents without verification methods**

1.1 WHEN the resolveDid helper function is called for a local account AND PLC resolution fails or is unavailable THEN the system constructs a synthetic DID document with @context, id, alsoKnownAs, and service fields but omits the verificationMethod array entirely

1.2 WHEN a federated consumer attempts to verify a signature from this DID THEN the system provides no public key material in the DID document, causing signature verification to fail

1.3 WHEN a federated consumer resolves identity for a local account THEN the system returns a DID document without the account's actual signing key

1.4 WHEN PLC directory is reachable and contains the DID THEN the system correctly returns the full DID document from DIDPLCResolver including verificationMethod

**Issue B1: Session tokens inconsistently JWT vs UUID**

1.5 WHEN createAccount generates tokens (line 167) THEN the system generates accessToken as JWT but refreshToken as UUID string

1.6 WHEN createSession generates tokens (line 270) THEN the system generates accessToken as JWT but refreshToken as UUID string

1.7 WHEN refreshSession generates tokens (line 335) THEN the system generates new accessToken as JWT but newRefreshToken as UUID string

1.8 WHEN JWT minter is nil in any of these paths THEN the system correctly returns an error for accessToken but would have fallen back to UUID for refreshToken

1.9 WHEN clients receive session responses with refreshJwt field THEN the system provides a UUID string instead of a JWT, breaking JWT-based refresh token parsing

### Expected Behavior (Correct)

**Issue A1: identity.resolveDid returns synthetic DID documents without verification methods**

2.1 WHEN the resolveDid helper function is called for any DID THEN the system SHALL delegate to DIDPLCResolver.resolveDID:error: and return the result directly without constructing synthetic documents

2.2 WHEN DIDPLCResolver successfully resolves a DID from PLC directory THEN the system SHALL return the complete DID document including verificationMethod array with real key material

2.3 WHEN DIDPLCResolver fails to resolve a DID (network error, DID not found, etc.) THEN the system SHALL return nil and propagate the error, not construct a synthetic fallback

2.4 WHEN a federated consumer attempts to verify a signature from this DID THEN the system SHALL provide the complete DID document with verificationMethod containing the account's actual public key

**Issue B1: Session tokens inconsistently JWT vs UUID**

2.5 WHEN createAccount generates tokens THEN the system SHALL generate both accessToken and refreshToken as JWTs using self.minter

2.6 WHEN createSession generates tokens THEN the system SHALL generate both accessToken and refreshToken as JWTs using self.minter

2.7 WHEN refreshSession generates tokens THEN the system SHALL generate both new accessToken and newRefreshToken as JWTs using self.minter

2.8 WHEN JWT minter is nil in any of these paths THEN the system SHALL return an error immediately without generating any tokens

2.9 WHEN clients receive session responses with refreshJwt field THEN the system SHALL provide a valid JWT that can be parsed and verified

### Unchanged Behavior (Regression Prevention)

**Issue A1: identity.resolveDid returns synthetic DID documents without verification methods**

3.1 WHEN com.atproto.identity.resolveDid is called with a valid did:plc DID THEN the system SHALL CONTINUE TO return HTTP 200 with a complete DID document

3.2 WHEN com.atproto.identity.resolveDid is called with an invalid DID THEN the system SHALL CONTINUE TO return an appropriate error response

3.3 WHEN DIDPLCResolver caches resolved DID documents THEN the system SHALL CONTINUE TO use the cache for subsequent resolutions

3.4 WHEN resolveDid helper function is called for did:web DIDs THEN the system SHALL CONTINUE TO return an error for unsupported DID methods

**Issue B1: Session tokens inconsistently JWT vs UUID**

3.5 WHEN createAccount is called with valid credentials THEN the system SHALL CONTINUE TO return a session response with did, handle, email, accessJwt, and refreshJwt fields

3.6 WHEN createSession is called with valid credentials THEN the system SHALL CONTINUE TO return a session response with did, handle, email, accessJwt, and refreshJwt fields

3.7 WHEN refreshSession is called with a valid refresh token THEN the system SHALL CONTINUE TO return a session response with accessJwt, refreshJwt, handle, and did fields

3.8 WHEN refresh tokens are stored in the session repository THEN the system SHALL CONTINUE TO store and validate them correctly

3.9 WHEN refresh tokens are revoked during rotation THEN the system SHALL CONTINUE TO revoke the old token before generating a new one

3.10 WHEN JWT minter is properly configured THEN the system SHALL CONTINUE TO generate valid JWTs with correct claims (DID, handle, scopes)
