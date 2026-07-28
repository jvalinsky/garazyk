# ADR 0021: Server-Side OTP Attempt Counting for Vonage, Plivo, and Telegram Gateway

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S13 (phase-23 slice 2c) identified an unbounded OTP brute-force
surface in the phone verification providers. Of the four supported providers:

- **Twilio Verify** (`PDSTwilioPhoneVerificationProvider.m:194`) enforces
  attempt limits server-side — the Verify API rejects after N failed attempts,
  and the PDS only sees a boolean result.

- **Vonage** (`PDSVonagePhoneVerificationProvider.m:190`),
  **Plivo** (`PDSPlivoPhoneVerificationProvider.m:172`), and
  **Telegram Gateway** (`PDSTelegramGatewayPhoneVerificationProvider.m:183`)
  do **not** enforce attempt limits. They accept an unlimited number of
  `verifyCode:` calls per phone number, each one a paid API request.

Without a server-side counter, an attacker can brute-force a 6-digit OTP
against any of these three providers at the rate the PDS allows (currently
bounded only by the global `RateLimiter` at the HTTP boundary (`checkRateLimitForIP:`
at `RateLimiter.m:189-224`), which is per-IP, not per-phone). A 6-digit code
has 10^6 combinations; at 10 attempts/second, the expected time to guess a code
is ~14 hours, but with a 5-minute TTL (hardcoded `300` seconds at
`ContactService.m:50`), the practical brute-force window is
limited. However, the provider charges per verification attempt regardless of
outcome, so an attacker can run up costs even if they never guess correctly.

Per-IP rate limiting (`RateLimiter.m:189-224`) is already in place but is
insufficient: an attacker rotating IPs (botnet, proxies) bypasses the per-IP
limit and hits the same phone number from many addresses.

Two alternatives were considered:

- **Delegate attempt counting to the provider layer.** Each provider
  implementation could maintain its own attempt counter via a
  provider-specific API (e.g., store counters in the provider's own
  database). This was rejected because it duplicates the counting logic
  across three providers and requires each provider to have its own
  persistence mechanism.

- **Use a per-IP attempt counter at the gate level.** The gate could count
  attempts per client IP rather than per phone number. This was rejected
  because it doesn't protect against IP rotation — the same reason per-IP
  rate limiting at the HTTP boundary is insufficient. The OTP-specific limit
  must be per-phone, not per-IP.

## Decision

1. **Attempt counting is server-side and per-phone, not per-IP.** A new
   `phone_verification_attempts` table is added to the service DB (migration
   V16 — the slice 2c migration, independently revertible from slices 1, 3,
   and 4). The table is keyed by `(phone_number, code_hash)` with columns:
   `attempt_count` (INTEGER NOT NULL DEFAULT 0),
   `first_attempt_at` (INTEGER NOT NULL), and
   `last_attempt_at` (INTEGER NOT NULL). The code hash is stored rather than
   the plaintext code to avoid storing verification codes in the service DB.

2. **The maximum attempt count is 5 within the code TTL window (5 minutes).**
   The TTL matches the 5-minute hardcoded value at `ContactService.m:50`. On the 6th
   failed attempt within the window, the gate rejects with
   `PDSRegistrationGateErrorPhoneVerificationRequired` and a message
   indicating the limit has been reached. The counter resets on successful
   verification (the row is deleted). If the code changes (new
   `startPhoneVerification` call), the old counter row is stale and a new one
   is created for the new code — the old row is cleaned up by a periodic
   sweep or on the next attempt for that phone.

3. **The counter is checked before and after the provider call.** The gate
   increments the counter before calling `verifyCode:` to prevent concurrent
   attempts from all passing the pre-check. If the provider returns success,
   the counter row is deleted. If the provider returns failure, the counter
   stays incremented. If the provider call fails (network error), the
   increment is kept — the attempt counted toward the limit even though the
   provider didn't process it, to prevent an attacker from forcing network
   errors to bypass the counter.

4. **Twilio is excluded from the counter because it enforces limits
   server-side.** The attempt counter is only applied to providers whose
   `requiresServerSideAttemptCounting` (new optional protocol method, default
   `NO`) returns `YES`. Twilio returns `NO`; Vonage, Plivo, and Telegram
   Gateway return `YES`. The gate checks this flag before accessing the
   counter table.

5. **The migration follows the O2 phase C pattern.** The migration (numbered
   V16 in the phase-23 prompt — slice 2c ships before slices 3b and 4a, so
   it claims the next available version; if slice 4a is implemented first, the
   version number is renumbered at implementation time)
   creates the `phone_verification_attempts` table and indices in
   `PDSMigrationManager.m` with apply/rollback/re-apply tests. The migration
   is a service-DB migration, not an actor-store migration — attempt counters
   are shared across the PDS, not per-user.

## Consequences

- **Brute-force surface reduced from unbounded to 5 attempts per code per
  phone.** An attacker rotating IPs can no longer brute-force a phone number
  beyond 5 attempts within the 5-minute TTL window. After 5 failures, they
  must wait for the code to expire and a new code to be issued (which resets
  the counter). A new code is only issued on a fresh `startPhoneVerification`
  call, which itself may be rate-limited.

- **Cost protection for Vonage, Plivo, and Telegram Gateway.** Each failed
  attempt is a paid API call. Capping at 5 attempts per code per phone limits
  the cost of a brute-force campaign against these providers.

- **New service-DB table with periodic cleanup needed.** The
  `phone_verification_attempts` table accumulates rows for expired codes. A
  periodic cleanup sweep (`DELETE FROM phone_verification_attempts WHERE
  last_attempt_at < ?`) must be added as a follow-up or the table will grow
  unboundedly. The TTL is 5 minutes, so rows older than ~10 minutes are dead.

- **Provider failures count toward the limit.** If Vonage/Plivo/Telegram
  Gateway is unreachable, the attempt is counted and the gate returns the
  provider's error. An attacker cannot force network errors to bypass the
  counter. The counter row persists until the code expires or a successful
  verification occurs.

- **Rollback.** Revert the slice-2c commit. The V16 migration's rollback
  drops the `phone_verification_attempts` table. Providers return to
  unlimited attempts within the global RateLimiter bounds. No data loss
  beyond attempt-counter rows (which are ephemeral by design).
