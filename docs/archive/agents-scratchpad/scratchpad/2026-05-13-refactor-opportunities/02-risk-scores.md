# Refactor Opportunity Risk Scores

Date: 2026-05-13

Deciduous:
- Scoring action node: 1578
- Attached document: 64
- Parent inventory action: 1577
- Roadmap action: 1580

Scoring: 1-5 each for boundary risk, structural drag, test leverage, change safety risk, and payoff. Higher totals indicate better refactor priority, not necessarily immediate editability.

| Priority | Candidate | Boundary | Drag | Tests | Safety | Payoff | Total | Confidence |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| P0 | XRPC registry/lexicon contract map | 5 | 5 | 4 | 4 | 5 | 23 | 88 |
| P0 | Shared HTTP client dependency injection | 5 | 4 | 5 | 3 | 5 | 22 | 87 |
| P0 | `objc-jupyter-wasm` interpreter dispatch split | 4 | 5 | 5 | 4 | 5 | 23 | 86 |
| P0 | Admin UI runtime route/render/action split | 4 | 5 | 4 | 3 | 5 | 21 | 84 |
| P1 | Legacy `PDSDatabase` facade decomposition | 5 | 5 | 4 | 5 | 5 | 24 | 82 |
| P1 | Queue contract assertions and state confinement | 4 | 4 | 4 | 4 | 4 | 20 | 80 |
| P1 | `skylab` XRPC bridge protocol alignment | 4 | 3 | 4 | 2 | 4 | 17 | 86 |
| P1 | Script/docs tooling ownership and dry-run outputs | 3 | 4 | 3 | 3 | 4 | 17 | 85 |
| P1 | Missing Chat/Ozone/Shared test suites | 4 | 3 | 5 | 2 | 4 | 18 | 84 |
| P2 | GNUstep platform-sensitive API normalization | 3 | 3 | 3 | 3 | 4 | 16 | 74 |
| P2 | SQL identifier/placeholder helper consolidation | 4 | 3 | 3 | 3 | 4 | 17 | 78 |
| P2 | Web UI rendering helper for `innerHTML` patterns | 3 | 3 | 3 | 2 | 3 | 14 | 78 |

## Evidence Highlights

### XRPC Registry/Lexicon Contract Map

Evidence:
- Architecture audit saw 1113 method registration signals and 3439 error-shape signals.
- `reports/unit_testing_gaps_summary.md` reports critical endpoint registration gaps.
- `AppViewXRpcRoutePack.m` has many direct `/xrpc/...` routes, while dispatcher packs use `registerMethod:`.
- XRPC spec requires `/xrpc/{NSID}` paths, clear query/procedure semantics, JSON error shape, and Lexicon-defined params/input/output/errors.

Risk:
- Contract drift can silently produce wrong HTTP method, wrong auth, wrong error shape, or missing lexicon coverage.

### Shared HTTP Client Dependency Injection

Evidence:
- `rg` found broad `[ATProtoSafeHTTPClient sharedClient]` use across PDS services, federation, DID/PLC, auth, AppView hooks/write proxy, chat auth, CLI, and tests.
- `reports/unit_testing_gaps_summary.md` calls out singleton dependence as test isolation debt.

Risk:
- Network behavior is hard to characterize and mock; timeouts/SSRF/proxying behavior becomes globally coupled.

### `objc-jupyter-wasm` Interpreter Dispatch Split

Evidence:
- `objc_interp_messages.c` is 4002 lines and includes JSON serialization helpers, parser externs, message parse, selector construction, Foundation dispatch, and placeholder paths.
- `objc-jupyter-wasm/docs/runtime-gap-report.md` lists P0 issues: loop break/continue, `isKindOfClass:`, `NSMutableString`, and super dispatch.

Risk:
- Behavior changes are easy to couple accidentally; better module seams would let feature fixes land in smaller, tested steps.

### Admin UI Runtime Split

Evidence:
- `UIServerRuntime.m` is 3008 lines and registers static assets, auth, partials, admin actions, lab routes, Ozone, PLC, relay, chat, video, appview, and HTML generation.
- The file has local escaping/CSP helpers, route registration, action dispatch, and rendering in one class.

Risk:
- Every new admin feature touches a large auth-sensitive file and increases XSS/CSRF/regression surface.

### Legacy `PDSDatabase`

Evidence:
- `PDSDatabase.m` is 3804 lines and still owns schema creation, legacy migrations, statement cache, PRAGMAs, transactions, account/record access, and compatibility behavior.
- Database skill notes a modern ActorStore/service DB architecture exists alongside this legacy facade.
- Security scan saw dynamic SQL/format signals here, many of which are constant column lists but still warrant clearer helpers.

Risk:
- Large blast radius; should be staged behind protocols and characterization tests.

### Queue Contracts

Evidence:
- Concurrency audit saw 549 threading sites, 108 synchronization sites, 296 sync sites, and 0 queue assertion sites.
- Existing DB code uses queue-specific reentrancy patterns; many other stateful classes do not expose explicit queue contracts.

Risk:
- Refactors can accidentally move callbacks/state access across queues without tests failing deterministically.

### `skylab` XRPC Bridge

Evidence:
- `skylab-bridge.js` detects query/procedure by checking `method.startsWith('get')`, `list`, `search`, or `describe`, but NSIDs start with namespace prefixes such as `app.bsky.feed.getTimeline`.
- XRPC query/procedure type should come from lexicon/method table, not naming at string start.

Risk:
- Read methods may be sent as POST with body, causing skew between demo UI and real XRPC contracts.

### Script/Docs Tooling Ownership

Evidence:
- Existing script hygiene plan identifies duplicate/stale scripts and placeholder docs validators.
- `scripts/docs/generate_xrpc_coverage_report.cjs` defaults to writing into `reports/`, which is useful for generation but awkward for read-only audits.
- Shell scripts include `rm -rf` cleanup patterns, mostly quoted but worth centralizing.

Risk:
- Tooling drift can make reports stale or hard to trust.

## Rejected Or Lower-Priority Signals

- WebSocket SHA1 findings are expected for RFC 6455 handshake and should not be treated as weak crypto without context.
- SQL format strings that only inject constant column lists or generated `?` placeholders are not immediate injection findings, but still motivate helper consolidation.
- GNUstep scanner flags many files heuristically; use for normalization planning, not bug claims.
