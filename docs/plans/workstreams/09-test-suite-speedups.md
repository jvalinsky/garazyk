---
title: Test Suite Speedups
status: active
last_verified: 2026-07-30
---

# Test Suite Speedups

Measured critique:
[`docs/plans/test-suite-speedups-2026-07-30.md`](../test-suite-speedups-2026-07-30.md)
(CI run `30512753291`; source agent `bc-019fb385-…` ended ERROR before any
implementation landed).

Goal: cut `AllTests` wall clock (baseline **~654s**, ~61% in XRPC auth-base
classes) and related CI / Deno cycle waste, without weakening production
crypto or introducing cross-test pollution.

## Status (2026-07-30)

- Critique and phased plan captured from the failed agent run.
- **No implementation items landed yet.** Start with Phase 1 (lexicon
  memoization + test-mode PBKDF2 + quieter logs + dead sleeps).

## Phase 1 — Highest impact / lowest risk

Target: **−300–400s** on `AllTests`.

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T1 | Lexicon load memoization in `ATProtoLexiconRegistry` (path+mtime+size; invalidate on `clearCache`) | open | Est. **~200–250s**. Files: `Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.{h,m}`; tests under `Garazyk/Tests/Lexicon/`. |
| T2 | Lower PBKDF2 iterations under `PDS_RUNNING_TESTS`; assert production still uses 600000 | open | Est. **~100–150s**. Centralize the constant across `PDSAccountService.m`, `ServiceDatabases.m`, `CryptoUtils.m`, `XrpcServerPack.m`, `UIAuthManager.m`, related. |
| T3 | Default quieter logs in tests (`GZ_LOG_LEVEL=warn` in `test_main.m` / CI) | open | Modest savings; near-zero risk. `GZ_LOG_LEVEL` already honored in `ATProtoServiceConfiguration`. |
| T4 | Remove/replace fixed 3s sleeps in `CoverageGapTests.m` and `XrpcProxyTests.m` | open | Est. **≥10s**. |

### Phase 1 verification

- Before/after: suite timing summary, count of `Loaded lexicons from` / 
  `PDSApplication initializing…` log lines.
- Success: lexicon load work collapses after first warm load; suite drops
  by several minutes; no new flakes; `--gated=run` still green; registration
  audit and module-boundary gates pass.
- Keep one unit test that production PBKDF2 iterations remain 600000 when
  `PDS_RUNNING_TESTS` is unset.

## Phase 2 — Fixture sharing

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T5 | Class-scoped (or process-scoped) `PDSApplication` / account fixtures for `AdminAuthXrpcTestBase` and `RepoAuthXrpcTestBase` | open | Land after Phase 1 so measurements isolate fixture vs lexicon wins. Higher risk of cross-test pollution. Files: `Garazyk/Tests/Network/AdminAuthXrpcTestBase.m`, `RepoAuthXrpcTestBase.m`. |

## Phase 3 — Parallelism

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T6 | `--shard=I/N` in `test_main.m`; PID-/shard-unique temp dirs; `ctest -j` entries | open | Fixed paths `garazyk-test-plc-keys` / `garazyk-test-data` are not PID-scoped today (keychain path already uses `getpid()`). |
| T7 | CI: decouple Linux `needs: macos-build-and-test`; remove bogus `september` build target; repair or remove `plc-integration-tests` ctest `-R` filter | open | Observed on run 30512753291: macOS failure skipped Linux entirely. `september` is not in `CMakeLists.txt` (`ci.yml:192`). |
| T8 | Real expectation fulfillment / run-loop polling in Linux XCTest shim | open | `Garazyk/Sources/Compat/XCTest/XCTest.m` currently sleeps the full timeout. 34 test files call `waitForExpectationsWithTimeout:`. |

## Phase 4 — Build & Deno hygiene

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T9 | Enable ccache in CI; slim duplicate ObjC compile/link deps for `AllTests` | open | Build minutes, not suite seconds, until sharding lands. |
| T10 | Hamownia: gate/replace 5s settle sleep in `packages/hamownia/atproto_network.ts`; avoid redundant Deno typecheck on repeated `deno test` after `deno task check` | open | Prefer health checks; document `--keep-running` for local loops. |

## Rollback

- Lexicon memoization: remove cache / always invalidate — correctness over
  speed; `clearCache` callers must remain valid.
- Test PBKDF2: revert to 600k when `PDS_RUNNING_TESTS` is set if any
  password-timing assumption breaks (unlikely; production path unchanged).
- Class fixtures: revert to per-method `setUp` on first cross-test flake
  that cannot be isolated with per-method reset.

## Owner boundary

Test-runner / CI / lexicon registry / password-KDF test seams. Does not
change production crypto defaults, XRPC contracts, or federation behavior
except where test-only env gates already exist (`PDS_RUNNING_TESTS`,
`GZ_LOG_LEVEL`).
