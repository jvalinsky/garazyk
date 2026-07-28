# Phase 26: Admin and AdminUIServer Trust-Boundary Sweep

## Mission

Harden the Admin (PDSAdminAuth, PDSAdminController, AdminMiddleware) and
AdminUIServer (UIAuthManager, UIServerRuntime, UIServiceConfig) trust
boundaries by closing credential-leak surfaces, tightening input validation,
and eliminating silent-auth paths. Both modules sit at a critical boundary —
they authenticate the PDS operator and serve the web UI that controls
account lifecycle, moderation, and configuration. Findings span plaintext
credential logging, unvalidated JSON at the admin-auth boundary, CSRF token
predictability, and an admin DID list that is read but never verified by
the admin middleware.

S13 (Registration/PhoneVerification/Email) and S14 (Ozone moderation) are
complete. Admin and AdminUIServer are the next highest-risk surfaces.

## Read-First

- `Garazyk/Sources/Admin/PDSAdminAuth.m` — admin password validation,
  token lifecycle, admin DID management (line 290: untested request
  validation).
- `Garazyk/Sources/Admin/AdminMiddleware.m` — middleware that checks
  admin tokens against the admin DID list (currently reads the DID list
  but does not verify the caller's DID is in it at all paths).
- `Garazyk/Sources/Admin/PDSAdminController.m` — thin controller
  delegating to PDSAdminService.
- `Garazyk/Sources/AdminUIServer/UIAuthManager.m` — UI session tokens,
  CSRF protection, cookie management.
- `Garazyk/Sources/AdminUIServer/UIServerRuntime.m` — runtime
  configuration and route wiring.
- `Garazyk/Sources/AdminUIServer/UIServiceConfig.m` — configuration
  loading (139 lines).
- `Garazyk/Tests/Admin/PDSAdminAuthTests.m` — existing admin auth tests
  (line of sight for new gate tests).
- `Garazyk/Tests/AdminUIServer/UIAuthManagerTests.m` — existing UI auth
  tests (check existence).

## Decisions

### D1: Admin DID list verification gap

`AdminMiddleware.m` reads `adminDids` from configuration but does not
verify that the authenticated caller's DID is present in the list on all
code paths. Fix: add DID-set membership check in the middleware's
`handleRequest:` before delegating to the next handler. Reject with 403
if the DID is not in the admin set.

### D2: Plaintext credential logging

`PDSAdminAuth.m` logs the admin password during failed authentication
attempts. This leaks secrets to the log stream. Fix: redact the password
from all log statements using `GZLogRedactor` or equivalent masking
before logging.

### D3: CSRF token nonce generation

`UIAuthManager.m` generates CSRF tokens. Audit the entropy source: if
it uses `arc4random` or a low-entropy PRNG, replace with
`SecRandomCopyBytes` (256-bit). If the token is embedded in a cookie
without `SameSite=Strict`, add the attribute.

### D4: Unvalidated JSON at the admin-auth boundary

Same defect class as S8 and S13. `PDSAdminAuth.m:290` checks
`isKindOfClass:[NSDictionary class]` on the request body but the admin
controller and middleware extract fields without similar guards. Add
`isKindOfClass:` checks to all field extractions at the admin boundary.

### D5: Admin session token TTL and rotation

`UIAuthManager.m` creates session tokens — verify the TTL is enforced
and that tokens are invalidated on password change (rotation). If tokens
persist across password changes, an attacker with a stolen session can
retain access indefinitely.

### D6: Admin UI static asset path traversal

`UIServerRuntime+StaticAssets.m` serves static files for the admin UI.
Audit the path resolution for directory traversal: ensure `..` sequences
and absolute paths are rejected, and that the served directory is
constrained to the configured asset root.

## Slices

1. Admin DID list verification: add DID-set membership check in
   AdminMiddleware, reject non-admin DIDs with 403, add tests.
2. Plaintext credential redaction: redact admin password from all
   PDSAdminAuth log statements, add a test verifying the password does
   not appear in log output.
3. CSRF token hardening: audit UIAuthManager CSRF entropy, upgrade to
   SecRandomCopyBytes if needed, add SameSite=Strict to the CSRF cookie.
4. Input validation sweep: add `isKindOfClass:` guards to all field
   extractions in PDSAdminController, AdminMiddleware, and UIServerRuntime.
5. Session token rotation: enforce TTL on UIAuthManager session tokens,
   invalidate on password change, add tests.
6. Static asset path hardening: audit UIServerRuntime+StaticAssets for
   directory traversal, constrain to asset root, add tests.
7. Admin audit logging: add admin action audit log entries for
   password changes, admin DID list modifications, and session creation.

## Gate

All acceptance gate tests pass:
- Non-admin DID reaches admin endpoint → 403.
- Admin password does not appear in logs after failed auth.
- CSRF token is 256-bit entropy and cookie has SameSite=Strict.
- Malformed JSON fields at the admin boundary are rejected (400, not
  crash via `NSInvalidArgumentException`).
- Session token is invalidated after password change.
- Directory traversal path returns 404 or 400, not a file from outside
  the asset root.

## Rollback

Each slice is a self-contained commit. If a slice introduces test
regressions, revert that slice's commit. The admin DID list check (slice
1) is the highest risk — roll it back if it breaks existing admin
workflows; the remaining slices are purely additive.
