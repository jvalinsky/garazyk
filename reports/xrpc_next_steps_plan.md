# XRPC Next Steps Plan

Generated: 2026-02-12T17:25:29.859Z

## Baseline

- Missing in code: 6
- Coverage: 93.02%
- Unknown registry entries: 0
- Duplicate registry registrations: 50

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

### Phase 2: Repository and Sync Completeness

- Endpoint count: 0
- P0: 0, P1: 0, P2: 0, P3: 0
- Next batch:

### Phase 3: Admin, Label, and Temp APIs

- Endpoint count: 6
- P0: 0, P1: 0, P2: 6, P3: 0
- Next batch:
  - P2 `com.atproto.temp.addReservedHandle`
  - P2 `com.atproto.temp.checkHandleAvailability`
  - P2 `com.atproto.temp.checkSignupQueue`
  - P2 `com.atproto.temp.dereferenceScope`
  - P2 `com.atproto.temp.fetchLabels`
  - P2 `com.atproto.temp.requestPhoneVerification`

### Phase 4: Non-core Namespaces

- Endpoint count: 0
- P0: 0, P1: 0, P2: 0, P3: 0
- Next batch:

## Recommended Work Order

1. Implement all Phase 1 P0/P1 endpoints.
2. Implement Phase 2 P0/P1 endpoints, then run interop/sync tests.
3. Implement Phase 3 P1/P2 endpoints needed for moderation/admin workflows.
4. Re-run `scripts/generate_xrpc_coverage_report.js` after each batch.

