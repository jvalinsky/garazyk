# Bugfix Requirements Document

## Introduction

Users cannot successfully log in to the PDS at https://pds.garazyk.xyz from Bluesky clients (bsky.app, witchsky.app, or other ATProto-compatible clients). The OAuth2 authorization flow fails to complete, preventing authentication.

**Current implementation status:**
- The PDS has OAuth 2.0 implementation with PKCE, DPoP, and PAR support
- Client validation requires database pre-registration in `oauth_clients` table
- The `validateClient` method in OAuth2Handler.m queries the database and rejects unknown clients

**ATProto OAuth specification requirements:**
- Reference: https://atproto.com/specs/oauth
- Reference: https://docs.bsky.app/docs/advanced-guides/oauth-client
- ATProto defines a specific OAuth 2.0 profile for federated authentication
- Clients should be able to authenticate with any PDS following the specification

**The root cause:** The PDS OAuth implementation does not fully conform to the ATProto OAuth specification, specifically regarding client validation and registration requirements. This prevents standard ATProto clients from authenticating with the PDS.

**The solution:** Update the OAuth implementation to fully conform to the ATProto OAuth specification at https://atproto.com/specs/oauth, ensuring compatibility with standard ATProto clients like bsky.app.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN an ATProto client (bsky.app, witchsky.app) attempts OAuth authorization THEN the system returns "unauthorized_client" error because validateClient requires the client_id to exist in the oauth_clients database table

1.2 WHEN an ATProto client provides a redirect_uri during authorization THEN the system returns "Invalid redirect_uri" error because validateRedirectURI requires exact match against pre-registered URIs in the database

1.3 WHEN an ATProto client attempts token exchange THEN the system returns "invalid_client" error because the client_id is not found in the oauth_clients table

1.4 WHEN the OAuth implementation is compared against the ATProto OAuth specification THEN the system does not conform to the specification's client validation requirements

### Expected Behavior (Correct)

2.1 WHEN an ATProto client attempts OAuth authorization THEN the system SHALL validate the client according to the ATProto OAuth specification at https://atproto.com/specs/oauth

2.2 WHEN an ATProto client provides PKCE parameters (code_challenge, code_challenge_method) THEN the system SHALL validate and accept them according to RFC 7636 and ATProto requirements

2.3 WHEN an ATProto client provides a redirect_uri THEN the system SHALL validate it according to ATProto OAuth security requirements as specified in the ATProto OAuth specification

2.4 WHEN an ATProto client completes token exchange with valid DPoP proof and PKCE code_verifier THEN the system SHALL issue access and refresh tokens according to the ATProto OAuth specification

2.5 WHEN OPTIONS preflight requests are sent to OAuth endpoints THEN the system SHALL respond with appropriate CORS headers allowing cross-origin requests from ATProto clients

2.6 WHEN /.well-known/oauth-authorization-server is requested THEN the system SHALL return OAuth metadata conforming to RFC 8414 and ATProto OAuth requirements with proper CORS headers

2.7 WHEN the OAuth implementation is audited against the ATProto OAuth specification THEN the system SHALL conform to all mandatory requirements

### Unchanged Behavior (Regression Prevention)

3.1 WHEN existing registered OAuth clients attempt authorization THEN the system SHALL CONTINUE TO validate and process their requests correctly

3.2 WHEN PKCE validation is performed THEN the system SHALL CONTINUE TO enforce PKCE requirements (code_challenge required, S256 method supported, code_verifier validation)

3.3 WHEN DPoP proof validation is performed for token requests THEN the system SHALL CONTINUE TO enforce DPoP requirements per RFC 9449

3.4 WHEN OAuth metadata endpoints (/.well-known/oauth-authorization-server, /oauth/jwks) are accessed THEN the system SHALL CONTINUE TO return correct metadata structure

3.5 WHEN token lifecycle operations (issuance, refresh, revocation) are performed THEN the system SHALL CONTINUE TO function correctly

3.6 WHEN non-OAuth authentication methods (XRPC com.atproto.server.createSession) are used THEN the system SHALL CONTINUE TO function without modification

3.7 WHEN security validations (CSRF protection, state parameter, nonce validation) are performed THEN the system SHALL CONTINUE TO enforce security requirements
