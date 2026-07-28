# ADR 0020: Phone OTP Gate Fails Closed When No Provider Is Configured

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S13 (phase-23 slice 2a) identified a fail-open defect in the
phone OTP registration gate. `PDSPhoneOTPRegistrationGate.m:25` stores the
configured `id<PDSPhoneVerificationProvider>` as `_provider`. When no phone
verification provider is configured — either because the operator omitted the
config or the factory at `PDSRegistrationGate.m:164-185` failed to construct
one — `_provider` is `nil`.

The gate's verification check does not guard against a nil provider:

- `verifyCode:` is called at `:66` with `[_provider verifyCode:code ...]`
- The nil-provider fallback at the gate level accepts any non-empty code

This means a misconfigured phone gate silently accepts any string as a valid
OTP code, defeating the registration gate composite at
`PDSRegistrationGate.m:73-86` (OR logic).

The factory at `PDSRegistrationGate.m:174` already logs a warning when
provider creation fails, but the gate itself does not turn that warning into a
hard rejection. An operator who sees "no phone verification provider configured"
in the logs may not realize that the gate is accepting all codes.

Two alternatives were considered:

- **Keep the nil-provider path but gate it behind `phoneVerificationRequired`.**
  The factory could refuse to create a `PDSPhoneOTPRegistrationGate` when no
  provider is configured, using `PDSOpenRegistrationGate` as a fallback. This
  was rejected because it conflates provider availability with gate
  enablement — the operator's intent is expressed through the configuration
  key, and the gate should fail closed rather than silently switching to a
  different gate.

- **Return a distinct error code for nil-provider to let the composite handle
  it.** The composite at `:73-86` OR-s gates: a single `YES` wins. A distinct
  error that the composite treats as "abort" would require changing the
  composite contract. This was rejected because the fix is simpler at the gate
  level — the gate knows it can't verify, so it should reject.

## Decision

1. **The nil-provider fallback is removed.** The gate at
   `PDSPhoneOTPRegistrationGate.m` must check `_provider` before calling
   `verifyCode:`. When `_provider` is `nil`, the gate returns `NO` with a
   `PDSRegistrationGateErrorPhoneVerificationRequired` error whose message
   names the misconfiguration: "phone verification required but no provider
   configured." The existing nil-provider accept path at the gate level is
   deleted entirely.

2. **The factory's existing warning is paired with the gate's hard rejection.**
   `PDSRegistrationGate.m:174` already logs a warning on provider creation
   failure. The gate now turns that failure into a hard rejection rather than
   a silent accept. The operator sees both a startup warning and a
   registration error, making the misconfiguration unambiguous.

3. **Providers that reject a nil sessionID get a gate-level check, not a
   generic provider error.** Vonage (`PDSVonagePhoneVerificationProvider.m`),
   Plivo (`PDSPlivoPhoneVerificationProvider.m`), and Telegram Gateway
   (`PDSTelegramGatewayPhoneVerificationProvider.m`) all reject a nil
   `sessionID` — but the gate currently passes
   `body[@"verificationSessionID"]` through without checking. The provider
   returns a generic "verification failed" error rather than naming the
   missing field. A new optional protocol method `requiresSessionID` (default
   `NO` for Twilio, which manages sessions server-side) lets the gate reject
   early with a specific error: "verification session ID required."

4. **The fail-closed behavior applies regardless of what other gates are in
   the composite.** The composite at `PDSRegistrationGate.m:73-86` OR-s gates
   together, so a single gate returning `YES` wins. The phone gate returning
   `NO` (with the appropriate error) leaves other gates free to accept or
   reject independently. The composite does not short-circuit on the phone
   gate's rejection.

## Consequences

- **Operators who enabled phone verification without a provider now get
  registration failures instead of silent acceptance.** Any deployment that
  set a `phoneVerificationProvider` config key to an invalid or missing value
  and relied on the nil-provider accept path must correct the configuration.
  The gate now fails closed with both a startup warning and a per-request
  error.

- **Vonage, Plivo, and Telegram Gateway now require `sessionID` in the
  request body.** The gate rejects early with a specific error rather than
  passing a nil sessionID to the provider and getting a generic failure. This
  changes the error shape for these providers: clients that omit
  `verificationSessionID` get a "session ID required" error from the gate
  rather than a "verification failed" error from the provider.

- **Twilio is unaffected.** Twilio Verify manages verification sessions
  server-side and does not require a client-supplied `sessionID`. The
  `requiresSessionID` protocol method defaults to `NO`, so the gate does not
  enforce a sessionID check for Twilio.

- **Rollback.** Revert the slice-2a commit to restore the nil-provider accept
  path. Operators who relied on the nil-provider behavior (intentionally or
  not) will return to silent acceptance. The `requiresSessionID` protocol
  method is optional and new, so reverting it does not break existing
  provider implementations.
