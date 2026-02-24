# Bugfix Requirements Document

## Introduction

The ATProto PDS has two authentication and OAuth interoperability issues that break RFC compliance and cause metadata inconsistencies:

1. **Issue B2**: DPoP nonce handling reads from request header instead of JWT proof claim, violating RFC 9449 §4.3
2. **Issue B3**: OAuth .well-known metadata routes are duplicated between HttpRouter and OAuth2Handler, creating divergent metadata sources

These issues impact OAuth client interoperability and force unnecessary authentication roundtrips. The fixes ensure RFC 9449 compliance and establish a single source of truth for OAuth metadata.

## Bug Analysis

### Current Behavior (Defect)

#### Issue B2: DPoP Nonce Handling

1.1 WHEN a client sends a DPoP-authenticated request THEN the system reads the nonce from the `DPoP-Nonce` HTTP request header instead of from the DPoP proof JWT's `nonce` claim

1.2 WHEN the server validates DPoP proofs THEN the system expects nonces in HTTP headers rather than in the JWT payload as specified by RFC 9449 §4.3

1.3 WHEN a standards-compliant OAuth client includes nonce in the JWT proof claim THEN the system ignores it and may reject valid proofs

#### Issue B3: OAuth Metadata Route Duplication

1.4 WHEN OAuth metadata is requested via .well-known paths THEN the system has four route registrations in HttpRouter (lines 277, 314, 324, 374) AND separate metadata serving in OAuth2Handler

1.5 WHEN multiple handlers serve the same OAuth metadata THEN the system may return divergent metadata depending on which handler processes the request

1.6 WHEN OAuth2Handler metadata logic is updated THEN the system may still serve stale metadata from HttpRouter registrations

### Expected Behavior (Correct)

#### Issue B2: DPoP Nonce Handling

2.1 WHEN the server requires a DPoP nonce THEN the system SHALL issue the nonce in the `DPoP-Nonce` response header (server-to-client direction)

2.2 WHEN a client sends a DPoP-authenticated request with a nonce THEN the system SHALL read the nonce from the DPoP proof JWT's `nonce` claim (not from request headers)

2.3 WHEN validating DPoP proofs THEN the system SHALL verify the `nonce` claim in the JWT payload matches the server-issued nonce per RFC 9449 §4.3

2.4 WHEN a DPoP proof is missing a required nonce THEN the system SHALL return 401 with a new nonce in the `DPoP-Nonce` response header

#### Issue B3: OAuth Metadata Route Duplication

2.5 WHEN OAuth metadata is requested via .well-known paths THEN the system SHALL route requests to OAuth2Handler as the single source of truth

2.6 WHEN .well-known/oauth-authorization-server is requested THEN the system SHALL return metadata exclusively from OAuth2Handler

2.7 WHEN .well-known/oauth-protected-resource is requested THEN the system SHALL return metadata exclusively from OAuth2Handler

2.8 WHEN OAuth2Handler metadata logic is updated THEN the system SHALL serve the updated metadata without requiring changes to HttpRouter

### Unchanged Behavior (Regression Prevention)

#### DPoP Authentication Flow

3.1 WHEN a client sends a valid DPoP proof with correct nonce THEN the system SHALL CONTINUE TO successfully authenticate the request

3.2 WHEN extractDIDFromAuthHeader is called from any of the 44 call sites THEN the system SHALL CONTINUE TO extract and validate DIDs correctly

3.3 WHEN PDSNonceManager generates and validates nonces THEN the system SHALL CONTINUE TO use the existing nonce storage and validation logic

3.4 WHEN DPoP proof validation fails for reasons other than nonce THEN the system SHALL CONTINUE TO return appropriate error responses

#### OAuth Metadata Serving

3.5 WHEN OAuth clients request .well-known metadata THEN the system SHALL CONTINUE TO return valid OAuth 2.0 authorization server metadata

3.6 WHEN OAuth2Handler serves metadata THEN the system SHALL CONTINUE TO include all required OAuth 2.0 metadata fields

3.7 WHEN non-OAuth routes are processed THEN the system SHALL CONTINUE TO route requests correctly through HttpRouter

3.8 WHEN PDSHttpServerBuilder wires up handlers THEN the system SHALL CONTINUE TO initialize OAuth2Handler and HttpRouter correctly
