# Refactor Inventory Matrix

Date: 2026-05-13

Deciduous:
- Inventory action node: 1577
- Attached documents: 63
- Parent goal: 1568
- Selected methodology decision: 1575

## Baseline

Current working tree at inventory time:
- `Garazyk/Sources/Network/XrpcRepoMethods.m` modified before this investigation. Treat as user work.

Approximate surface sizes:

| Surface | Files | Notable observations |
|---|---:|---|
| `Garazyk/Sources` | 820 | Large Objective-C service, DB, XRPC, auth, network, sync, appview, compat, and UI runtime surface. |
| `Garazyk/Tests` | 392 | Mature suite, but report notes Chat/Ozone/Shared structural gaps and singleton mocking debt. |
| `objc-jupyter-wasm` | 144 excluding `node_modules` | Interpreter/runtime split has large C modules and explicit runtime gap report. |
| `skylab` | 12 | Small surface, but central bridge owns routing/auth/state and panels use repeated DOM rendering patterns. |
| `scripts` | 7099 files including nested package/tool outputs | Needs ownership separation; prior plan identifies stale, duplicate, placeholder, and move candidates. |
| `docs`/`reports` | 631 | Many plans/reports, some stale; docs tooling has generated registry/link/report workflows. |

## Largest Or High-Signal Files

| Path | Lines | Why inspect |
|---|---:|---|
| `Garazyk/Sources/Auth/OAuth2Handler.m` | 4110 | OAuth routes, DPoP, metadata, client validation, shared global queues, SSRF-sensitive client metadata fetch. |
| `Garazyk/Sources/Database/PDSDatabase.m` | 3804 | Legacy monolithic DB facade with migrations, statement cache, transactions, schema, account and record access. |
| `Garazyk/Sources/AdminUIServer/UIServerRuntime.m` | 3008 | Admin UI routes, auth guards, CSP, HTML generation, static assets, many action endpoints in one runtime. |
| `objc-jupyter-wasm/kernel/objc_interp_messages.c` | 4002 | Message parsing, Foundation dispatch, JSON helpers, selector logic, and runtime feature stubs. |
| `Garazyk/Sources/Network/AppViewXRpcRoutePack.m` | 1945 | Direct HTTP route registration for many AppView XRPC endpoints; high contract drift risk. |
| `Garazyk/Sources/AdminUIServer/UIBackendClient.m` | 1822 | Hard-coded XRPC URL construction across many admin/backend services. |
| `Garazyk/Sources/Services/PDS/PDSRepositoryService.m` | 1848 | Repository lifecycle and commit boundary. |
| `Garazyk/Sources/Services/PDS/PDSRecordService.m` | 1594 | Record validation, stats cache, and PDS service behavior. |
| `Garazyk/Sources/Network/XrpcAdminMethods.m` | 1572 | Admin XRPC surface with route registration and authorization sensitivity. |
| `scripts/docs/repo_docs.py` | 933 | Canonical docs registry/link/orphan workflow with generated outputs. |
| `scripts/docs/generate_xrpc_coverage_report.cjs` | 841 | Important report generator for route/lexicon sync; default output paths mutate reports. |
| `skylab/static/js/skylab-bridge.js` | 352 | Service-aware XRPC client, auth state, event bus, and state bridge. |

## Existing Reports And Prior Plans

| Source | Signal |
|---|---|
| `reports/unit_testing_gaps_summary.md` | Chat, Ozone, and Shared lack corresponding unit suites; XRPC registration gaps noted; `ATProtoSafeHTTPClient sharedClient` dependency injection debt. |
| `reports/stubs_report.txt` | Current source stubs include registration CAPTCHA, STAR reconstruction, CLI service stub, GNUstep/security placeholders, and chat actor placeholder responses. |
| `docs/plans/sans-io-refactor.md` | Prior network/parser refactor path already extracted some pure cores; use its characterization-first pattern. |
| `docs/plans/2026-05-08-script-and-nix-hygiene-plan.md` | Existing script cleanup inventory marks duplicate/stale/placeholder scripts and ownership moves. |
| `/tmp/garazyk-refactor-architecture-audit/summary.md` | GNUstep, XRPC, parser, DoS, SQLite, and test-gap heuristic signals. Some scanner paths are stale, so treat as heuristics. |
| `/tmp/garazyk-refactor-concurrency-audit/summary.md` | 549 threading sites, 108 synchronization sites, 0 queue assertion sites; prioritize queue contracts around mutable shared state. |
| `/tmp/garazyk-refactor-security-audit/summary.md` | SQL formatting, dynamic identifiers, crypto/logging heuristics; secrets scan found no source secrets. |

## Surface Notes

### Core Garazyk

Current refactor pressure is strongest around:
- Route registry and XRPC method contract consistency.
- HTTP client injection and network isolation.
- Legacy DB facade split from modern ActorStore/service DB patterns.
- Queue contract documentation/assertions in stateful services.
- Admin UI runtime split into route packs/renderers/actions.
- GNUstep compatibility normalization around platform-sensitive APIs.

### `objc-jupyter-wasm`

Current refactor pressure is strongest around:
- Separating message parsing from Foundation method dispatch.
- Turning feature gap report categories into implementation slices.
- Centralizing marker/string/object representation helpers.
- Keeping tests as the safety rail before changing interpreter semantics.

### `skylab`

Current refactor pressure is strongest around:
- XRPC method type detection and service routing.
- Shared API/render helpers to reduce repeated `innerHTML`.
- Auth token handling and state bridge clarity.

### Scripts, Tooling, Docs

Current refactor pressure is strongest around:
- Declaring canonical owners for docs migration tooling, report generators, scenario runners, ops scripts, and wasm scripts.
- Making report generators support dry-run/temp-output modes by default for audits.
- Reducing duplicate scenario/control scripts.

### Tests

Current refactor pressure is strongest around:
- Missing Chat/Ozone/Shared suites.
- Dependency injection seams for network clients.
- Characterization tests before route, DB, interpreter, and script runner changes.
