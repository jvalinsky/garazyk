# Refactor Deep Dives

Date: 2026-05-13

Deciduous:
- Deep-dive action node: 1579
- Attached document: 65
- Parent scoring action: 1578
- Outcome nodes: 1583, 1584

## 1. XRPC Registry And Lexicon Contract Map

Current shape:
- XRPC is registered through both dispatcher method packs and direct HTTP route packs.
- `AppViewXRpcRoutePack.m` registers many `/xrpc/...` paths directly on `HttpServer`.
- Dispatcher packs such as `XrpcAdminMethods.m`, `XrpcRepoMethods.m`, and `XrpcAppBsky*Pack.m` register NSIDs via `registerMethod:`.
- `UIBackendClient.m` hard-codes many `/xrpc/...` paths for admin/backend calls.

Why it is hard to change:
- XRPC behavior depends on NSID, HTTP method, auth requirement, input schema, params, output shape, and error names.
- Direct routes and dispatcher registrations can drift independently.
- Reports currently exist, but report generation itself has defaults that write to tracked `reports/`.

Proposed refactor:
- Introduce a generated or declarative XRPC method catalog used by route packs, coverage tools, and tests.
- Catalog fields: NSID, surface (`pds`, `appview`, `relay`, `chat`, `ozone`, `video`, `germ`), HTTP method, auth mode, lexicon path, handler owner, and error-shape policy.
- Keep existing handlers; first wire the catalog only to tests and reports.
- Add a “contract audit” test that confirms registered methods match catalog and lexicon type.

Required tests:
- Characterization test that enumerates current registered methods and compares expected HTTP method for a small seeded catalog.
- Lexicon-backed tests for query/procedure method type.
- Error response shape test for representative 400, 401, 404, and 500 paths.
- Proxying tests for `atproto-proxy` DID plus service fragment and JWT `aud` expectations.

Staging and rollback:
- Stage 1: catalog as read-only test/report input.
- Stage 2: route packs consume catalog for registration metadata while handlers remain unchanged.
- Stage 3: optionally generate route-registration glue.
- Rollback by keeping existing manual registrations untouched until catalog tests pass.

## 2. Shared HTTP Client Dependency Injection

Current shape:
- `ATProtoSafeHTTPClient sharedClient` is called from many boundaries: account service, relay service, AppView write proxy/hooks, OAuth2Handler, chat auth, DID/PLC, federation, lexicon resolver, CLI, and provider HTTP clients.
- Some newer clients already accept an injected client or have a property fallback to shared client.

Why it is hard to change:
- The shared client centralizes SSRF, timeout, redirect, and platform behavior.
- Swapping all call sites at once risks auth, proxy, CLI, and service regressions.

Proposed refactor:
- Define a small protocol, for example `ATProtoHTTPClienting`, matching the safe async/sync methods actually used.
- Add initializer or property injection to high-value boundary services first: `OAuth2Handler`, DID/PLC resolver, federation client, XRPC proxy interceptor, AppView write proxy/hooks.
- Keep `[ATProtoSafeHTTPClient sharedClient]` as the default adapter.
- Move tests from singleton swizzling to explicit fake clients.

Required tests:
- Existing HTTP client tests unchanged.
- New fake-client tests for OAuth metadata fetch, DID/PLC resolver, federation client, proxy interceptor, and AppView write proxy.
- Timeout/error propagation characterization.
- GNUstep timeout fallback characterization remains attached to concrete client.

Staging and rollback:
- Add protocol and adapter with no behavior change.
- Convert one class per commit.
- Rollback individual conversions by restoring default shared-client path.

## 3. `objc-jupyter-wasm` Interpreter Dispatch Split

Current shape:
- `objc_interp_messages.c` includes message parsing, selector construction, Foundation dispatch, JSON serialization helpers, placeholder handling, and method invocation glue.
- Runtime gap report identifies clear P0/P1 behavior targets with passing probe infrastructure.

Why it is hard to change:
- Interpreter state is global and marker-string based.
- Dispatch bugs may be class-pointer, marker, parser, or bridge issues.
- Many features are intentionally partial or stubbed for WASM constraints.

Proposed refactor:
- Split message parsing from Foundation dispatch:
  - `objc_interp_message_parse.c`: parse target/selector/arguments.
  - `objc_interp_foundation_dispatch.c`: NSString/NSArray/NSDictionary/NSNumber/etc.
  - `objc_interp_runtime_dispatch.c`: class hierarchy, `super`, `isKindOfClass:`, protocol conformance.
  - `objc_interp_json.c`: JSON helpers.
- Add a feature-status table that maps gap report rows to source modules and tests.
- Fix P0s only after mechanical extraction has characterization coverage.

Required tests:
- Preserve `test-runtime-v2`, `kernel-smoke`, and `test-runtime-gap-probes`.
- Add focused tests for `[super ...]`, `isKindOfClass:`, loop `break`/`continue`, `NSMutableString`, and immutable copy markers.
- Add source-level smoke test for module split if build supports it.

Staging and rollback:
- First extraction should be mechanical and behavior-preserving.
- Keep old symbols as forwarding functions until tests pass.
- Rollback by reverting extraction without changing feature semantics.

## 4. Admin UI Runtime Split

Current shape:
- `UIServerRuntime.m` owns route registration, authorization guard usage, static asset serving, HTML escaping, CSP, CSRF, partial rendering, actions, lab, Ozone, PLC, relay, chat, video, and AppView rendering.
- `UIBackendClient.m` separately hard-codes backend routes and request execution.

Why it is hard to change:
- The file is auth-sensitive and XSS/CSRF-sensitive.
- Tests likely target rendered fragments and action routing.
- Large HTML strings make small edits risky.

Proposed refactor:
- Introduce route packs by domain: overview/accounts, relay/plc, repo/blobs, chat/video, ozone, lab, appview.
- Introduce renderer helpers that only take sanitized view models.
- Keep `UIServerRuntime` as composition root.
- Move `UIEscaped`, CSP, and CSRF helpers into small tested utilities.

Required tests:
- Snapshot-like tests for representative partials before and after split.
- CSRF/auth guard tests for all POST actions.
- Escaping tests for user-controlled DID/handle/error content.
- Route registration tests that every old route still dispatches.

Staging and rollback:
- Extract one domain route pack at a time.
- Keep original method signatures until all call sites move.
- Rollback by re-registering the domain routes in `UIServerRuntime`.

## 5. Legacy `PDSDatabase` Facade

Current shape:
- `PDSDatabase.m` includes connection lifecycle, PRAGMAs, legacy migrations, statement cache, schema creation, transaction helpers, account access, record access, and compatibility behavior.
- Modern ActorStore/service DB patterns exist with readers/transactors, migration manager, connection pools, and schema manager.

Why it is hard to change:
- Legacy tests and production flows may still depend on `PDSDatabase`.
- Statement cache and transaction behavior are cross-cutting.
- Migration paths are high blast radius.

Proposed refactor:
- Freeze `PDSDatabase` behavior with characterization tests.
- Extract internal collaborators behind private protocols:
  - connection lifecycle and PRAGMAs,
  - statement cache,
  - account repository,
  - record repository,
  - legacy migration adapter.
- Prefer moving consumers to modern repositories only after tests prove parity.

Required tests:
- Account CRUD parity tests.
- Record pagination/listing parity tests.
- Migration fresh vs upgraded DB tests.
- Statement cache finalize/reopen tests.
- Transaction rollback and nested transaction tests.

Staging and rollback:
- Private extraction first, no public API change.
- Migrate consumers only after facade is stable.
- Rollback by keeping facade methods intact and removing internal collaborator use.

## 6. `skylab` XRPC Bridge

Current shape:
- `skylab-bridge.js` routes services with `METHOD_ROUTES` and `APPVIEW_READ_METHODS`.
- Query/procedure detection checks `method.startsWith('get')`, `list`, `search`, or `describe`, which does not match namespaced NSIDs.
- Auth tokens are kept in memory, which is acceptable for a dev/demo lab, but should be documented as intentional.

Why it is hard to change:
- Multiple panels depend on bridge response shape and events.
- Demo behavior may mask contract drift if calls are proxied or permissive.

Proposed refactor:
- Replace name-prefix query detection with a method metadata table or generated lexicon-derived map.
- Keep service routing table separate from HTTP method/type table.
- Add one small DOM/render helper to replace repeated raw `innerHTML` patterns for common empty/error/pre states.

Required tests:
- Unit tests for `routeMethod`, method type selection, URL generation, auth header selection, and error event emission.
- Browser smoke tests for login, timeline, chat, admin search, and firehose panel.

Staging and rollback:
- Add table while preserving public `xrpc()` signature.
- Fall back to existing POST behavior only behind a compatibility option during testing.

## 7. Script And Docs Tooling Ownership

Current shape:
- `scripts/docs/repo_docs.py` is a substantial docs registry/link/orphan workflow.
- `scripts/docs/generate_xrpc_coverage_report.cjs` writes default outputs into `reports/`.
- Existing plan identifies duplicate/stale scripts, placeholder validators, and ownership moves.

Why it is hard to change:
- Scripts may be invoked by humans, CI, agents, docs, or old plans.
- Some tools mutate reports by default, which is useful but risky in audit flows.

Proposed refactor:
- Define canonical tool owners:
  - active docs validators under `docs/scripts` or one documented docs-tooling directory,
  - migration utilities under `tooling/docs-migration`,
  - scenario runners under `scripts/scenarios`,
  - ops scripts under `scripts/ops`,
  - report generators with explicit `--out-*` or `--dry-run`.
- Add deprecation wrappers only where external references still exist.

Required tests:
- ShellCheck or equivalent for shell scripts.
- `--help` smoke tests for active scripts.
- Dry-run report generation into `/tmp`.
- Docs link validation in non-mutating mode.

Staging and rollback:
- First document ownership and add dry-run/temp output options.
- Move low-risk scripts with wrappers.
- Rollback by preserving wrappers and aliases.
