# XRPC Next Steps Plan

Generated: 2026-02-13T03:52:53.566Z

## Baseline

- Missing in code: 0
- Coverage: 100%
- Unknown registry entries: 0
- Duplicate registry registrations: 0
- Duplicate registry registrations (cross-scope, actionable): 0
- Cross-scope overlap (expected controller/application dual-path): 48
- Cross-scope overlap (raw total): 48

## Priority Rubric

- P0: Critical PDS identity/account/repo/sync gaps with security or federation impact.
- P1: High-value protocol completeness for core `com.atproto.*` flows.
- P2: Admin/label/temp and useful adjacent functionality.
- P3: Non-core namespaces for appview/chat/custom extensions.

## Phased Queue

### Phase 1: Identity and Account Safety

- Endpoint count: 0
- P0: 0, P1: 0, P2: 0, P3: 0
- Next batch:
  - none

### Phase 2: Repository and Sync Completeness

- Endpoint count: 0
- P0: 0, P1: 0, P2: 0, P3: 0
- Next batch:
  - none

### Phase 3: Admin, Label, and Temp APIs

- Endpoint count: 0
- P0: 0, P1: 0, P2: 0, P3: 0
- Next batch:
  - none

### Phase 4: Non-core Namespaces

- Endpoint count: 0
- P0: 0, P1: 0, P2: 0, P3: 0
- Next batch:
  - none

## Recommended Work Order

1. No in-scope endpoint implementation backlog remains.
2. Keep `scripts/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates` in CI.
3. Re-run coverage and next-steps generation after registry or lexicon changes.

