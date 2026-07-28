# ADR 0030: Registration Gate Composite Uses AND Semantics

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S13 slice 6 (phase-25) found that `PDSCompositeRegistrationGate`
(`PDSRegistrationGate.m:63-90`) used OR semantics: it returned `YES` on the
first configured gate that passed. `PDSRegistrationGateFactory` adds one gate
per independent `*Required` flag — `inviteCodeRequired`,
`phoneVerificationRequired`, `captchaRequired`, `oauthOnlyRegistration` — so an
operator who enables both `inviteCodeRequired` and `captchaRequired` intends
both checks to hold, but OR semantics let a valid invite code bypass CAPTCHA
entirely.

This is a distinct defect from the no-op gates found elsewhere in S13 (ADR
0019, ADR 0020): fixing every individual gate's fail-closed behavior does not
fix the composite. It also silently negated ADR 0019's own fail-closed and 503
work — a CAPTCHA rejection, including "siteverify unreachable," was only
reachable when CAPTCHA was the *sole* configured gate. With any second gate
present, the composite's first-pass-wins loop meant a passing invite gate
returned before the CAPTCHA gate was ever invoked, so its 503 was silently
absorbed.

Two structures were considered:

- **Two-bucket required/alternative split** (e.g. invite code as an
  "alternative" to CAPTCHA+phone-OTP "required" gates). Rejected: none of the
  four flags are named or documented as alternatives to each other, and
  introducing a bucketing scheme now would be a larger, less legible surface
  change than fixing the loop's semantics directly.
- **Rename the flags to reflect OR** (e.g. `*Sufficient` instead of
  `*Required`). Rejected: `*Required` is the correct name for what operators
  want — every one of these being required is the reason they configured more
  than one gate.

## Decision

1. **`PDSCompositeRegistrationGate` requires every configured gate to pass.**
   The loop at `PDSRegistrationGate.m:63-90` no longer returns on the first
   passing gate. It short-circuits on the first *failing* gate instead,
   returning that gate's error. Zero configured gates still means open
   registration (unchanged).
2. **The first failing gate's error is reported**, not the last, so the
   client sees the most specific rejection. Short-circuiting on first failure
   already guarantees this — the loop never advances past a failure to
   evaluate (and potentially overwrite the error with) a later gate.
3. **Short-circuiting also means gates after the first failure are never
   invoked**, avoiding a needless siteverify round-trip when an earlier,
   cheaper gate (e.g. invite code lookup) already rejected the request.
4. **A gate that fails with `httpStatus: 503` in its error `userInfo`
   propagates unchanged** through the composite and the existing
   `XrpcServerPack+Session.m:83-90` 503-mapping logic. Because AND semantics
   mean every gate must still be evaluated when an earlier gate passes, the
   CAPTCHA gate's 503 (siteverify unreachable) is reachable again even when
   another gate (e.g. invite code) is configured and passing — the absorption
   bug described above is fixed as a side effect of the semantics change.
5. **The same change applies to both entry points** —
   `validateRegistrationRequest:configuration:error:` and the
   `remoteAddress:`-aware variant — since the two-parameter method simply
   delegates to the three-parameter one with `remoteAddress:nil`.

Alongside this, two remaining defects from the ADR 0019 implementation
(flagged in review, not part of the original slice) were fixed in the same
change:

- **CAPTCHA siteverify wait budget tightened from 12s to 5s**, with the
  underlying request/options timeouts reduced from 10s to 3s to preserve the
  same margin. The in-flight siteverify task is now tracked with a
  lock-guarded `cancelled` flag: if the gate's semaphore wait times out, a
  late-arriving completion becomes a no-op instead of writing to `__block`
  state nobody reads.
- **`percentEncode:` nil guard.**
  `stringByAddingPercentEncodingWithAllowedCharacters:` returns `nil` for
  strings containing unpaired surrogates. `PDSCaptchaRegistrationGate.m`'s
  form-body loop now checks each encoded field and rejects the request with
  `PDSRegistrationGateErrorInvalidCaptcha` rather than emitting a literal
  `secret=(null)` (or similarly malformed field) to the CAPTCHA provider.

## Consequences

- **This is a live signup-funnel change for any deployment running more than
  one gate.** A user who previously registered with an invite code alone now
  also needs to clear CAPTCHA or phone OTP if those flags are also enabled.
  This is the intended behavior — the whole point of enabling multiple gates
  — but operators running more than one `*Required` flag today should be
  notified via release notes before this ships, since their effective
  registration policy is about to tighten from "any one of N" to "all N."
- **A misconfigured or unreachable CAPTCHA provider is now a harder failure
  mode when combined with another gate.** Previously, an unreachable
  siteverify endpoint combined with a passing invite-code gate degraded
  silently to "invite code sufficient." Now it surfaces as a 503 on every
  registration attempt that reaches the CAPTCHA gate. This is intentional
  (ADR 0019's fail-closed design), but it means a CAPTCHA outage can become a
  total registration outage for gate combinations that previously masked it.
  Operators should monitor siteverify latency/error rates (already
  recommended in ADR 0019) with this in mind.
- **Rollback.** Slice 6 is a one-line revert of the composite loop
  (return `YES` on first pass instead of on completing the full loop). The two
  follow-up fixes (wait budget, `percentEncode:` guard) are independent,
  narrow reverts.
- **Process note.** This change and the two ADR 0019 follow-up fixes landed
  in commit `0239f88c`, which — due to a concurrent Claude Code session
  running phase-24 (Ozone) work in the same worktree and staging broadly —
  also bundled in unrelated S14/docs bookkeeping under a commit message that
  does not mention this change. The composite AND acceptance-matrix tests
  (`PDSCaptchaRegistrationGateTests.m`) landed separately at `1d44cde7`. See
  the workstream S13 section and phase-25 prompt for the accurate record.
- **Test suite.** `PDSRegistrationGateTests.m` covers AND-fails-if-any-fails,
  AND-passes-only-if-all-pass, first-failing-gate error reporting,
  short-circuit (a gate after the first failure is never invoked), 503
  propagation from a later gate when an earlier gate passes, and the
  invite+phone-OTP two-gate combination (alone vs. both).
  `PDSCaptchaRegistrationGateTests.m` adds a dedicated invite+CAPTCHA
  acceptance matrix (all four pass/fail combinations), the same short-circuit
  and 503-not-absorbed checks against the real gates, the `percentEncode:`
  nil-guard case (a lone UTF-16 surrogate), and the tightened timeout value
  plus a late-completion-after-timeout regression test.
