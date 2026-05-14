# Whole-Repo Refactor Opportunity Investigation Methodology

Date: 2026-05-13

Deciduous:
- Goal node: 1568
- Decision node: 1575
- Evidence action nodes: 1576, 1577, 1578, 1579, 1580, 1581
- Outcome nodes: 1583, 1584, 1585

## Intent

Run a whole-repo, evidence-first refactor review. The investigation treats core Garazyk Objective-C, `objc-jupyter-wasm`, `skylab`, scripts/tooling, docs infrastructure, and tests as first-class surfaces before ranking by risk.

This is research output, not implementation. Existing dirty working-tree changes are user work and must not be reverted or overwritten.

## Skills Used

- `using-deciduous`: graph nodes and scratchpad attachments.
- `slop-detector`: placeholder, boilerplate, fragile parsing, and generated-looking code scans.
- `objc-architecture-audit`: service boundaries, XRPC contracts, portability, parser, DoS, and SQLite scans.
- `better-code-objc`: Objective-C modularity, nullability, protocols, queue discipline, and error handling rubric.
- `garazyk-database` and `sqlite-sql-best-practices`: DB layer, migrations, raw SQL, and transaction review.
- `objc-concurrency-audit`: queue/lock/re-entrancy and shared state review.
- `objc-security-audit`: SQL, crypto, secrets, and log-redaction scan review.
- `gnustep-compat`: cross-platform and shim review.
- `web-ui-audit`: `skylab`, Admin UI, and browser asset review.
- `professional-bash-scripting`: shell/tooling review.

## External References

- AT Protocol overview: https://atproto.com/guides/overview
- XRPC spec: https://atproto.com/specs/xrpc
- Lexicon spec: https://atproto.com/specs/lexicon

Protocol implications:
- XRPC paths are top-level `/xrpc/{NSID}` and methods are `query`, `procedure`, or `subscription`.
- Queries should use GET and not mutate state; procedures use POST and may mutate state.
- XRPC error responses should be JSON objects with at least an `error` string.
- Proxying uses `atproto-proxy` with a DID plus service fragment, and the spec calls out active evolution around full service references in JWT `aud`.
- Lexicons define params, input, output, and error names; route-pack refactors must preserve this mapping.

## Metaplans

### Core Garazyk Objective-C

Inspect service boundaries, XRPC registration, auth/proxying, DB layers, concurrency, portability shims, and generated route pack patterns.

Primary reasons:
- Many high-risk boundaries are here: auth, DB, XRPC, network, parser, crypto, filesystem.
- Current reports show missing test coverage for Chat/Ozone/Shared and many shared HTTP client singleton uses.
- Architecture scans show high route-registration, validation, GNUstep, SQL, and queue-contract signal counts.

### `objc-jupyter-wasm`

Inspect runtime stubs, parser/interpreter dispatch boundaries, feature gap docs, build/package split, and smoke/gap tests.

Primary reasons:
- Large interpreter files combine parser state, Foundation dispatch, runtime bridge, and feature stubs.
- `docs/runtime-gap-report.md` already identifies P0/P1 missing or broken runtime behavior.
- The subsystem is test-rich enough to support staged extraction.

### `skylab`

Inspect static UI modularity, service-routing assumptions, XRPC query/procedure handling, DOM rendering, token handling, and scenario integration.

Primary reasons:
- `skylab-bridge.js` is a central client runtime with auth, event bus, state sync, and routing.
- Current GET/POST detection is name-based and appears mismatched to NSIDs.
- Many panels use `innerHTML`; some sanitize values, but a common renderer would reduce XSS risk and duplication.

### Scripts, Tooling, And Docs

Inspect runner consistency, destructive cleanup, generated reports, migration tooling, and docs validation.

Primary reasons:
- Prior script hygiene plan already identifies obsolete or placeholder tooling.
- Shell scripts include broad cleanup and curl/token flows.
- Docs tooling has overlapping Python, JS, shell, and generated report pathways.

### Tests

Inspect coverage gaps, brittle mocks, singleton swizzling, test registration, and characterization-test opportunities.

Primary reasons:
- `reports/unit_testing_gaps_summary.md` identifies Chat, Ozone, and Shared test gaps.
- Singleton `ATProtoSafeHTTPClient` usage creates hard-to-isolate network behavior.
- Refactors should start with characterization tests around protocol and persistence boundaries.

## Scoring Rubric

Each candidate is scored 1-5 on:

- Boundary risk: auth, DB, XRPC, network, parser, filesystem, crypto.
- Structural drag: file size, mixed responsibilities, duplicate logic, fragile parsing, stubs/TODOs.
- Test leverage: missing tests, I/O coupling, characterization potential.
- Change safety: public API surface, current dirty files, migration or rollout risk.
- Refactor payoff: clearer ownership, portability, protocol correctness, maintainability.

Priority is derived from total score plus confidence:
- P0: high risk and high payoff, with clear characterization tests.
- P1: meaningful payoff or known gap, but less urgent or higher staging cost.
- P2: cleanup, consolidation, or documentation/tooling improvements.

## Commands And Evidence Sources

- File inventory and line counts with `rg --files`, `find`, and `wc -l`.
- Stub/slop scan with `rg -n "TODO|FIXME|not implemented|not_implemented|placeholder|stub|HACK|temporary"`.
- Fragile-boundary scan with `rg -n "componentsSeparatedByString:|substringFromIndex:|sqlite3_exec|dispatch_sync|@synchronized|innerHTML|onclick=|rm -rf|Authorization|Bearer"`.
- Architecture scanner: `./.agents/skills/objc-architecture-audit/scripts/run_architecture_audit.sh . /tmp/garazyk-refactor-architecture-audit`.
- Concurrency scanner: `./.agents/skills/objc-concurrency-audit/scripts/run_concurrency_audit.sh . /tmp/garazyk-refactor-concurrency-audit`.
- Security scanner: `./.agents/skills/objc-security-audit/scripts/run_all_security_scans.sh . /tmp/garazyk-refactor-security-audit`.
- Existing reports: `reports/unit_testing_gaps_summary.md`, `reports/stubs_report.txt`, and previous plans under `docs/plans/`.

## Acceptance Criteria

- Every major surface gets a real inspection pass before ranking.
- Top candidates cite code, reports, or scan outputs.
- Every accepted candidate includes tests, risk, staging, and rollback notes.
- The final roadmap is implementation-ready but does not perform implementation changes.
