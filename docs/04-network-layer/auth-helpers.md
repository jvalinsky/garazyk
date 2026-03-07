---
title: Auth Helpers
---

# Auth Helpers

## Overview

`XrpcAuthHelper` is the main authentication boundary for XRPC endpoints. It
centralizes the logic that would otherwise be easy to reimplement badly in many
handlers: header parsing, JWT verification, DPoP proof checks, audience and
issuer validation, account takedown checks, and admin authorization helpers.

This is one of the most important "why" pages in the docs because auth bugs are
usually bugs of duplicated logic.

## Supported Auth Shapes

The helper currently understands:

- `Bearer` authorization with JWT access tokens
- `DPoP` authorization, including clients that send `Bearer` plus a `DPoP`
  proof header

That dual support matters because the helper is not just parsing a token
string. It is deciding how the request should be verified.

## DPoP Verification

For DPoP-protected requests, the helper:

- builds the expected request URL
- verifies the DPoP proof against request method and URL
- optionally enforces nonce use
- issues a `DPoP-Nonce` challenge when the client must retry
- binds the access token to the presented DPoP key via `cnf.jkt`

This is exactly the kind of logic that should stay centralized. If each handler
implemented its own version, the server would drift into inconsistent security
behavior very quickly.

## JWT Verification

After auth-header parsing, the helper verifies the JWT using `JWTVerifier` and
the configured key material from the minter. It derives the expected issuer from
the runtime configuration and applies custom audience checks that support the
server's identity model.

The useful takeaway is not "JWTs exist". It is that the helper owns the
repository's current interpretation of valid token identity.

## Proxy And Host Header Handling

DPoP verification depends on the expected request URL, which means proxy
behavior matters. The helper only trusts forwarded headers when
`PDS_TRUST_PROXY_HEADERS` is enabled and the remote address is treated as a
trusted proxy.

That rule is easy to miss, and it explains a lot of local-versus-production
auth mismatches.

## Account And Admin Checks

Authentication success is not the end of the path. The helper also checks
account moderation state through the admin controller and provides the admin
authorization entry point used by privileged routes.

That means "valid token" and "allowed request" are deliberately separate
questions in the current architecture.

## Failure Modes That Matter

When auth fails, start with these questions:

- was the request expected to be `Bearer` or `DPoP`?
- did the helper issue a nonce challenge?
- does the token issuer and audience match the runtime identity?
- does the token's `cnf.jkt` match the DPoP proof?
- is the account suspended or taken down?

Most auth debugging becomes straightforward once those questions are answered.

## Related Deep Dives

- [OAuth + DPoP Request Walkthrough](../06-authentication/oauth-dpop-request-walkthrough)
- [Session and JWT Lifecycle](../06-authentication/session-and-jwt-lifecycle)
- [From NSID to Service Call](./from-nsid-to-service-call)

## Related Reading

- [Error Handling](./error-handling)
- [ATProto Basics](../02-core-concepts/atproto-basics)
- [Cryptography](../02-core-concepts/cryptography)
- [Troubleshooting](../11-reference/troubleshooting)
