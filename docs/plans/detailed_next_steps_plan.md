# Detailed Next Steps Plan (2026-02-19, Deep Audit Revision)

## Objective

Clear the remaining production blockers for internet-exposed personal selfhosters after the latest code-grounded audit.

## Baseline (Now)

Completed and verified:
- In-scope `com.atproto.*` XRPC coverage is 100%.
- Refresh-token lookup/rotation/revocation flow is implemented.
- `refreshSession` auth flow is aligned to bearer refresh token usage.
- Firehose/event formatter conformance tests remain green.

Still blocking:
- Admin auth runtime selector regression.
- Password/KDF and auth-decoding correctness defects.
- Issuer/public URL consistency and backup tooling drift.
- WebSocket backpressure enforcement gaps.

## Priority Execution Plan

### P0 — Restore admin auth runtime correctness

1. Fix `extractDIDFromAuthHeader` selector mismatch in `XrpcMethodRegistry` (4-arg call vs 5-arg implementation).
2. Ensure all admin endpoints use a single canonical helper signature.
3. Re-run and stabilize:
   - `AdminAuthXrpcTests`
   - `AdminAuthApplicationXrpcTests`
4. Add regression test coverage for selector/API compatibility at class method boundary.

## P1 — Correct credential and token parsing defects

1. Fix PBKDF2 password length handling to use UTF-8 byte length (not `NSString.length`).
2. Fix salt generation to fully populate intended entropy length.
3. Fix Base64URL padding logic in:
   - `Auth/JWT.m`
   - `Auth/DPoPUtil.m`
4. Add tests for:
   - non-ASCII passwords
   - JWT/DPoP segments where `length % 4 == 1/3`
5. Validate existing account migration behavior after KDF fix.

## P1 — Unify public issuer/base URL behavior

1. Remove localhost hardcoding from application startup HTTP builder wiring.
2. Use one canonical configured issuer/public base URL for:
   - JWT issuer/audience validation context
   - NodeInfo responses
   - PLC `AtprotoPersonalDataServer` endpoint
3. Add startup validation for production mode when issuer is unset/unsafe.

## P1 — Fix backup/restore operational mismatch

1. Update `scripts/backup_pds.sh` to back up current runtime DB naming/layout (`service.db` plus user stores).
2. Add script self-check to fail fast when expected DB targets are missing.
3. Update ops docs to match on-disk runtime layout exactly.

## P2 — Firehose/WebSocket reliability hardening

1. Enforce outbound queue byte/frame cap in `WebSocketConnection`.
2. Define slow-client policy (close/drop) and instrument queue pressure metrics.
3. Ensure shutdown waits for actual async send completion, not immediate dispatch-group bookkeeping.
4. Add stress tests for slow consumers and burst broadcasts.

## P2 — Test environment resilience

1. Make `CoverageGapTests` skip gracefully when socket bind is denied in restricted CI/sandbox environments.
2. Ensure `SecurityHardeningTests` are discoverable/executed via suite filters used in CI.

## Exit Criteria

1. P0 admin auth fix merged and both admin auth suites green.
2. P1 auth parsing/KDF/base64 fixes merged with new regression tests.
3. P1 issuer and backup fixes validated in deployment smoke tests.
4. P2 websocket backpressure tests pass under synthetic load.
5. Reliability suites skip/fail cleanly in restricted environments without noisy false negatives.

## Deployment Decision

Remain **No-Go** until all P0 and P1 criteria are complete.

## Related Documentation

- [Production Readiness](production-readiness.md) - Full audit findings and evidence
- [Roadmap](ROADMAP.md) - Project milestones and future work
- [Security Hardening](../security/README.md) - Security analysis and hardening guides
- [OAuth2 Documentation](../oauth2/README.md) - Token management and DPoP implementation
- [Admin Auth Configuration](../security/ADMIN_AUTH_CONFIGURATION.md) - Admin authentication setup
- [DPoP Implementation](../oauth2/dpop.md) - DPoP proof verification details
- [Architecture Overview](../architecture/README.md) - System design decisions
