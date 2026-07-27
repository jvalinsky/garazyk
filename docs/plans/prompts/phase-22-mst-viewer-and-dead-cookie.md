---
phase: 22
title: MST viewer gating and dead admin credential surface
status: pending
agent: worker
depends_on: []
---

# Phase 22: MST viewer gating and dead admin credential surface

## Mission

Close the two findings in workstream 01 § S12: a debug MST viewer shipped on
by default with no config key, no env var, and no authentication, and a dead
`admin_token=` cookie credential carrier on the admin auth path that nothing
in the codebase ever issues.

Both are small and independently shippable. Neither touches schema versioning,
migration files, or the auth cluster wired in phase 14 — they are config
plumbing and dead-code removal, not architecture changes.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S12
  (authoritative; if this prompt disagrees, the workstream wins)
- `Garazyk/Sources/Network/ATProtoHttpServerBuilder.m` — `:45` (the hardcoded
  `YES` default), `:176-178` (the route pack registration gate)
- `Garazyk/Sources/App/MSTViewer/MSTViewerHandler.m` — `handleRequest:` at
  `:55` (no auth check), `handleAccountsRequest` at `:162` (unauthenticated
  DB query), `handleExportRequest` at `:232` (unbounded MST load + serialize)
- `Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.m` in full (46 lines;
  registers `/mst-viewer` and `/api/mst` handlers with no auth middleware)
- `Garazyk/Sources/Admin/PDSAdminAuth.m` — `:299-317` (X-Admin-Token header
  + admin_token cookie parsing), `:151` (`PDS_DISABLE_X_ADMIN_TOKEN_HEADER`),
  `authenticateHeaders:error:` (the JWT verification path both carriers feed
  into)
- `Garazyk/Sources/App/ATProtoServiceConfiguration.m` — `:517-535` (the
  existing `debug` config section, the pattern to follow for the new key)
- `Garazyk/Sources/App/PDSApplication.m` — `:354-363` (the production
  fail-closed issuer check, the pattern for production-default-off), `:526-532`
  (the X-Admin-Token startup warning)
- `Garazyk/Tests/App/MSTViewerHandlerTests.m` in full (38 lines; current tests
  assume no auth)
- `Garazyk/Tests/Admin/PDSAdminAuthTests.m` — `:289,299,315` (the three
  cookie-path tests that will need removal)

## Decisions already taken (do not re-litigate)

- **MST viewer defaults off in production.** The default is NO when
  `PDS_ENV=production`, YES otherwise. This matches the issuer fail-closed
  pattern, not a new opinion. Operators who need the viewer in production set
  `PDS_ENABLE_MST_VIEWER=1`.
- **Auth is required when the viewer is enabled, including static assets.** The
  page is useless without the API, and serving it without auth only reveals the
  tool exists. The check goes at the top of `handleRequest:`, before any
  dispatch — not per-endpoint.
- **The `admin_token=` cookie is removed, not gated.** It has no issuer, no
  disable mechanism, and no CSRF protection. Removing the parsing block is
  safer than adding a config gate.
- **The `X-Admin-Token` header is defaulted to disabled in production, not
  removed.** It already has `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` and a startup
  warning. Defaulting it off in production closes the gap without breaking
  operators who explicitly enable it for automation.

## Scope and order

One coherent slice per commit.

1. **MST viewer gating and auth.**

   a. Add a `mstViewerEnabled` property to `ATProtoServiceConfiguration.h`
      (nonatomic, assign, BOOL). Default it to YES in `init`. In `applyConfig:`,
      read `debug.mst_viewer_enabled` from the `debug` config section (follow
      the exact pattern of `debug.verbose_logging` at `:519-522`) and
      `PDS_ENABLE_MST_VIEWER` via `boolFromEnv:default:`. **Compute the default
      from production status** rather than applying a post-hoc override: set
      `BOOL mstDefault = isProduction ? NO : YES` (using the same `PDS_ENV`
      detection as `PDSApplication.m:354-356`) and pass it as the default to
      `boolFromEnv:@"PDS_ENABLE_MST_VIEWER" default:mstDefault`. This way
      `PDS_ENABLE_MST_VIEWER=1` in production overrides the NO default,
      `PDS_ENABLE_MST_VIEWER=0` in dev overrides the YES default, and unset
      falls through to the production-appropriate default — all in one line,
      no `envVarExists:` check needed.

   b. In `ATProtoHttpServerBuilder.m initWithConfiguration:` (after `:52`),
      set `_enableMSTViewer = configuration.mstViewerEnabled` instead of
      relying on the `init` default of YES. The bare `init` path (no
      configuration) keeps the YES default for backward compat with tests that
      construct the builder directly.

   c. In `MSTViewerHandler.m handleRequest:` (at `:55`, before the path
      dispatch), add:
      ```objc
      if (![[PDSAdminAuth sharedAuth] authenticateHeaders:request.headers
                                                    error:nil]) {
          response.statusCode = HttpStatusUnauthorized;
          [response setJsonBody:@{
              @"error": @"Unauthorized",
              @"message": @"MST viewer requires admin authentication"
          }];
          return;
      }
      ```
      Import `Admin/PDSAdminAuth.h` at the top of the file.

   d. Update `MSTViewerHandlerTests.m`: the existing `testHandleRequestIndexReturns200HtmlContent`
      test will now fail (no auth → 401). The handler tests need the full
      PDSAdminAuth + PDSController + jwtMinter chain to mint a valid admin JWT.
      Do not build this from scratch — follow the setUp pattern in
      `Garazyk/Tests/Network/AdminAuthXrpcTestBase.m`, which already wires
      `PDSApplication`, sets `PDS_ADMIN_PASSWORD`, assigns
      `[PDSAdminAuth sharedAuth].controller`, calls `authenticateWithPassword:`
      to populate `self.adminJwt`, and provides `sendGetRequestWithPath:headers:`.
      Either subclass `AdminAuthXrpcTestBase` or replicate its setUp/tearDown.
      Update the existing test to pass the JWT in the `Authorization: Bearer`
      header. Add a new test `testHandleRequestRejectsUnauthenticated` asserting
      401 with no header.

   e. Update `ATProtoHttpServerBuilderTests.m:272` — the test
      `XCTAssertTrue(builder.enableMSTViewer)` assumes the bare-init default of
      YES. This still holds (the bare `init` path keeps YES). But add a test
      asserting that `initWithConfiguration:` under `PDS_ENV=production` sets
      `enableMSTViewer = NO`.

2. **Dead cookie removal and X-Admin-Token production default.**

   a. In `PDSAdminAuth.m authenticateHeaders:error:`, remove the cookie-parsing
      block at `:306-317` (the `if (token.length == 0)` block that scans
      `Cookie:` for `admin_token=`). Do not remove the `Authorization: Bearer`
      block above it or the `X-Admin-Token` block — only the cookie block.

   b. In `PDSAdminAuth.m`, update `PDSAdminAuthIsXAdminTokenHeaderDisabled`
      (`:149-151`) to also return YES when `PDS_ENV=production` and
      `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` is not explicitly set. The logic:
      first check `env[@"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"] != nil` — if the
      env var is explicitly set, honor it via `PDSAdminAuthEnvBool` (so `=0`
      means "enable", `=1` means "disable"). If it is not set, return YES
      (disabled) when `[[env[@"PDS_ENV"] lowercaseString]
      isEqualToString:@"production"]`, NO otherwise. The existence check is
      essential: without it, `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0` is
      indistinguishable from unset, and the production default would override
      an explicit enable.

   c. In `PDSApplication.m:526-532`, update the startup warning to reflect the
      new default: warn only when `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0` is
      explicitly set in production (the header is now on by operator choice,
      not by default).

   d. In `PDSAdminAuthTests.m`, remove the three cookie-path tests at `:289`,
      `:299`, and `:315`. Add `testAdminTokenCookieNoLongerAccepted` asserting
      that a request with `Cookie: admin_token=<valid-jwt>` returns NO from
      `authenticateHeaders:`. Add
      `testXAdminTokenDisabledByDefaultInProduction` asserting that under
      `PDS_ENV=production` with no `PDS_DISABLE_X_ADMIN_TOKEN_HEADER`, the
      header is rejected. Add
      `testXAdminTokenExplicitlyEnabledInProduction` asserting that under
      `PDS_ENV=production` with `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0`, the
      header is accepted.

## Acceptance gate

Per-slice tests are the gate:

**Slice 1:**
- Viewer off by default in production: `ATProtoServiceConfiguration` under
  `PDS_ENV=production` asserts `mstViewerEnabled == NO`.
- Viewer on by default otherwise: same config without `PDS_ENV` asserts
  `mstViewerEnabled == YES`.
- Config key disables: `debug.mst_viewer_enabled: false` in config sets
  `mstViewerEnabled == NO`.
- Env var disables: `PDS_ENABLE_MST_VIEWER=0` sets `mstViewerEnabled == NO`.
- Env var enables in production: `PDS_ENABLE_MST_VIEWER=1` under
  `PDS_ENV=production` sets `mstViewerEnabled == YES`.
- Viewer requires auth: `/api/mst/accounts` with no `Authorization` header
  returns 401. With a valid admin JWT, returns 200.
- Static assets require auth: `/mst-viewer` with no auth returns 401.

**Slice 2:**
- Cookie removed: `Cookie: admin_token=<valid-jwt>` returns NO from
  `authenticateHeaders:`. `Authorization: Bearer <same-jwt>` returns YES.
- X-Admin-Token off by default in production: under `PDS_ENV=production` with
  no env var set, `X-Admin-Token: <valid-jwt>` returns NO.
- X-Admin-Token explicitly enabled: under `PDS_ENV=production` with
  `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0`, `X-Admin-Token: <valid-jwt>` returns
  YES.
- No regression: `Authorization: Bearer <valid-jwt>` works in all modes.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently run
zero tests. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Each slice is a single-commit revert. Slice 1 changes the MST viewer default
(off in production) and adds auth — if an operator relied on the unauthenticated
viewer in production, they must set `PDS_ENABLE_MST_VIEWER=1` and provide admin
credentials. Slice 2 removes the cookie carrier — if an automation client
relied on `admin_token=` cookie, it must migrate to `Authorization: Bearer`.
The X-Admin-Token header remains available via `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0`.

## On completion

Update S12 status in workstream 01 with commit hashes, then set
`status: complete` here.
