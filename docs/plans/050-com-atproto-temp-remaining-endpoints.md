# `com.atproto.temp.*` parity follow-up and hardening

## Summary

All bundled `com.atproto.temp.*` lexicon endpoints are now registered/implemented in the XRPC registry.
This issue now tracks post-parity hardening and semantics decisions for production quality.

## Current status (as of 2026-02-12)

Implemented endpoints:

- `com.atproto.temp.addReservedHandle`
- `com.atproto.temp.checkHandleAvailability`
- `com.atproto.temp.checkSignupQueue`
- `com.atproto.temp.dereferenceScope`
- `com.atproto.temp.fetchLabels`
- `com.atproto.temp.requestPhoneVerification`
- `com.atproto.temp.revokeAccountCredentials` (already implemented before this batch)

## Remaining goals

- Harden semantics where current implementation is intentionally minimal.
- Ensure behavior is explicitly documented for operators and clients.
- Preserve `com.atproto.*` 100% in-scope lexicon parity while tightening edge-case handling.

## Non-goals

- Building a full phone/SMS verification provider integration in the first pass.
- Implementing a full signup queue system (we can return a trivial response unless we truly need a queue).

## Remaining decision points

1) `requestPhoneVerification` provider behavior:
- Current: explicit provider contract implemented with centralized config/env resolution.
- Remaining: real provider integration beyond `mock`.

## Current semantics

### `com.atproto.temp.addReservedHandle`
- Admin-only.
- Validates handle format and persists reservation in service DB (`reserved_handles`).
- Returns `{}`.

### `com.atproto.temp.checkHandleAvailability`
- Public query.
- Validates handle; optional email yields `InvalidEmail` if malformed.
- Checks local-account handles + persisted reserved handles.
- Returns either empty `result` (available) or `result.suggestions[]` (unavailable).

### `com.atproto.temp.checkSignupQueue`
- Returns `{ "activated": true }` (minimal queue-free behavior).

### `com.atproto.temp.dereferenceScope`
- Requires query `scope` prefixed by `ref:`.
- Invalid format returns `InvalidScopeReference`.
- Resolves via explicit static mapping:
  - `ref:com.atproto.transition:generic` -> `atproto transition:generic`
  - `ref:com.atproto.transition:email` -> `atproto transition:email`
  - `ref:com.atproto.transition:chat.bsky` -> `atproto transition:generic transition:chat.bsky`
- Unknown references return `InvalidScopeReference`.

### `com.atproto.temp.fetchLabels` (deprecated)
- Directly fetches label rows from DB with `since`/`limit` bounds.
- Returns `labels[]`.
- Sends deprecation contract headers on successful responses:
  - `Deprecation: true`
  - `Sunset: 2027-12-31T00:00:00Z`
  - `Link: </xrpc/com.atproto.label.queryLabels>; rel="successor-version", </xrpc/com.atproto.label.subscribeLabels>; rel="successor-version"`
  - `Warning: 299 ... deprecated ...`

### `com.atproto.temp.requestPhoneVerification`
- Validates phone-number shape.
- Uses provider abstraction (`PDSPhoneVerificationProviderFactory` + `PDSPhoneVerificationProvider`) so integrations can be plugged in without changing XRPC shape.
- Provider selection is centralized in `PDSConfiguration.phoneVerificationProvider` with precedence:
  - `PDS_PHONE_VERIFICATION_PROVIDER` env var (if set)
  - `phone_verification.provider` config file value
  - default `none`
- Factory supports runtime provider registration (`registerProviderClass:forName:` / `unregisterProviderWithName:`), so custom integrations (e.g. Twilio adapter) can be added without endpoint rewrites.
- Provider contract:
  - default / unset (`PDS_PHONE_VERIFICATION_PROVIDER` missing or `none`): `501 PhoneVerificationNotConfigured`
  - `PDS_PHONE_VERIFICATION_PROVIDER=mock`: returns `200 {}`
  - any other value: `501 UnsupportedPhoneVerificationProvider`

## Follow-up implementation plan

- Add concrete provider implementation(s) behind current `PDS_PHONE_VERIFICATION_PROVIDER` contract.
- Add provider-level tests once a non-mock provider exists.

## Subtasks (remaining)

- [x] Register all missing `com.atproto.temp.*` endpoints.
- [x] Implement baseline behavior + validation for each endpoint.
- [x] Add endpoint behavior tests and pass targeted/full test suites.
- [x] Persist reserved handles in DB (`reserved_handles`) and validate via tests.
- [x] Define explicit mapping source for `dereferenceScope` and validate unknown-ref rejection.
- [x] Decide and implement `fetchLabels` compatibility/deprecation contract (headers + successor links).
- [x] Finalize provider/not-configured contract for `requestPhoneVerification` and add tests.
- [x] Centralize phone verification provider selection in `PDSConfiguration` (`env > config > default`).
- [x] Add custom provider registration hooks + unit tests for registration lifecycle.
- [ ] Implement real phone verification provider beyond `mock` (deferred until core PDS hardening milestones complete).

## Definition of done

- [x] `com.atproto.temp.*` lexicon parity achieved for in-scope coverage.
- [x] Endpoint tests added and passing.
- [x] Follow-up hardening decisions documented and implemented (persistence/provider/mapping/fetchLabels deprecation).
