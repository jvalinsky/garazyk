# ADR 0022: Deterministic OTP Code Gated Behind `#if DEBUG`, Not a Runtime Env Var

**Status:** Accepted
**Date:** 2026-07-27

## Context

Workstream 01 S13 (phase-23 slice 3c) identified a backdoor in the phone
verification code generator. `ContactService.m:41-43` generates the OTP code
as follows:

```objc
if ([[NSProcessInfo processInfo].environment[@"PDS_ALLOW_HTTP"] boolValue]) {
    code = @"123456";
} else {
    code = [NSString stringWithFormat:@"%06d", arc4random_uniform(1000000)];
}
```

`PDS_ALLOW_HTTP` is read at **runtime** via `NSProcessInfo`. A production
binary deployed with `PDS_ALLOW_HTTP=1` in its environment accepts `123456` for
any phone number, bypassing the OTP verification entirely. The env var is
already used elsewhere for the HTTP-vs-HTTPS egress policy
(`ATProtoSafeHTTPClient.m:193,750`, `AppViewWriteProxy.m:152`), but at
`ContactService.m` it controls a security-critical code path.

The debugging convenience (deterministic code for test environments) is
correct — tests that verify the OTP flow need a predictable code. The
mechanism is wrong: a runtime env var on a production binary allows an
operator to accidentally (or an attacker to deliberately, via environment
injection) bypass phone verification.

Additionally, `ContactService.m:60` logs the generated code through
`GZLogRedactor maskToken:`, but `maskToken:` on a 6-digit string leaves most
digits visible. An attacker with log access can recover the code from logs.

Two alternatives were considered:

- **Keep the runtime check but gate it behind a separate, narrowly-scoped env
  var.** A new `PDS_DEBUG_OTP` env var would isolate the deterministic-code
  path from the HTTP egress policy. This was rejected because it doesn't
  solve the fundamental problem: a runtime env var on a production binary is
  still a runtime env var. The fix is to make the deterministic path
  unreachable in a release build, not to rename the env var.

- **Remove the deterministic code entirely and require tests to intercept the
  code from the DB.** Tests could read the generated code from the
  `phone_verifications` table instead of knowing it a priori. This was
  rejected because it complicates test setup — every OTP test would need a DB
  query to extract the code. The deterministic path is useful for testing;
  the problem is its runtime availability, not its existence.

## Decision

1. **The deterministic `123456` code is gated behind `#if DEBUG`, not a
   runtime env var.** The `PDS_ALLOW_HTTP` check at `ContactService.m:41-43`
   is replaced with:

   ```objc
   #if DEBUG
   if ([[NSProcessInfo processInfo].environment[@"PDS_ALLOW_HTTP"] boolValue]) {
       code = @"123456";
   } else
   #endif
   {
       code = [NSString stringWithFormat:@"%06d", arc4random_uniform(1000000)];
   }
   ```

   A **release build** (`-DNDEBUG` or no `-DDEBUG`) cannot reach the `123456`
   path regardless of environment variables. The `arc4random_uniform` path is
   always compiled and is the only path in release builds.

2. **`PDS_ALLOW_HTTP` is not removed — it still controls the HTTP-vs-HTTPS
   egress policy.** The env var is read at `ATProtoSafeHTTPClient.m:193,750`
   and `AppViewWriteProxy.m:152` for egress policy; removing it would break
   those paths. The change is scoped to `ContactService.m` only.

3. **The code is not logged, even masked.** `ContactService.m:60` currently
   logs the code through `GZLogRedactor maskToken:`. This is replaced with a
   categorical log ("verification code sent for <masked phone>") that does not
   include the code at all. The code is recoverable from the
   `phone_verifications` table for test inspection; it must never appear in
   logs.

4. **A test asserts the deterministic path is absent in a release build.**
   `ContactServiceTests.m` (or equivalent) includes a test that verifies a
   release build (or a build without `DEBUG`) never returns `123456` even
   when `PDS_ALLOW_HTTP=1` is set. This is a compile-time guard test — it
   verifies the `#if DEBUG` exclusion, not the runtime behavior.

## Consequences

- **Production binaries are immune to the `PDS_ALLOW_HTTP` phone-verification
  bypass.** A release build compiled without `DEBUG` cannot reach the
  deterministic code path. An operator who deploys with `PDS_ALLOW_HTTP=1`
  for egress testing does not accidentally open the phone verification
  backdoor.

- **Debug builds retain the deterministic code for testing.** The `#if DEBUG`
  block is compiled in debug builds, so test suites that rely on `123456`
  continue to work unchanged. The two-pronged guard (`#if DEBUG` + runtime
  env var) means the env var only has effect in debug builds.

- **Log safety improved.** The code is removed from logs entirely rather than
  masked. A masked 6-digit code leaks most digits (e.g., `****56`); removing
  it eliminates the leak. The code remains available in the
  `phone_verifications` table for authorized inspection.

- **No change to `PDS_ALLOW_HTTP` semantics for egress.** The env var still
  controls HTTP-vs-HTTPS for outbound connections. The change is scoped to
  `ContactService.m` only; no other file is affected.

- **Rollback.** Revert the slice-3c commit to restore the runtime-only check
  and the masked-code log line. Production binaries become vulnerable to the
  env-var backdoor again.
