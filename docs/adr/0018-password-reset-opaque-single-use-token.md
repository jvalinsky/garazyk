# ADR 0018: Password Reset Uses Opaque Single-Use Tokens, Not the Account DID

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S13 (phase-23 slice 4) identified a critical authorization
bypass in the password-reset flow. The `resetPassword` handler at
`XrpcServerPack+AccountManagement.m:204-249` validates the `token` parameter
as a DID (`ATProtoValidator validateDID:token` at `:225-229`) and then looks
up the account by that DID (`getAccountByDid:token` at `:230-235`). Because
DIDs are public identifiers — they appear in every record URI, every DID
document, every firehose event — any attacker who knows a victim's DID can
reset their password without access to the victim's email.

The companion `requestPasswordReset` handler at `:188-202` is a complete
no-op: it validates the email format (`:193-198`) and returns 200 with an
empty body (`:200`). It does not mint a token, does not send an email, and
does not store anything. The intended flow — request reset → receive email
with token → exchange token for password change — was never implemented.

Two alternatives were considered:

- **Keep the DID-as-token path but require email ownership proof.** The
  handler could verify that the caller controls the account's email before
  accepting the DID. This was rejected because it conflates two trust
  boundaries: the reset token should be a proof-of-email-ownership artifact,
  not a re-derivation of public identity. It also requires an email-send
  step regardless, so the token infrastructure is needed either way.

- **Use a signed JWT as the reset token.** A JWT minted by the PDS could
  carry the DID claim and an expiry, avoiding a database table. This was
  rejected because JWTs are not naturally single-use: enforcing single-use
  requires a revocation list or a `jti` replay cache (the same machinery
  ADR 0014 added for DPoP). An opaque token stored in the service DB is
  simpler, atomically single-use via a `used_at` column update, and does
  not require a replay cache or JWT verification on the reset path.

## Decision

1. **The reset token is an opaque, single-use, time-bounded random string,
   not a DID.** The token is a 32-byte cryptographically random value,
   base64url-encoded, stored in a new `password_reset_tokens` table in the
   service DB (migration V18 — V16 and V17 are taken by phase-23 slices 2c
   and 3b; each slice ships its own migration so slices remain independently
   revertible). The table schema is:

   | Column       | Type    | Constraints                    |
   | ------------ | ------- | ------------------------------ |
   | `token`      | TEXT    | PRIMARY KEY                    |
   | `did`        | TEXT    | NOT NULL (FK to accounts)      |
   | `expires_at` | INTEGER | NOT NULL                       |
   | `used_at`    | INTEGER | NULL (set on successful reset) |

   TTL is 15 minutes. Single-use is enforced atomically: `resetPassword`
   updates `used_at = now` in the same transaction as the password hash
   update, so a concurrent replay cannot succeed.

2. **`requestPasswordReset` mints and emails the token.** The handler at
   `:188-202` is replaced with a flow that:

   a. Looks up the account by the `email` field (already validated at
      `:193-198`).
   b. If the account exists, mints a token, stores it with `expires_at =
      now + 900`, and sends it via `emailProvider sendEmailTo:` to the
      account's email using the existing `XrpcIdentityPack.m:302` pattern.
   c. Returns 200 with an empty body **regardless of whether the account
      exists.** The endpoint must not leak which emails are registered — a
      timing-orthogonal response is the spec's guidance. This is recorded
      in the handler's comment.

   If no `emailProvider` is configured, the handler returns 503 with a
   "password reset unavailable" error rather than silently failing to send
   the email.

3. **`resetPassword` exchanges the opaque token for a DID internally.**
   The handler at `:204-249` is restructured:

   a. The `ATProtoValidator validateDID:token` check at `:225-229` is
      replaced with a lookup against `password_reset_tokens` keyed by the
      opaque `token` string.
   b. Expired tokens (`expires_at < now`) are rejected with 400
      `"InvalidToken"`.
   c. Used tokens (`used_at IS NOT NULL`) are rejected with 400
      `"InvalidToken"`.
   d. On successful password update, `used_at = now` is set in the same
      transaction as `updateAccount:`.
   e. The rest of the handler (PBKDF2 hash, `updateAccount:`,
      `logHostingEvent:`) stays as-is, but `logHostingEvent:` receives the
      DID from the token row, not from the `token` parameter.

4. **The old DID-as-token path is removed, not deprecated.** A `token`
   value that is a valid DID is now rejected (it will not match any row in
   `password_reset_tokens`). This is a deliberate contract change, not a
   compatibility break: the old path was a security hole, and keeping it
   alive — even behind a deprecation flag — would leave the bypass
   exploitable. The handler's deprecation comment records the migration
   path for clients that were sending DIDs.

5. **The token is not logged.** The `logHostingEvent:` call at `:248`
   previously logged the DID (which was the token). The new path logs the
   DID from the token row, not the token itself. The token is a credential;
   it must not appear in logs, audit entries, or error messages.

## Consequences

- **Contract change.** Any client that sends a DID as the `resetPassword`
  `token` parameter must migrate to the opaque token received via email.
  The old path is removed, not deprecated, because it was a security hole.
  The deprecation comment in the handler records the migration path.

- **New service-DB migration (V18).** The `password_reset_tokens` table
  is created by a V18 migration following the O2 phase C migration pattern
  in `PDSMigrationManager.m` with apply/rollback/re-apply tests. The
  migration is independently revertible (slice 4 is a single-commit
  revert). Reverting drops the table; outstanding tokens are lost, which
  is acceptable since they have a 15-minute TTL.

- **`requestPasswordReset` now requires an email provider.** If no
  `emailProvider` is configured, the handler returns 503. This inverts the
  current silent no-op: an operator who enables password reset without an
  email provider gets a clear failure rather than a false success. The
  `PDSRegistrationGateFactory` warning pattern (phase-23 slice 1b) is the
  precedent for fail-closed-on-misconfiguration.

- **No replay possible.** A captured reset token — from email
  interception, log scraping, or network sniffing — can be used at most
  once. The `used_at` column is set atomically with the password update, so
  a concurrent replay attempt either sees `used_at IS NOT NULL` (rejected)
  or fails the transaction (the row is locked).

- **Token enumeration is infeasible.** A 32-byte (256-bit) random token
  has a keyspace of 2^256. Even at 10^9 guesses/second, the expected time
  to find a valid unused token exceeds the 15-minute TTL by many orders of
  magnitude. No rate limit is needed on the `resetPassword` endpoint beyond
  the existing `RateLimiter` at the HTTP boundary.

- **No-leak guarantee on `requestPasswordReset`.** The handler returns 200
  with an empty body for both existing and nonexistent emails. An attacker
  cannot enumerate registered emails by observing response status or body.
  Timing-based enumeration is mitigated by the email-send step (the
  response time is dominated by the SMTP/API call, not the DB lookup), but
  a future hardening pass could add a constant-time delay for nonexistent
  accounts if the email provider's latency is distinguishable from the
  no-send path.

- **Rollback.** Revert the slice-4 commit to restore the DID-as-token path.
  The V18 migration's rollback drops the `password_reset_tokens` table. No
  data loss occurs beyond outstanding (unused) tokens, which are
  TTL-bounded to 15 minutes. Clients that had migrated to the opaque-token
  flow will receive `"InvalidToken"` errors until they re-request a reset.
