# (Optional) Tests: reduce/contain ActorStore signing-key generation warnings

## Summary

Test runs currently emit repeated warnings:

> `[ActorStore] Warning: Failed to generate signing key for ...: ... failed to generate CDSA key`

This appears to be caused by key generation attempts in account creation paths during tests, and it adds noise (even if tests pass).

## Background / current state (as of 2026-02-12)

- Keygen happens in `ATProtoPDS/Sources/Database/ActorStore/PDSActorStore+Account.m` (see account insert flow).
- On non-GNUstep builds, key generation is attempted when `self.useKeychainSigningKey` is enabled.
- In constrained environments, this can fail and log warnings.

## Goals

- Keep production behavior secure.
- Make test logs clean and deterministic.

## Non-goals

- Disabling signing keys in production.
- Hiding real failures (we only want to avoid noisy warnings in test contexts where keygen is intentionally skipped).

## Proposed approach options

Option A (test-only):
- In tests, initialize controllers/stores with `useKeychainSigningKey = NO` (or equivalent) to avoid keygen.
- Or add a test flag/env var that disables keygen.

Option B (robust keygen):
- Fix key generation to be compatible with the environment and avoid sporadic failure.

## Suggested investigation steps

- [ ] Identify which tests trigger the warnings (capture stderr/stdout and grep for `[ActorStore] Warning:`).
- [ ] Confirm whether failures happen only on:
  - test runs without Keychain access, or
  - Linux/GNUstep builds, or
  - both.
- [ ] Decide whether signing keys are actually required for the tests that create accounts.

## Subtasks (recommended breakdown)

- [ ] Add a single test configuration seam to disable signing-key generation during tests:
  - prefer wiring through existing configuration objects rather than sprinkling per-test toggles
  - ensure GNUstep and non-GNUstep paths behave consistently
- [ ] Update test harness setup to disable keygen where appropriate.
- [ ] Ensure any tests that *do* require signing keys explicitly enable them and assert behavior.
- [ ] Downgrade the log level for expected/ignored keygen failures in tests (optional):
  - avoid `NSLog` warnings if we deliberately skipped keygen

## Definition of done

- [ ] Tests no longer spam keygen warnings in normal runs.
- [ ] Production defaults remain secure.
- [ ] Any new toggles are documented.
