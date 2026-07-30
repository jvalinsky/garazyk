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

Phase 1 (T1–T4) landed in this branch, plus T7/T8/T10 and the PID-scoped
temp-dir half of T6. T5 (class fixtures), full sharding, and ccache remain.

## Phase 1 — Highest impact / lowest risk

Target: **−300–400s** on `AllTests`.

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T1 | Lexicon load memoization in `ATProtoLexiconRegistry` (path+mtime; invalidate on `clearCache`) | **complete** | Directory fingerprint short-circuits re-walk/re-parse after the first successful load. Tests in `ATProtoLexiconRegistryTests`. |
| T2 | Lower PBKDF2 iterations under `PDS_RUNNING_TESTS`; assert production still uses 600000 | **complete** | `ATProtoPBKDF2IterationCount()` in `CryptoUtils` (prod 600000 / test 1000). Wired through account, app-password, CLI, XrpcServerPack, UIAuthManager, and `deriveKeyFromPassword:`. `CryptoTests` asserts both modes. |
| T3 | Default quieter logs in tests (`GZ_LOG_LEVEL=warn` in `test_main.m`) | **complete** | Set only when unset so operators can still override. |
| T4 | Remove/replace fixed 3s sleeps in `CoverageGapTests` and `XrpcProxyTests` | **partial** | Removed tearDown sleep in `CoverageGapTests` (port release handled by `startServerWithRetry`). `XrpcProxyTests.m:286` sleep is intentional upstream delay for the 504 timeout test — left alone. |

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
| T5 | Class-scoped (or process-scoped) `PDSApplication` / account fixtures for `AdminAuthXrpcTestBase` and `RepoAuthXrpcTestBase` | deferred | Phase 1 already removes most of the XRPC-base cost (lexicon + PBKDF2). Class fixtures remain higher risk of cross-test pollution; Linux XCTest shim has no `+setUp`/`+tearDown`. |

## Phase 3 — Parallelism

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T6 | `--shard=I/N` in `test_main.m`; PID-/shard-unique temp dirs; `ctest -j` entries | **complete** | `--shard=I/N` by class index; PID-scoped temp dirs; CMake registers `AllTestsShard{1..4}of4`; CI runs `ctest -j4 -E '^AllTests$'`. |
| T7 | CI: decouple Linux `needs:`; remove bogus `september` target; repair or remove `plc-integration-tests` | **complete** | Linux jobs no longer `needs: macos-build-and-test`. Build target is `kaszlak`. Removed the `plc-integration-tests` job (ctest `-R` matched no registered names; PLC already covered by macOS AllTests). |
| T8 | Real expectation fulfillment / run-loop polling in Linux XCTest shim | **complete** | Added `XCTestExpectation`, `XCTestCase` expectation APIs, and run-loop polling in `XCTWaiter` (no more full-timeout sleep). |

## Phase 4 — Build & Deno hygiene

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T9 | Enable ccache in CI; slim duplicate ObjC compile/link deps for `AllTests` | **partial** | ccache launcher wired for macOS + Linux CI configure. Slimming AllTests link deps still open. |
| T10 | Hamownia: gate/replace 5s settle sleep in `packages/hamownia/atproto_network.ts`; avoid redundant Deno typecheck on repeated `deno test` after `deno task check` | **partial** | Settle sleep is now opt-in via `HAMOWNIA_SETTLE_MS` (default 0; per-service readiness already waited). Deno `--no-check` hygiene still open. |

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
