# Admin API: parity complete; track post-parity hardening

## Summary

`com.atproto.admin.*` endpoint parity is complete against bundled lexicons.  
This issue now tracks behavior hardening and operational follow-up work.

## Snapshot (as of 2026-02-13)

- In-scope missing endpoints: **0**
- In-scope coverage: **100%**
- In-scope duplicate registrations: **0**
- Cross-scope duplicate registrations (actionable): **0**
- Cross-scope overlap (expected controller/application dual-path): **23**

Source artifacts:
- `reports/xrpc_coverage.md`
- `reports/xrpc_coverage.json`

## Implemented admin endpoints

- `com.atproto.admin.getAccountInfo`
- `com.atproto.admin.getAccountInfos`
- `com.atproto.admin.getInviteCodes`
- `com.atproto.admin.deleteAccount`
- `com.atproto.admin.disableAccountInvites`
- `com.atproto.admin.enableAccountInvites`
- `com.atproto.admin.disableInviteCodes`
- `com.atproto.admin.searchAccounts`
- `com.atproto.admin.sendEmail`
- `com.atproto.admin.updateAccountEmail`
- `com.atproto.admin.updateAccountHandle`
- `com.atproto.admin.updateAccountPassword`
- `com.atproto.admin.updateAccountSigningKey`

## Current behavior notes

- `sendEmail` currently validates input + recipient existence, logs intent, and returns `200 { sent: true }` without external delivery integration.
- `updateAccountSigningKey` currently validates `did` + `did:key:*` shape and returns success, but logs that DID document persistence is not configured.
- `disableInviteCodes` now accepts lexicon-shaped input (`codes`, `accounts`) and persists invite-code disabling with parameterized SQL updates.

## Remaining hardening backlog

- [ ] Decide and document final `sendEmail` contract when delivery is not configured (`sent: false` vs explicit config error).
- [ ] Add optional SMTP/provider-backed delivery path behind configuration.
- [ ] Define authoritative semantics for `updateAccountSigningKey` (PLC operation, repo signing key, or both).
- [ ] Implement persistence/propagation for signing-key updates once semantics are finalized.
- [ ] Add explicit negative tests for update-account uniqueness conflicts (`EmailAlreadyInUse`, `HandleAlreadyInUse`).
- [ ] Add stronger paging stability tests for `searchAccounts` cursor behavior under concurrent writes.
- [ ] Decide whether admin `note` fields are persisted (audit log) or intentionally ignored.

## Definition of done

- [x] All bundled `com.atproto.admin.*` methods are registered and reachable.
- [x] Admin auth is enforced consistently (`401` unauthenticated, `403` non-admin).
- [x] Endpoint input/output shapes align with lexicons.
- [x] Targeted endpoint tests exist and pass.
- [ ] Remaining hardening items above are either implemented or explicitly de-scoped/documented.
