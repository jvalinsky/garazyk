# Garazyk AT Protocol Spec Compliance Review

**Date**: 2026-04-22
**Scope**: PDS, PLC, Relay, AppView against AT Protocol specification
**Method**: Code-level audit with spec citations and reference implementation comparison

## Summary

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | 2 | Firehose event emission gaps, account lifecycle broadcast missing |
| High | 4 | PLC export streaming, getAccount handler unwired, deactivateAccount semantics, migration flow absent |
| Medium | 4 | Docker key persistence, E2E stack incomplete, relay event forwarding, account status in getAccount |
| Low | 2 | PLC recovery window enforcement, lexicon validation strictness |

## Critical Findings

### C1: Firehose `#account` event only emitted on takedown

**Spec**: https://atproto.com/specs/sync — `#account` events must be emitted on all account lifecycle transitions (creation, activation, deactivation, takedown).

**Evidence**:
- `SubscribeReposHandler.m:482-514` — `broadcastAccountTakedown:` is the ONLY method that emits `#account`
- `PDSAccountService.m:261-270` — Account creation logs a hosting event (`account_created`) but does NOT call `broadcastAccountTakedown:` or any `#account` broadcast
- `XrpcServerMethods.m:1277-1324` — `activateAccount` calls `reinstateAccount:` and `deactivateAccount` calls `takeDownAccount:`, but neither triggers a firehose `#account` event with appropriate `active`/`status` values

**Impact**: Relay and AppView consumers will not learn about account creation, activation, or deactivation. They only discover takedowns. This breaks the spec-mandated event ordering: `#identity` → `#account` → `#commit`.

**Remediation**:
1. Add `broadcastAccountStatus:active:status:` method to `SubscribeReposHandler`
2. Call it from `PDSAccountService.createAccountForEmail` with `active=YES, status=nil`
3. Call it from `activateAccount` with `active=YES, status=nil`
4. Call it from `deactivateAccount` with `active=NO, status="deactivated"`
5. Rename `broadcastAccountTakedown:` to use the new generic method with `active=NO, status="takendown"`

→ [[critical.md]] | [[files/SubscribeReposHandler.md]] | [[files/PDSAccountService.md]]

### C2: Account creation does not emit `#identity` event

**Spec**: https://atproto.com/guides/account-lifecycle — Account creation must emit `#identity` event so relays discover the new DID.

**Evidence**:
- `PDSAccountService.m:261-270` — Only logs hosting event, no firehose broadcast
- `XrpcIdentityMethods.m:856` — `broadcastIdentityChange:handle:` is called for handle updates, but NOT for account creation
- `SubscribeReposHandler.m:447-480` — `broadcastIdentityChange:handle:` exists and works correctly, but is never called from the account creation path

**Impact**: Relays will not discover new accounts until the first handle update or record commit. New accounts are invisible on the firehose.

**Remediation**: After successful account creation in `PDSAccountService`, call `broadcastIdentityChange:handle:` with the new DID and handle.

→ [[critical.md]] | [[files/PDSAccountService.md]]

## High Priority Findings

### H1: PLC `/export` endpoint returns JSONL, not streaming NDJSON

**Spec**: https://web.plc.directory/spec/v0.1/did-plc — The `/export` endpoint should support streaming for large operation sets.

**Evidence**:
- `PLCServer.m:658-705` — `handleExport:` builds a complete `NSMutableString` of all operations, then returns it as a single response
- Content-Type is `application/jsonlines; charset=utf-8` (correct)
- But the implementation loads ALL operations into memory before sending, which will OOM on large directories

**Impact**: Works for small directories but will fail at scale. The reference PLC server streams operations one at a time.

**Remediation**: Implement chunked transfer encoding or streaming response. Process operations in batches, writing each line to the response as it's generated.

→ [[high.md]] | [[files/PLCServer.md]]

### H2: `com.atproto.server.getAccount` handler declared but not wired

**Spec**: https://atproto.com/specs/xrpc — Declared methods must have working handlers.

**Evidence**:
- `XrpcHandler.h:158` — Declares `registerComAtprotoServerGetAccount:handler:`
- `XrpcHandler.m:264` — Registers the method on the dispatcher: `[self registerMethod:@"com.atproto.server.getAccount" handler:handler]`
- But the actual handler registration in `XrpcServerMethods.m` does NOT include a `getAccount` handler registration
- `PDSAccountService.m:390-399` — `getAccountForDid:error:` exists and returns `{did, handle, email}`, but is never called from XRPC dispatch

**Impact**: Clients calling `com.atproto.server.getAccount` will get a 501 or empty response.

**Remediation**: Add handler registration in `registerAccountLifecycleEndpoints:` that calls `accountService.getAccountForDid:error:`.

→ [[high.md]] | [[files/XrpcServerMethods.md]]

### H3: `deactivateAccount` uses `takeDownAccount` semantics

**Spec**: https://atproto.com/guides/account-lifecycle — Deactivation is a user-initiated, reversible action distinct from admin takedown.

**Evidence**:
- `XrpcServerMethods.m:1300-1324` — `deactivateAccount` handler calls `[adminController takeDownAccount:did reason:reason error:&error]`
- This means deactivation sets the same takedown status as admin moderation
- The spec requires deactivation to set `active=false, status="deactivated"`, not `"takendown"`

**Impact**: User-initiated deactivation is indistinguishable from admin takedown in the database and firehose events. This breaks the account status model for relay consumers.

**Remediation**: Add a separate `deactivateAccount:reason:error:` method to the admin controller that sets a distinct status. Update the firehose event to emit `active=NO, status="deactivated"` instead of `"takendown"`.

→ [[high.md]] | [[files/XrpcServerMethods.md]]

### H4: Account migration flow absent

**Spec**: https://atproto.com/guides/account-migration — PDS must support account migration (export, transfer, import).

**Evidence**:
- No `com.atproto.server.prepareDeleteAccount` or migration preparation endpoint
- No `com.atproto.identity.getRecommendedDidCredentials` handler
- No DID rotation key update flow for migration
- `activateAccount`/`deactivateAccount` exist but no `requestAccountMove` or `requestPlcOperationSignature`

**Impact**: Accounts cannot be migrated between PDS instances. This is a core AT Protocol feature.

**Remediation**: Implement migration endpoints per spec. This is a large scope item — see [[files/migration.md]] for detailed plan.

→ [[high.md]] | [[files/migration.md]]

## Medium Priority Findings

### M1: Docker testnet keys in `/tmp` (fragile)

**Evidence**: `docker/local-network/docker-compose.yml` — Key material mounted from host `/tmp` paths, which are cleared on reboot.

**Impact**: Testnet requires re-seeding after every reboot.

**Remediation**: Use named Docker volumes or persistent host paths.

→ [[medium.md]]

### M2: E2E test stack lacks AppView

**Evidence**: `docker/e2e/docker-compose.yml` only has PLC + PDS + Relay. No AppView (syrena) for full pipeline testing.

**Impact**: Cannot test subscription processing, label generation, or indexed views.

**Remediation**: Add syrena to the E2E stack.

→ [[medium.md]]

### M3: Relay does not forward `#account` events from upstream

**Evidence**: `RelayDownstreamHandler.m:90` — Only forwards `#identity` events. `#account` events from subscribed PDS instances are not relayed.

**Impact**: Relay consumers miss account lifecycle events from all connected PDS instances.

**Remediation**: Add `#account` event forwarding in `RelayDownstreamHandler`.

→ [[medium.md]] | [[files/RelayDownstreamHandler.md]]

### M4: `getAccountForDid:` returns email, spec says it shouldn't

**Evidence**: `PDSAccountService.m:390-399` — Returns `{did, handle, email}`. The spec for `com.atproto.server.getAccount` returns `{did, handle}` only.

**Impact**: Potential PII leak through XRPC endpoint.

**Remediation**: Remove `email` from the response, or gate it behind auth.

→ [[medium.md]] | [[files/PDSAccountService.md]]

## Low Priority Findings

### L1: PLC recovery window not enforced

**Spec**: PLC spec requires a recovery window for rotation key changes.

**Evidence**: `PLCServer.m` — No recovery window enforcement in `handlePostDID:`. Operations are accepted immediately.

**Impact**: Key rotation is instant, no grace period for recovery.

→ [[low.md]]

### L2: Lexicon validation not strict enough

**Evidence**: Some lexicon-defined fields are not validated against their schemas. For example, `alsoKnownAs` entries should start with `at://` but this is not enforced.

**Impact**: Invalid data may be accepted and propagated.

→ [[low.md]]

## Files

- [[critical.md]] — Detailed critical findings
- [[high.md]] — Detailed high priority findings
- [[medium.md]] — Detailed medium priority findings
- [[low.md]] — Detailed low priority findings
- [[files/SubscribeReposHandler.md]] — Per-file analysis
- [[files/PDSAccountService.md]] — Per-file analysis
- [[files/PLCServer.md]] — Per-file analysis
- [[files/XrpcServerMethods.md]] — Per-file analysis
- [[files/RelayDownstreamHandler.md]] — Per-file analysis
- [[files/migration.md]] — Migration implementation plan

## Spec References

- https://atproto.com/specs/sync — subscribeRepos event format
- https://atproto.com/guides/account-lifecycle — Account lifecycle and event ordering
- https://atproto.com/guides/account-migration — Account migration protocol
- https://web.plc.directory/spec/v0.1/did-plc — PLC directory specification
- https://atproto.com/specs/xrpc — XRPC protocol specification
