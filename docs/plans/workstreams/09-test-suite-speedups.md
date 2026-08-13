---
title: Test Suite Speedups
status: complete
last_verified: 2026-08-12
---

# Test Suite Speedups

Measured critique:
[`docs/plans/test-suite-speedups-2026-07-30.md`](../test-suite-speedups-2026-07-30.md)
(CI run `30512753291`; source agent `bc-019fb385-…` ended ERROR before any
implementation landed).

Goal: cut `AllTests` wall clock (baseline **~654s**, ~61% in XRPC auth-base
classes) and related CI / Deno cycle waste, without weakening production
crypto or introducing cross-test pollution.

## Status (2026-08-04)

Phase 1 (T1–T4) and Phase 3 (T6-T8) are complete. Phase 4's ccache (T9) and
Hamownia (T10) items are complete. T5 (class fixtures) and T9's link-slimming
half are both formally closed without implementation, each with a recorded
decision rationale below — re-open only if their blocking constraints change.

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
| T5 | Class-scoped (or process-scoped) `PDSApplication` / account fixtures for `AdminAuthXrpcTestBase` and `RepoAuthXrpcTestBase` | **closed, not pursued (2026-08-04)** | See rationale below. Re-open only if the Linux XCTest shim gains real class-level `+setUp`/`+tearDown`. |

### T5 decision (2026-08-04)

Re-verified before closing rather than leaving deferred indefinitely, per
`docs/plans/README.md`'s "decide, don't drift" rule.

- **Blocking constraint confirmed still true.** Re-read
  `Garazyk/Sources/Compat/XCTest/XCTest.h` (the GNUstep/Linux XCTest
  compatibility shim): it declares only instance-level `- (void)setUp;` /
  `- (void)tearDown;`. No class-level `+setUp`/`+tearDown` exists anywhere in
  the shim. A class-scoped fixture shared across test methods within one
  `AdminAuthXrpcTestBase`/`RepoAuthXrpcTestBase` subclass has no
  cross-platform hook to construct once and tear down once on Linux.
  28 test classes subclass one of the two bases today
  (`git grep -l ': AdminAuthXrpcTestBase\|: RepoAuthXrpcTestBase'
  Garazyk/Tests/`).
- **The cost this item targeted is already mostly gone.** The original
  654s baseline this workstream measured was ~61% concentrated in XRPC
  auth-base classes, driven specifically by uncached lexicon reloads
  (~200-250s) and production-strength PBKDF2 in tests (~100-150s) — both
  T1/T2 (Phase 1, complete) fixed independently of T5. Each `-setUp` still
  constructs a fresh SQLite-backed `PDSApplication` and mints real accounts,
  but that per-method cost is now small relative to what was cut.
- **Two ways to close the remaining gap, both rejected for now:**
  1. Add real class-level `+setUp`/`+tearDown` to the Linux XCTest shim
     first, then share fixtures on both platforms identically. This is
     legitimate but is its own separate, nontrivial piece of test-runner
     infrastructure work (changing lifecycle semantics for every suite that
     uses the shim), not a fixture-sharing change scoped to two base
     classes — out of scope for this item.
  2. Share fixtures on macOS only (where `+setUp`/`+tearDown` exist) and
     leave Linux on per-method setup. Rejected: this would make GNUstep and
     macOS runs exercise measurably different test behavior (mutable shared
     state on one platform, fresh state on the other), undermining
     confidence that a GNUstep pass means the same thing a macOS pass does
     — a correctness/maintainability cost the remaining marginal speedup
     doesn't justify.
- **Decision: closed, not pursued.** Re-open only if a future workstream
  adds real class-level lifecycle hooks to the Linux XCTest shim for reasons
  independent of this item, at which point sharing these two fixtures
  becomes low-risk on both platforms.

## Phase 3 — Parallelism

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T6 | `--shard=I/N` in `test_main.m`; PID-/shard-unique temp dirs; `ctest -j` entries | **complete** | `--shard=I/N` by class index; PID-scoped temp dirs; CMake registers `AllTestsShard{1..4}of4`; CI runs `ctest -j4 -E '^AllTests$'`. |
| T7 | CI: decouple Linux `needs:`; remove bogus `september` target; repair or remove `plc-integration-tests` | **complete** | Linux jobs no longer `needs: macos-build-and-test`. Build target is `kaszlak`. Removed the `plc-integration-tests` job (ctest `-R` matched no registered names; PLC already covered by macOS AllTests). |
| T8 | Real expectation fulfillment / run-loop polling in Linux XCTest shim | **complete** | Added `XCTestExpectation`, `XCTestCase` expectation APIs, and run-loop polling in `XCTWaiter` (no more full-timeout sleep). |

## Phase 4 — Build & Deno hygiene

| ID | Item | Status | Notes |
| --- | --- | --- | --- |
| T9 | Enable ccache in CI; slim duplicate ObjC compile/link deps for `AllTests` | **partial, link-slimming closed (2026-08-04)** | ccache launcher wired for macOS + Linux CI configure. See T9 decision below for why link-dep slimming is deliberately not implemented. |

### T9 link-slimming decision (2026-08-04)

Re-verified rather than left "partial" indefinitely, per `docs/plans/README.md`'s
"decide, don't drift" rule.

- **The duplication is real and reproducible.** A fresh `AllTests` link on
  macOS emits `ld: warning: ignoring duplicate libraries: ...
  'libATProtoCore.a', 'libATProtoMediaCore.a', 'libATProtoPLC.a',
  'libATProtoRuntime.a', 'libATProtoServices.a', 'libATProtoStorage.a',
  'libATProtoSync.a', 'libATProtoTransport.a', 'libATProtoXRPC.a',
  'secp256k1/lib/libsecp256k1.a'` — every module `AllTests` lists directly is
  also reachable transitively, because `ATProtoMikrus`/`ATProtoBeskid`/
  `ATProtoAppViewServer` each already `target_link_libraries(... PRIVATE
  ATProtoCore ATProtoStorage ATProtoServices ...)` the same set (CMake
  propagates a `STATIC` library's link-time dependencies to any executable
  that links it, even when declared `PRIVATE`), and `AllTests` links all
  three of those *plus* the eight lower-level modules directly.
- **Removing the direct entries carries real correctness risk, not just a
  performance question.** `AllTests` sets `LINK_FLAGS "-ObjC"` (macOS) /
  wraps everything in `-Wl,--whole-archive ... -Wl,--no-whole-archive`
  (GNUstep) specifically so unreferenced Objective-C categories still get
  force-linked (the existing comment names `PDSActorStore+Account` as the
  motivating example). Relying on transitive-only inclusion through
  `ATProtoMikrus`/`ATProtoBeskid`/`ATProtoAppViewServer` would depend on
  *their* link line still force-including every category `AllTests` needs —
  those three targets are ordinary `STATIC` libraries with no `-ObjC`/
  whole-archive treatment of their own, so a category defined in, say,
  `ATProtoCore` but referenced only via `+load`/string-based lookup could
  silently stop being linked into the final `AllTests` binary. That failure
  mode is exactly the kind of thing this repo's own test-registration audit
  exists to catch for *test classes*, but nothing catches it for production
  categories reached only via runtime dispatch.
- **The actual cost is linker noise and a small amount of duplicate
  archive-scanning, not measurable suite wall-clock.** Phase 1's lexicon and
  PBKDF2 fixes are what moved the needle on `AllTests` timing; this
  duplication was never separately measured as a wall-clock contributor
  because static-archive re-scanning is cheap relative to the compile/test
  work it doesn't affect.
- **Decision: closed, not pursued.** The safe version of this fix (auditing
  every category in the eight "duplicated" modules for `-ObjC`/whole-archive
  dependence before removing any direct link entry) is real work with a
  correctness-verification cost disproportionate to a link-time-noise
  cleanup. Re-open only alongside a broader link-line audit, not as a
  standalone slimming pass.
| T10 | Hamownia: gate/replace 5s settle sleep in `packages/hamownia/atproto_network.ts`; avoid redundant Deno typecheck on repeated `deno test` after `deno task check` | **complete** | Settle sleep is opt-in via `HAMOWNIA_SETTLE_MS` (default 0). Deno `--no-check` landed (2026-08-03): `deno.json`'s `check` task now also covers `packages/**/*_test.ts` / `*.test.ts` (previously only `packages/*/mod.ts` entry graphs — test files were never actually reachable from those and so were unchecked by `check` at all, only by `test`'s own implicit check). `packages/hamownia/cli/test_command.ts` now passes `--no-check` to both `deno test` invocations (`runUnitTests` and the `--filter` path), safe because `check` now covers the same files. Verified: `deno task check` (1320 files, ~1.5s warm), `deno task test` (1264 passed, 0 failed, ~32s vs ~37s before), `deno task test --filter` path, and `deno task lint` all pass clean. |

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
