# ADR 0019: CAPTCHA Gate Fails Closed and Implements Real Siteverify

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S13 (phase-23 slice 1) found that the CAPTCHA registration gate's
`verifyTokenWithSiteverify:` method (originally at
`PDSCaptchaRegistrationGate.m:75`, rearranged to `:95` after implementation) was
a no-op: it returned `YES` unconditionally with `#pragma unused(verifyURL)`. A
separate token-presence path accepted any non-empty string when no secret key was
configured. Together, these two paths meant the CAPTCHA gate never actually
verified a CAPTCHA token against any provider.

The gate contributes to the composite registration check at
`PDSRegistrationGate.m:73-86`, which OR-s gates together. A no-op gate that
returns `YES` for any input defeats every other gate in the composite. An
operator who enables `captchaRequired` without configuring a secret key gets a
gate that appears to work but silently accepts all tokens.

The composite dispatches through `XrpcServerPack+Session.m:68-74`, which passes
the client IP (`request.remoteAddress`) when the gate implements the three-param
protocol variant introduced in this slice.

Two alternatives were considered:

- **Keep the no-secret-key accept path behind a deprecation flag.** An operator
  who enabled the gate without a key would get a runtime warning but the gate
  would still accept token presence. This was rejected because it preserves the
  footgun — a warning in a log is not a signal an operator actively monitors,
  and the gate's `YES` return defeats every other gate via composite OR.

- **Use a separate HTTP client instance per siteverify call.** The
  `PDSEmailHTTPClient` instantiates `NSURLSession` on each request. Reusing
  `ATProtoSafeHTTPClient` (already used by `PDSEmailHTTPClient.m:23`) with a
  configurable timeout avoids duplicating the connection pool and timeout
  infrastructure.

## Decision

1. **The CAPTCHA gate fails closed when no secret key is configured.** The
   no-secret path at `PDSCaptchaRegistrationGate.m:79-81` now returns `NO` with
   a `PDSRegistrationGateErrorCaptchaRequired` error rather than accepting token
   presence. The factory at `PDSRegistrationGate.m:190-193` logs a startup
   warning when `captchaRequired` is `YES` and `captchaSecretKey` is empty:
   "CAPTCHA gate enabled but no secret key configured; registration will fail
   until PDS_CAPTCHA_SECRET_KEY is set." This matches the phase-22
   `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` warning pattern documented in
   `PDSApplication.m:526-532`. Operators who want open registration use
   `PDSOpenRegistrationGate` explicitly via configuration.

2. **The siteverify call is real, not a no-op.** `verifyTokenWithSiteverify:` at
   `:95` sends a form-encoded POST to the provider's siteverify endpoint using
   `ATProtoSafeHTTPClient`:

   - Turnstile: `https://challenges.cloudflare.com/turnstile/v0/siteverify`
   - hCaptcha: `https://hcaptcha.com/siteverify`

   The body is `secret=<key>&response=<token>&remoteip=<address>`. The response
   must include `"success": true`. Any non-200, missing `success` field, parse
   failure, or network timeout is a hard rejection: 503 on network error
   (matching the S10 egress-hardening decision), 400 on `success: false`. The
   gate does not accept the token on timeout — a configured secret key means
   the operator intends real verification, and a network failure must not
   silently downgrade to token-presence.

3. **The client IP is forwarded to the siteverify endpoint.** The
   `PDSRegistrationGate` protocol gained an optional method
   `validateRegistrationRequest:configuration:remoteAddress:error:` at
   `PDSRegistrationGate.h`. The composite at `PDSRegistrationGate.m:73-86`
   `respondsToSelector:`-checks the new method and dispatches to it when
   present, passing the `remoteip` parameter to the siteverify POST at
   `PDSCaptchaRegistrationGate.m:120`. The XRPC handler at
   `XrpcServerPack+Session.m:68-70` passes `request.remoteAddress` through.
   This is the only new outbound dependency in phase 23 and is scoped to
   slice 1.

4. **The siteverify timeout is configurable via a property, with a safe
   default.** `siteverifyTimeout` at `PDSCaptchaRegistrationGate.m:28` defaults
   to 12.0 seconds. Tests override it to 0.5 seconds via a Testing category
   (`PDSCaptchaRegistrationGateTests.m`) so the timeout test runs in under a
   second rather than 12. The semaphore wait uses the property value; a
   semaphore timeout returns 503 to the client.

## Consequences

- **Operators who relied on the no-op behavior must reconfigure.** Any
  deployment that enabled `captchaRequired` without a `captchaSecretKey` and
  relied on the gate accepting all tokens (effectively open registration) must
  switch to `PDSOpenRegistrationGate` explicitly. The gate now fails closed with
  a startup warning and registration errors until the secret key is set.

- **New outbound dependency on the CAPTCHA provider.** The PDS now makes an
  HTTPS call to Cloudflare Turnstile or hCaptcha on every registration. If the
  provider is unreachable, the gate returns 503 rather than silently accepting
  — the client retries, but registration throughput depends on provider
  availability. Operators should monitor siteverify latency and error rates.

- **No downgrade to token-presence on network failure.** The fail-closed design
  means a network partition between the PDS and the CAPTCHA provider stops all
  CAPTCHA-gated registrations. This is intentional: a configured secret key
  signals operator intent to verify, and silent downgrade defeats that intent.

- **Remote IP forwarding requires the protocol extension.** The composite
  dispatches to the three-param method via `respondsToSelector:`, so existing
  gate implementations that do not implement it are unaffected. The CAPTCHA
  gate is the only consumer in this phase; future gates that need client IP can
  adopt the same protocol method.

- **Rollback.** Revert the slice-1 commit to restore the no-op `verifyToken`
  and no-secret accept paths. Operators who deployed without a secret key will
  return to the open-registration behavior. The protocol extension is backward-
  compatible (optional method) so reverting does not break existing callers.

- **Test suite.** `PDSCaptchaRegistrationGateTests.m` (17 tests) covers:
  no-secret fail-closed, empty-secret fail-closed, siteverify success,
  `success:false` → 400, network error → 503, non-200 → 503, unparseable → 503,
  timeout → 503, hCaptcha routing, Turnstile routing, default provider routing,
  remoteAddress inclusion/omission, form percent-encoding. The suite uses a
  `MockCaptchaSiteverifyHTTPClient` injection via Testing category.
