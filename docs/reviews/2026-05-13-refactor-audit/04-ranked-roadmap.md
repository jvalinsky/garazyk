# Ranked Refactor Roadmap

Date: 2026-05-13

Deciduous:
- Roadmap action node: 1580
- Attached document: 66
- Outcome nodes: 1583, 1584
- Parent deep-dive action: 1579

## P0

### 1. XRPC Registry/Lexicon Contract Map

Goal: make method registration, lexicon type, HTTP method, auth mode, handler owner, and error-shape policy auditable from one catalog.

Implementation plan:
- Add a read-only method catalog and tests first; do not replace handlers.
- Seed the catalog with representative PDS, AppView, Relay, Chat, Ozone, Video, Germ, and proxy methods.
- Extend coverage tooling to consume the catalog using explicit output paths.
- Add contract tests for query/procedure mapping, registered NSIDs, and JSON error shape.

Acceptance:
- Test fails when a method is registered with the wrong query/procedure HTTP method.
- Test fails when a cataloged method is missing from dispatcher/direct routes.
- Proxy tests cover DID plus service fragment.

### 2. Shared HTTP Client Dependency Injection

Goal: make network boundaries testable without singleton swizzling while preserving `ATProtoSafeHTTPClient` behavior.

Implementation plan:
- Define a protocol for the safe HTTP methods in actual use.
- Add default adapter backed by `[ATProtoSafeHTTPClient sharedClient]`.
- Convert `OAuth2Handler`, DID/PLC resolver, federation client, proxy interceptor, and AppView write proxy/hooks first.
- Replace singleton-dependent tests with fake-client tests.

Acceptance:
- Converted classes can be tested with fake timeout, invalid JSON, redirect, and SSRF responses.
- Existing concrete safe-client tests still cover GNUstep fallback behavior.

### 3. `objc-jupyter-wasm` Interpreter Dispatch Split

Goal: separate parsing, Foundation dispatch, runtime/class dispatch, and JSON helpers before fixing runtime P0 behavior.

Implementation plan:
- Mechanically extract modules with no semantic changes.
- Keep public C/JS bridge entry points stable.
- Use runtime gap probes as required checks.
- Then fix P0s: loop break/continue, `isKindOfClass:`, `NSMutableString`, and super dispatch.

Acceptance:
- Existing wasm runtime tests pass after extraction.
- New focused probes cover every P0 fixed behavior.

### 4. Admin UI Runtime Split

Goal: reduce auth/XSS/CSRF-sensitive churn in `UIServerRuntime.m`.

Implementation plan:
- Extract route packs by domain while keeping `UIServerRuntime` as composition root.
- Extract escaping, CSP, and CSRF helpers.
- Convert HTML assembly into renderer helpers with sanitized view models.

Acceptance:
- All existing admin routes still dispatch.
- Representative partial rendering tests pass before/after extraction.
- POST actions remain auth and CSRF guarded.

## P1

### 5. Legacy `PDSDatabase` Facade Decomposition

Goal: isolate connection lifecycle, statement cache, account access, record access, and legacy migrations behind private collaborators.

Implementation plan:
- Add characterization tests first.
- Extract private collaborators without changing public `PDSDatabase` API.
- Move consumers toward modern ActorStore/service DB repositories only after parity.

Acceptance:
- Fresh and migrated DB behavior match existing tests.
- Statement cache and rollback behavior are characterized.

### 6. Queue Contract Assertions And State Confinement

Goal: make stateful queue ownership explicit in high-risk classes.

Implementation plan:
- Start with DB, auth/session, AppView ingest/backfill, Relay/Firehose, UI auth/backend, and safe HTTP client.
- Add queue-specific keys/assert helpers where platform-compatible.
- Snapshot state before invoking callbacks.

Acceptance:
- Tests cover re-entrant calls, callback ordering, and shutdown paths.
- Queue contract violations are caught in debug/test builds.

### 7. `skylab` XRPC Bridge Protocol Alignment

Goal: make demo/lab XRPC calls follow lexicon query/procedure semantics.

Implementation plan:
- Replace `method.startsWith(...)` query detection with a method metadata table.
- Separate service routing from HTTP method selection.
- Add bridge unit tests and a browser smoke script.

Acceptance:
- Known query methods generate GET URLs with query params.
- Known procedures generate POST requests with JSON body.

### 8. Missing Chat/Ozone/Shared Test Suites

Goal: close structural testing gaps before refactoring services that depend on them.

Implementation plan:
- Add baseline Chat service tests.
- Add Ozone `ModerationService` tests for event/status/template/safelink flows.
- Add Shared design system tests where logic exists, or document static-only coverage.

Acceptance:
- New suites cover happy path, invalid input, empty state, and persistence failures.

### 9. Script/Docs Tooling Ownership And Dry-Run Outputs

Goal: reduce stale reports and make audits non-mutating by default.

Implementation plan:
- Document canonical owners.
- Add `--dry-run` or temp output examples to report generators.
- Move or wrap obsolete scripts according to the existing script hygiene plan.

Acceptance:
- Active scripts have `--help` smoke tests.
- Report generation can run into `/tmp` without touching tracked reports.

## P2

### 10. GNUstep Compatibility Normalization

Goal: lower platform drift by making shim/capability ownership explicit.

Implementation plan:
- Review architecture scanner hits manually.
- Convert ad hoc platform checks to established macros where appropriate.
- Document intentional macOS-only paths.

Acceptance:
- No new unguarded platform-sensitive APIs in runtime paths.

### 11. SQL Identifier And Placeholder Helper Consolidation

Goal: distinguish safe generated SQL fragments from risky dynamic SQL.

Implementation plan:
- Centralize `IN (?, ?, ?)` placeholder generation.
- Add whitelist helpers for identifiers and sort keys.
- Add tests with injection-like values for every helper.

Acceptance:
- Security scans become easier to triage.
- No behavior change in generated queries.

### 12. Web Rendering Helper For Repeated `innerHTML`

Goal: reduce repeated panel rendering and XSS risk across `skylab` and admin static assets.

Implementation plan:
- Add small helpers for empty/error/preformatted states and safe text insertion.
- Convert one panel at a time.

Acceptance:
- UI smoke tests cover unsafe text rendering.

## Rollout Defaults

- Each P0/P1 starts with characterization tests.
- Prefer one subsystem per branch/commit.
- Keep old public APIs until replacement tests pass.
- Use deciduous action/outcome nodes for each implementation phase.
