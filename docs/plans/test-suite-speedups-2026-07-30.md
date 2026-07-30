---
title: Test Suite Speedups — Measured Critique
date: 2026-07-30
status: open
source_agent: bc-019fb385-ce67-7ea2-8109-0d51374e7038
source_ci_run: 30512753291
workstream: workstreams/09-test-suite-speedups.md
---

# Test Suite Speedups — Measured Critique (2026-07-30)

Measured analysis of Garazyk’s Objective-C `AllTests` wall clock and related
CI / Deno cycle time. Originally produced by cloud agent
[Test performance optimization](https://cursor.com/agents/bc-019fb385-ce67-7ea2-8109-0d51374e7038)
(`bc-019fb385-…`); the agent ended ERROR mid-implementation with no commits.
This document captures the critique and plan so the work is durable.

Execution tracking lives in
[workstream 09](workstreams/09-test-suite-speedups.md).

## Measured baseline

Source: CI run `30512753291` (2026-07-30), macOS `AllTests` / `ctest`.

| Metric | Value | Source |
| --- | --- | --- |
| `AllTests` wall clock | **653.80 s** (~10m54s) | CI `ctest` |
| macOS job: Build | ~2m06s | CI step timing |
| macOS job: Run Tests | ~10m57s (~75% of job) | CI step timing |
| Test suites / methods | 431 suites; **4888** `test*` methods | Runner / count |
| XRPC auth-base class time | **~397 s (~61%)** of suite | Class timing summary |
| `PDSApplication` inits | **622** | CI log: `PDSApplication initializing…` |
| Lexicon directory loads | **1297** | CI log: `Loaded lexicons from` |
| Lexicon JSON files per tree | **662** | `Garazyk/Resources/lexicons` |
| Implied lexicon file parse ops | **~858,000** (1297 × 662) | Derived |
| Migration “Applying N migrations” | **7,382** | CI log |
| Migration-related log lines | **77,924** / **97,612** total INFO/WARN/DEBUG | CI log |
| PBKDF2 cost (600k iters) | **~0.12 s/hash** (Linux OpenSSL path) | Local measurement |
| PBKDF2 ops in default suite | **~1250–1350** (AdminAuth 432×2 + RepoAuth 120×3 + scatter) | Test-base accounting |
| PBKDF2 contribution | **~100–165 s (~15–23%)** of suite | Derived |

### Slowest classes (CI timing summary)

| Time | Tests | Class |
| --- | ---: | --- |
| 43.630s | 42 | `XrpcChatBskyGroupTests` |
| 38.583s | 38 | `XrpcChatBskyConvoTests` |
| 38.499s | 66 | `XrpcToolsOzoneTests` |
| 31.299s | 31 | `OAuth2HandlerTests` |
| 30.690s | 37 | `AdminAuthXrpcTests` |
| 29.202s | 34 | `RepoAuthServerTests` |
| 23.524s | 42 | `XrpcAppBskyGraphTests` |
| 21.909s | 40 | `XrpcAppBskyUnspeccedTests` |
| 20.809s | 25 | `RepoAuthRepoTests` |
| 19.959s | 19 | `RepoAuthTempTests` |

`AdminAuthXrpcTestBase` subclasses: **432** methods (e.g. Ozone 66, Chat
Group 42, Graph 42, …). `RepoAuthXrpcTestBase` subclasses: **120** methods.
Combined **552** methods each constructing a full app in `setUp`.

---

## Finding 1 — Lexicon registry reloads dominate app init (~200–250s)

**Evidence**

- Every `PDSApplication` init calls `loadLexicons` →
  `ATProtoLexiconRegistry loadLexiconsFromDirectory:` with **no memoization**
  (`Garazyk/Sources/App/PDSApplication.m` ~226–244;
  `Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.m` ~37–89).
- Each load recursively walks the tree and `NSData` +
  `NSJSONSerialization`-parses every `*.json`, then `registerSchema:`
  (async barrier work).
- CI: **622** app inits, **1297** successful “Loaded lexicons from …” lines,
  **662** lexicon files → on the order of **850k+** read/parse/register
  operations per run.
- After subtracting PBKDF2 (~100–150s) from the ~397s spent in XRPC auth
  bases, the residual (~250s) aligns with repeated lexicon + migration/init
  work.

**Fix**

Memoize in `ATProtoLexiconRegistry`:

- Prefer **per-file** fingerprint `(path, mtime, size)` so re-reads/parses
  are skipped when unchanged; directory enumeration can remain (cheap) or be
  optionally short-circuited by dir mtime.
- Invalidate memoization in `clearCache` (tests call it:
  `ATProtoLexiconRegistryTests`, `GermRecordTests`, `PDSRecordServiceTests`,
  etc.).
- Fresh registry instances in unit tests stay correct with per-instance
  caches.

**Estimated savings: ~200–250s** suite wall clock. Low risk; single choke
point.

---

## Finding 2 — Production PBKDF2 (600k) in every account create/login (~100–150s)

**Evidence**

- Hardcoded `const uint32_t iterations = 600000` in e.g.
  `PDSAccountService.m:946–964`, `ServiceDatabases.m:32`, `CryptoUtils.m`,
  `XrpcServerPack.m`, `UIAuthManager.m`, etc.
- Linux uses OpenSSL `PKCS5_PBKDF2_HMAC` via
  `Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonKeyDerivation.h`.
- `AdminAuthXrpcTestBase.setUp` creates **two** accounts per test
  (`AdminAuthXrpcTestBase.m:45–63`); RepoAuth paths typically create + login
  (**~3** hashes/test).
- Precedent: `PDS_RUNNING_TESTS` already gates behavior in ~11 sites
  (`PDSApplication.m`, `HandleResolver.m`, `ATProtoServiceConfiguration.m`,
  …).

**Fix**

- Single helper / env override (e.g. low iteration count when
  `PDS_RUNNING_TESTS` is set) used by password KDF call sites.
- Keep one dedicated test asserting production iteration count remains
  600000 outside test mode.

**Estimated savings: ~100–150s**. Medium risk to “tests exercise real crypto
cost”—mitigate with the production-count unit test.

---

## Finding 3 — Per-method full app fixtures in XRPC auth bases (~397s class time)

**Evidence**

- `AdminAuthXrpcTestBase` / `RepoAuthXrpcTestBase` rebuild `PDSApplication`,
  run migrations, register XRPC methods, and create accounts **per test
  method**, not per class.
- That drives the majority of the 622 inits and the 397s class-time bucket.

**Fix**

- Move expensive setup to class-scoped fixtures (`setUp` once / shared
  app+accounts) with careful reset of mutable state between methods; or
  share a warmed lexicon registry + thinner per-test DB.
- Complements Finding 1 (memoization helps even before fixture sharing).

**Estimated savings: large fraction of remaining app-init time after lexicon
memoization** (order of tens to low hundreds of seconds depending on how
much state must still be rebuilt). Higher risk (cross-test
pollution)—land after Phase 1.

---

## Finding 4 — Log volume from migrations

**Evidence**

- **97,612** leveled log lines in one CI AllTests capture; **77,924**
  mention `PDSMigrationManager`; **7,382** “Applying N migrations”.
- Default log level is INFO; `GZ_LOG_LEVEL` is already honored in
  `ATProtoServiceConfiguration` (~979–988).

**Fix**

- In `test_main.m` (or CI), default `GZ_LOG_LEVEL=warn` (or error) unless
  overridden.
- Optional: reduce chatty migration INFO under tests.

**Estimated savings: smaller but real** (I/O + runner overhead); near-zero
risk.

---

## Finding 5 — Dead sleeps and broken expectation waits

**Evidence**

- `CoverageGapTests.m:71` — `[NSThread sleepForTimeInterval:3.0]` in tearDown
  path; class takes **10.536s** for 3 tests.
- `XrpcProxyTests.m:286` — `sleepForTimeInterval:3.0`; class **7.977s** for
  8 tests.
- Linux XCTest shim (`Garazyk/Sources/Compat/XCTest/XCTest.m:278–286`)
  **always sleeps the full timeout**; no fulfillment. **34** test files call
  `waitForExpectationsWithTimeout:` (timeouts often 5–10s, some 30–60s on
  gated/media tests).

**Fix**

- Remove or replace fixed 3s sleeps with condition/poll.
- Implement real `XCTestExpectation` + run-loop polling in the Linux shim
  (or guard Linux tests that rely on waits).

**Estimated savings: ≥10s from the two sleeps alone**; more on Linux once
waits stop burning full timeouts.

---

## Finding 6 — No test sharding; CI serializes Linux behind macOS

**Evidence**

- Single-process `AllTests`; no `--shard=I/N`; CI invokes `ctest` without
  `-j` on the suite (`.github/workflows/ci.yml`).
- `linux-gnustep-build-and-test` and `linux-docker-build` /
  `plc-integration-tests` use `needs: macos-build-and-test` — macOS failure
  skips Linux entirely (observed on run 30512753291).
- Fixed temp paths in `test_main.m` (`garazyk-test-plc-keys`,
  `garazyk-test-data`) are **not PID-scoped**; keychain DB path already uses
  `getpid()`.

**Fix**

- Add `--shard=I/N` to `test_main.m`; register multiple `ctest` entries; run
  `ctest -j`.
- Make temp dirs PID-/shard-unique like the keychain path.
- Drop or relax `needs:` so Linux jobs are independent of macOS green.

**Estimated savings: wall-clock ÷ shard count** on multi-core runners (e.g.
2–4× on test phase), plus CI graph latency.

---

## Finding 7 — CI / build waste

**Evidence**

- Linux build: `cmake --build … --target september AllTests` but
  **`september` is not defined** in `CMakeLists.txt` (`ci.yml:192`).
- `plc-integration-tests`: full macOS rebuild then
  `ctest -R "PLC|DID|Identity"` — filter does not match registered class
  names usefully (build-for-nothing risk).
- No `ccache` / `CMAKE_*_COMPILER_LAUNCHER` in CI; Objective-C sources can
  be compiled into multiple targets; service binaries pulled into test link
  graph unnecessarily.

**Fix**

- Remove bogus `september` target; fix or delete the PLC integration filter
  job; enable ccache; slim `AllTests` link deps.

**Estimated savings: build minutes + avoid wasted 15m jobs**; does not
shrink the 654s AllTests number much until sharding lands.

---

## Finding 8 — Deno / scenario cycle

**Evidence**

- Unconditional **5s** settle sleep:
  `packages/hamownia/atproto_network.ts:346–347`
  (`Waiting for services to settle...`).
- Docker compose often rebuilds / volume churn per scenario setup
  (laweta/hamownia); scenarios can use `--no-setup` / `--keep-running` but
  default path is heavy.
- Deno package checks vs tests: keep typecheck in `deno task check`; ensure
  repeated `deno test` invocations use `--no-check` where appropriate to
  avoid duplicate work.

**Estimated savings: 5s+ per network bring-up; larger when avoiding full
compose rebuilds.**

---

## Phased implementation plan

### Phase 1 — Highest impact / lowest risk (target: −300–400s on AllTests)

1. **Lexicon load memoization** in `ATProtoLexiconRegistry` (file fingerprint
   + `clearCache` invalidation).
   - Files: `Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.m`, `.h`; tests
     under `Garazyk/Tests/Lexicon/`.
   - Save: **~200–250s**.
2. **Test-mode PBKDF2 iteration reduction** via `PDS_RUNNING_TESTS`
   (centralize constant; keep production assertion test).
   - Files: `PDSAccountService.m`, `ServiceDatabases.m`, `CryptoUtils.m`,
     `XrpcServerPack.m`, `UIAuthManager.m`, related.
   - Save: **~100–150s**.
3. **Default quieter logs in tests** (`GZ_LOG_LEVEL=warn` in `test_main.m` /
   CI).
   - Save: modest.
4. **Remove fixed 3s sleeps** in `CoverageGapTests.m` and
   `XrpcProxyTests.m`.
   - Save: **≥10s**.

### Phase 2 — Fixture sharing (target: large cut of remaining XRPC-base time)

5. Class-scoped (or process-scoped) `PDSApplication` / account fixtures for
   `AdminAuthXrpcTestBase` and `RepoAuthXrpcTestBase`.
   - Files: `Garazyk/Tests/Network/AdminAuthXrpcTestBase.m`,
     `RepoAuthXrpcTestBase.m`.
   - Verify no cross-test leakage; prefer after Phase 1 so measurements
     isolate fixture vs lexicon wins.

### Phase 3 — Parallelism

6. `--shard=I/N` in `Garazyk/Tests/test_main.m`; PID-unique temp dirs;
   CMake/`ctest -j` registration.
7. CI: parallelize Linux vs macOS (`needs:`); fix `september` target; repair
   or remove `plc-integration-tests` filter.
8. Implement real expectation waiting in
   `Garazyk/Sources/Compat/XCTest/XCTest.m` (Linux).

### Phase 4 — Build & Deno hygiene

9. ccache in CI; reduce duplicate ObjC compilation / unnecessary binary deps
   for `AllTests`.
10. Hamownia: replace or gate the 5s settle sleep; prefer health checks;
    document `--keep-running` for local loops; Deno `--no-check` on repeated
    test runs after `deno task check`.

### Verification

- Compare CI (or local) AllTests timing summary and lexicon-load / app-init
  log counts before vs after each phase.
- Phase 1 success criteria: “Loaded lexicons from” and raw JSON parse work
  collapse after first warm load; suite duration drops by several minutes
  without new flakes.
- Re-run gated subset with `--gated=run` as CI does.
- Keep registration audit / module-boundary gates green.

---

## Todos / checklist

- [x] **lexicon-memoize** — Memoize `ATProtoLexiconRegistry` directory/file
  loads by path+mtime/size; invalidate on `clearCache`
- [x] **pbkdf2-test-iters** — Lower PBKDF2 iterations under
  `PDS_RUNNING_TESTS`; assert production still uses 600000
- [x] **test-log-level** — Default `GZ_LOG_LEVEL=warn` (or similar) in test
  runner / CI
- [x] **remove-dead-sleeps** — Remove tearDown sleep in `CoverageGapTests`
  (`XrpcProxyTests` 3s is intentional timeout fixture — left alone)
- [ ] **xrpc-class-fixtures** — Share `PDSApplication`/accounts across
  methods in AdminAuth/RepoAuth bases
- [ ] **test-sharding** — Add `--shard=I/N`, `ctest -j` entries (PID-scoped
  temp dirs landed)
- [x] **ci-parallel-fixups** — Decouple Linux `needs:`; remove `september`;
  remove broken PLC ctest `-R` job
- [x] **xctest-shim-waits** — Real expectation fulfillment / polling on
  Linux XCTest shim
- [ ] **build-ccache-deps** — Enable ccache; slim duplicate compile/link for
  tests
- [x] **deno-scenario-waits** — Gate settle sleep behind `HAMOWNIA_SETTLE_MS`
  (default 0); Deno `--no-check` on test reruns still open
