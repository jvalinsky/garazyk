# Remediation Plan — Test Regressions & Issues (2026-07-13)

**Trigger:** Full test run after the `43e13ad42` (network refactor) and `444fc622f`
(admin UI rework) commits. Report: `reports_out/test_report.html`.
**Goal:** 0 ObjC failures (excluding intentionally gated), Deno suite exits 0, dashboard green.

> **Plan status:** v3 — revised after rebuilding `AllTests` from current HEAD.
>
> **Critical correction (invalidates v1/v2):** The original report was generated against a
> **stale binary** (`build/tests/AllTests` built **09:12**, but HEAD is **10:18**). That binary
> predates all 7 of this session's commits and contained **uncommitted debug logging**
> (`"CREATE TABLE rate_limits FAILED … disk I/O error"`, which is **not** in any committed source).
> Rebuilding from HEAD and re-running shows the real state is **3189 run / 3 failures / 28 gated
> skipped** — not 14. The v1/v2 WS1 diagnosis (11 RateLimiter failures from `SQLITE_IOERR`) was an
> artifact of that stale binary; **WS1 is resolved in HEAD.** `reports_out/test_report.html` is
> therefore stale and must be regenerated from `reports_out/objc_alltests_HEAD_2026-07-13.log`.

## Findings (root-caused from fresh HEAD build + source)

| # | Issue | Suite / test | Root cause | Commit |
|---|-------|--------------|-----------|--------|
| 1 | Rate limiter (was 11 failures) | `RateLimiterTests` | **RESOLVED in HEAD.** Fresh build: `RateLimiterTests` all pass; no `SQLITE_IOERR`. The I/O error came from the stale 09:12 binary's uncommitted debug code. Committed `initializeDatabase` swallows the error via `error:nil` (see note) but the table is created and writes persist. No action beyond cleanup logging. | `43e13ad42` |
| 2 | `com.atproto.admin.getRecord` → 404 (1 failure) | `LexiconResolveXrpcTests::testAllRegisteredMethodsCanBeResolved` | The handler **is** registered (`XrpcAdminPack.m:929` `registerComAtprotoAdminGetRecord:`). The test dispatches `com.atproto.lexicon.resolveLexicon?def=com.atproto.admin.getRecord` and gets **404** — i.e. the **lexicon doc for that NSID is not resolvable** by `XrpcLexiconResolver`, not a missing registration. 1 of 318 methods fails. | `43e13ad42` (exposed) |
| 3 | Lab shell HTML missing tokens (2 failures) | `UILabAuthTests::testLabShellHTMLContainsLabConfig` / `...SignOutButton` | **Stale tests, not missing features.** Commit `444fc622f` reworked `labShellHTML:` to inject config via `<meta name="lab-pds-url">` etc. (read client-side by `lab.js`, which builds its own frozen `LAB_CONFIG` object) and emits the sign-out button as `<button data-lab-action="sign-out">Sign Out</button>`. The served HTML therefore no longer contains the literal strings `"LAB_CONFIG"` (now a JS-only symbol) or `"signOutOAuth"` (a function defined in `lab.js`). Both assertions check obsolete literals. | `444fc622f` |
| 4 | Deno process exits 1 with 0 failures | `deno test -A packages/` | `Promise resolution is still pending but the event loop has already resolved` — leak sanitiser points at `packages/gruszka/firehose_test.ts` (`FirehoseClient.handleMessage` → `firehose.ts:267`): an unclosed firehose socket/timer/listener. | pre-existing |
| 5 | 28 gated classes skipped | `AllTests` | By design: `PDS_RUN_INTEGRATION_TESTS=1` / `PDS_RUN_SOCKET_TESTS=1`. Not failures; coverage gap. | n/a |

> **Logging cleanup (low priority):** Committed `RateLimiter.m` keeps three `GZ_LOG_HTTP_DEBUG` /
> `RateLimiter DEBUG` `NSLog` lines (`RateLimiter.m:252, 275, 287`) that log *expected* "Transaction
> rolled back" events. These are fine; just convert to `GZ_LOG_*` if desired. The v1/v2 note about an
> I/O error being "the only reason failures were visible" was wrong — that error was from the stale
> binary, not committed code.

---

## Workstream 1 — Rate limiter (CLOSED)

No code change required. `RateLimiterTests` is green on the HEAD build. Optional hygiene:
1. (Optional) In `RateLimiter.m`, stop passing `error:nil` in `initializeDatabase`'s
   `executeUpdate:… error:` calls and surface DB errors via `GZ_LOG_DB_ERROR` so any future
   open/DDL failure is visible in CI instead of silently returning success.
2. Convert the three debug `NSLog` to `GZ_LOG_*` per `better-code-objc`.

---

## Workstream 2 — XRPC `admin.getRecord` 404 (`garazyk-xrpc-implementation` + `better-code-objc`)

**Skills in use**
- `garazyk-xrpc-implementation`: registration workflow, coverage report, "registered exactly once".
- `garazyk-testing`: running the single resolver test class.

**Steps**
1. **Red.** `build/tests/AllTests -XCTest LexiconResolveXrpcTests`.
2. **Diagnose — do NOT blindly re-register.** The handler is already registered
   (`XrpcAdminPack.m:929`). Inspect `XrpcLexiconResolver` to see why `com.atproto.admin.getRecord`
   resolves to 404 *despite* registration (the test calls `com.atproto.lexicon.resolveLexicon`, so
   the resolver's doc lookup is the failure point, before dispatch):
   - Is the lexicon doc for `com.atproto.admin.getRecord` missing / unresolvable in the bundled
     lexicons the resolver loads?
   - Does the resolver 404 on a specific NSID pattern (e.g. `admin.*`) while `server.*`/`repo.*` work?
   - Does `resetRegisteredMethods` interact badly with the resolver's own cache?
3. **Fix the real cause** (lexicon doc availability / resolver path). Re-registering risks a
   **duplicate** registration, which `generate_xrpc_coverage_report.cjs --fail-on-duplicates` would flag.
4. **Green + coverage.** Re-run `LexiconResolveXrpcTests` → 0 red, then:
   `node scripts/docs/generate_xrpc_coverage_report.cjs --source-only --fail-on-duplicates` is clean.

---

## Workstream 3 — Admin UI lab shell stale tests (`garazyk-admin-ui` + `tdd` + `impeccable`)

**Skills in use**
- `garazyk-admin-ui`: server-rendered HTML, auth/session boundary, design-system conformance.
- `tdd`: the rework (`444fc622f`) changed the contract; the tests were not updated — update the
  tests to the new, deployed contract (meta tags + `data-lab-action="sign-out"` button), not the HTML.
- `impeccable`: if any re-injection is chosen, keep tokens/components on the existing design system.

**Steps**
1. **Red.** `build/tests/AllTests -XCTest UILabAuthTests` → 2 red.
2. **Confirm the feature is present** (already verified in source):
   - `labShellHTML:` emits `<meta name="lab-pds-url">` / `lab-client-id` / `lab-redirect-uri`;
     `lab.js` reads them and builds a frozen `LAB_CONFIG` (`lab.js:9-16`). So config is delivered.
   - `labShellHTML:` emits `<button data-lab-action="sign-out" …>Sign Out</button>`; `lab.js:529`
     wires `[data-lab-action="sign-out"]` → `signOutOAuth()`. So sign-out works.
3. **Fix the tests to the new contract** (preferred — the HTML is the deployed artifact):
   - `testLabShellHTMLContainsLabConfig`: assert presence of `lab-pds-url` meta (e.g.
     `containsString:@"lab-pds-url"`) instead of the literal `LAB_CONFIG`.
   - `testLabShellHTMLContainsSignOutButton`: assert `data-lab-action="sign-out"` (or `Sign Out`)
     instead of the literal `signOutOAuth`.
   - *Alternative (only if the team wants SSR `window.LAB_CONFIG` for SEO/legacy consumers):* re-inject
     `window.LAB_CONFIG = {...}` into `labShellHTML:` with real **client** config only (never a
     `client_secret`/bearer token). Do not do both — pick one contract.
4. **Conformance.** Run `scripts/test/check_ui_design_system.sh` if present.
5. **Green.** Re-run `UILabAuthTests` + `UIServerRuntimeTests` → 0 red.

---

## Workstream 4 — Deno pending-promise leak (`garazyk-testing` + `tdd`)

**Skills in use**
- `garazyk-testing`: Deno package testing guidance, `--trace-leaks`.
- `tdd`: isolate the leaking test, fix cleanup, keep green.

**Steps**
1. **Locate (narrow).** `deno test --trace-leaks -A packages/` — the leak sanitiser implicates
   `packages/gruszka/firehose_test.ts` (`FirehoseClient.handleMessage` → `firehose.ts:267`). Start there.
2. **Fix.** Close the leaked resource (firehose `WebSocket` / subscription timer / listener) in
   `tearDown` / on test completion; await its cleanup.
3. **Green.** `deno test -A packages/` exits **0** (not just 0 failures).

---

## Workstream 5 — Gated coverage as a CI gate (`garazyk-testing`)

Informational — not a failure, but closes the blind spot.
1. Before merge, run with network/services available:
   - `PDS_RUN_INTEGRATION_TESTS=1 build/tests/AllTests`
   - `PDS_RUN_SOCKET_TESTS=1 build/tests/AllTests`
2. Fold both into the quality-gate workflow (`.opencode/workflows/quality_gates*` / CI) so the 28
   gated classes are measured, not silently skipped.

---

## Execution order

1. **WS2** — the only real ObjC regression from `43e13ad42`. Diagnose the resolver, fix, green.
2. **WS3** — `444fc622f` stale tests; update the two assertions to the new contract, green.
3. **WS1 (optional hygiene)** — logging cleanup only; no behavior change.
4. **WS4** — independent Deno fix.
5. **WS5** — wire into CI.
6. **Full verification + re-report:**
   - `cmake --build build --target AllTests` (already done; re-run if sources change) →
     `build/tests/AllTests` → expect **0 ObjC failures**.
   - `deno test -A packages/` → exits 0.
   - `deno test -A scripts/scenario-dashboard` → green.
   - Regenerate `reports_out/test_report.html` from the fresh HEAD log (the existing one is stale).

## Definition of done
- ObjC `AllTests`: 0 failures (gated classes excluded by design, now run in CI).
- `deno test -A packages/` and dashboard: exit 0, 0 failures.
- `scripts/docs/generate_xrpc_coverage_report.cjs` passes; `check_ui_design_system.sh` passes.
- `UILabAuthTests` + `LexiconResolveXrpcTests` green on the HEAD build.
- `reports_out/test_report.html` regenerated from `objc_alltests_HEAD_2026-07-13.log` (green).
