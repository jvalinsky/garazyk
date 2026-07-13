# Mega Plan Audit Methodology

Date: 2026-07-12

## Objective

Replace scattered, overlapping, and stale plans with one repository roadmap
whose claims match source, tests, Git history, branches, and the decision graph.

## Scope

- Objective-C/GNUstep services, persistence, networking, and XRPC handlers
- Deno packages, scenarios, dashboards, TUI, scripts, and release tooling
- Admin UI and browser surfaces
- `objc-jupyter-wasm`
- tracked plan-like files in docs, scratchpads, root, and embedded projects

Vendor and generated reports are evidence inputs, not roadmap owners.

## Method

1. Inventory every major surface and tracked plan-like artifact.
2. Compare plan claims with source, tests, Git history, branches, and deciduous.
3. Score boundary risk, structural drag, test leverage, change safety, and
   payoff.
4. Check protocol and platform assumptions against current primary sources.
5. Keep one roadmap, move durable choices to ADRs, and delete completed or
   contradicted implementation diaries.
6. Require evidence, characterization, staging, and rollback for each item.

## Guardrails

- No implementation code changes during this audit.
- Preserve dirty PLC, RateLimiter, test, and QueryRunner-plan work.
- Scanner output is a lead until source confirms it.
- Prefer staged extractions over coordinated rewrites.

## Primary sources

- [AT Protocol accounts](https://atproto.com/specs/account)
- [AT Protocol event streams](https://atproto.com/specs/event-stream)
- [AT Protocol sync](https://atproto.com/specs/sync)
- [AT Protocol OAuth](https://atproto.com/specs/oauth)
- [AT Protocol Lexicon](https://atproto.com/specs/lexicon)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)
- [CSP Level 3](https://www.w3.org/TR/CSP/)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [SQLite transactions](https://www.sqlite.org/lang_transaction.html)
- [SQLite WAL](https://www.sqlite.org/wal.html)

## Corrections discovered

- XRPC `100%` means name presence only, not schema or behavior.
- May scenario failures are stale. The suite now lists 92 scenarios.
- Deno split and Objective-C modernization work exist off `main`.
- Several audit scripts use obsolete service and test roots.
- QueryRunner, CLI parsing, and lifecycle primitives are farther along than old
  plans state.
