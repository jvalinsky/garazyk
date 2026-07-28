---
phase: 25
title: Registration gate composition and CAPTCHA slice-1 follow-ups
status: pending
agent: worker
depends_on: [23]
---

# Phase 25: Registration gate composition and CAPTCHA slice-1 follow-ups

## Mission

Execute workstream 01 § S13 slice 6 plus the two slice-1 follow-ups found
reviewing the in-flight CAPTCHA implementation.

The headline item is a defect S13 named but did not schedule: the composite
registration gate uses **OR** semantics, so four independent `*Required` config
flags behave as a disjunction. Enabling CAPTCHA alongside invite codes means
CAPTCHA is not enforced for anyone holding an invite. Fixing the individual
no-op gates (slices 1-2) does not fix this — it is an independent defect.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S13,
  specifically the "Slice 1 follow-ups" and "Slice 6" subsections
  (authoritative; if this prompt disagrees, the workstream wins)
- `Garazyk/Sources/Registration/PDSRegistrationGate.m:63-90` — the composite
  loop, and `:156`, `:163`, `:190`, `:205` — the four flags that each append a
  gate
- `Garazyk/Sources/Registration/PDSCaptchaRegistrationGate.m` — the slice 1
  implementation being corrected

## Decisions already taken (do not re-litigate)

- **All configured gates must pass (AND).** Not OR-with-renamed-flags, and not
  a two-bucket required/alternative split.
- **The CAPTCHA gate stays synchronous.** Tighten the wait budget and cancel
  on timeout rather than converting the gate protocol to async.

## What is already correct — do not "fix" it

The slice 1 CAPTCHA implementation is sound in its core. Leave these alone:

- Fails closed on missing secret, timeout, network error, non-2xx,
  unparseable body, and `success: false`.
- Type-checks `captchaToken`, `success` (both `NSNumber` and `NSString`
  forms), and `error-codes`.
- Routes through `ATProtoSafeHTTPClient`, inheriting phase-18 address pinning.
- `percentEncode:` uses an explicit RFC 3986 unreserved allowlist. Do **not**
  "simplify" it to `URLQueryAllowedCharacterSet` — that set leaves `&` and `=`
  unescaped and would allow field injection into the form body.
- `remoteAddress` is not spoofable: `HttpRequest.m:125` honors
  `X-Forwarded-For` only when proxy trust is enabled *and* the peer is on a
  private or loopback range.
- The 503-vs-400 distinction and its propagation through
  `XrpcServerPack+Session.m`.

## Scope and order

One coherent slice per commit. The follow-ups land first, so the conjunction
takes effect only once every gate is correct.

1. **Tighten the siteverify wait budget.** Reduce `siteverifyTimeout` from 12s
   to ~5s and bring the request/options timeouts down with it, preserving the
   existing margin so the semaphore does not fire before the HTTP layer can
   report a real error. Cancel the in-flight task when the wait times out —
   today it runs to completion writing to `__block` variables nobody reads.
2. **Guard `percentEncode:`.** It returns nil for unpaired surrogates, and
   `[formBody appendFormat:@"%@=%@", key, …]` would then write the literal
   `(null)`, sending `secret=(null)` to the provider. Reject the request
   instead of emitting a malformed body.
3. **Composite becomes AND.** `PDSRegistrationGate.m:63-90` must admit the
   registration only when **every** configured gate passes. Requirements:
   - Zero gates still means open registration.
   - Report the **first** failing gate's error, not the last, so the client
     sees the most specific rejection.
   - Short-circuit on first failure — this is preferable, since it avoids a
     needless siteverify round-trip when an earlier gate already rejected.
   - A gate failing with `httpStatus: 503` must still surface as 503 at the
     handler, so an unreachable CAPTCHA provider stays distinguishable from a
     rejected registration.
   - Apply the same change to the `remoteAddress`-aware variant; both entry
     points must have identical semantics.

## Acceptance gate

Composition matrix — with two gates configured, assert every combination:

| invite | captcha | expected |
| ------ | ------- | -------- |
| pass   | pass    | admitted |
| pass   | fail    | **rejected** (this is the bug being fixed) |
| fail   | pass    | rejected |
| fail   | fail    | rejected, reporting the *first* gate's error |

Plus:

- Zero configured gates still admits (open registration unchanged).
- A CAPTCHA gate failing with `httpStatus: 503` surfaces as 503 even when
  another gate is configured and passing — proving the 503 path is no longer
  absorbed.
- Short-circuit is observable: when the first gate rejects, no siteverify HTTP
  request is issued.
- Slice 1 follow-ups: a siteverify that never responds fails the registration
  within the tightened budget, and the in-flight task is cancelled; a token
  containing an unpaired surrogate is rejected rather than producing
  `secret=(null)`.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure — CMake globs
`Garazyk/Tests`, so the reconfigure is what picks the file up. Verify the new
tests actually execute before claiming a pass. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Slices 1-2 are narrow single-commit reverts.

Slice 3 is the risky one: it tightens admission for every deployment running
more than one gate, so a user who previously registered with an invite code
alone now also needs to clear CAPTCHA or phone OTP. That is intended, but it
is a live signup-funnel change. It needs a release note naming the affected
configurations, and it must not ship in the same release as slice 1's
fail-closed change without deliberate sequencing — together, a misconfigured
CAPTCHA becomes a total registration outage rather than a degraded path.
Rollback is a one-line revert of the composite loop.

## On completion

Update S13 slice 6 and the slice 1 follow-ups with commit hashes, mark slice 1
complete, then set `status: complete` here. If the AND change is judged
operator-visible enough to warrant it, record the composition semantics as an
ADR alongside the existing 0018-0029 registration set.
