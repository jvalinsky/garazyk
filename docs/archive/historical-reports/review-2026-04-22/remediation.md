# Prioritized Remediation Plan

**Generated**: 2026-04-22
**Based on**: docs/review-2026-04-22/ findings

## Phase 1: Firehose Event Emission (Critical — 1-2 days)

These fixes are interdependent and should be done together.

### Step 1: Add generic `broadcastAccountStatus:active:status:` to SubscribeReposHandler

**Why**: Currently only `broadcastAccountTakedown:` exists, hardcoding `active=NO, status="takendown"`. A generic method supports all lifecycle transitions.

**Files**:
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — Add method
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.h` — Declare method
- `Garazyk/Tests/Sync/SubscribeReposHandlerTests.m` — Add tests

**Spec**: https://atproto.com/specs/sync — `#account` event type

### Step 2: Add `PDSAccountLifecycleNotification` notification

**Why**: `PDSAccountService` has no reference to `SubscribeReposHandler`. Following the existing pattern of `PDSRecordDidChangeNotification`, add a notification for account lifecycle events.

**Files**:
- `Garazyk/Sources/Core/PDSAccountEvents.h` — Define notification names and user info keys
- `Garazyk/Sources/Services/PDS/PDSAccountService.m` — Post notifications on create/activate/deactivate
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — Observe notifications

### Step 3: Wire account creation to emit `#identity` and `#account`

**Why**: New accounts are invisible on the firehose (C2).

**Files**:
- `Garazyk/Sources/Services/PDS/PDSAccountService.m` — Post `PDSAccountCreatedNotification` after line 270
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — Observe and broadcast

### Step 4: Wire activate/deactivate to emit `#account`

**Why**: Lifecycle transitions are invisible (C1 partial fix).

**Files**:
- `Garazyk/Sources/Network/XrpcServerMethods.m` — Post notifications after activate/deactivate
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — Observe and broadcast

### Step 5: Add `#account` event forwarding in relay

**Why**: Even after PDS emits `#account`, relay drops them (M3).

**Files**:
- `Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.m` — Add `#account` forwarding

---

## Phase 2: Account Lifecycle Semantics (High — 2-3 days)

### Step 6: Separate deactivation from takedown

**Why**: `deactivateAccount` calls `takeDownAccount` with wrong semantics (H3).

**Files**:
- `Garazyk/Sources/Admin/PDSAdminController.h` — Add `deactivateAccount:reason:error:` to protocol
- `Garazyk/Sources/Admin/PDSAdminController.m` — Implement with distinct status
- `Garazyk/Sources/Network/XrpcServerMethods.m` — Call new method from deactivateAccount handler

### Step 7: Wire `com.atproto.server.getAccount` handler

**Why**: Declared but not implemented (H2).

**Files**:
- `Garazyk/Sources/Network/XrpcServerMethods.m` — Add handler in `registerAccountLifecycleEndpoints:`
- `Garazyk/Tests/Network/XrpcServerMethodsTests.m` — Add test

### Step 8: Remove email from `getAccountForDid:` response

**Why**: PII leak (M4).

**Files**:
- `Garazyk/Sources/Services/PDS/PDSAccountService.m` — Remove `email` from return dict

---

## Phase 3: PLC Improvements (High — 3-5 days)

### Step 9: Implement streaming `/export` endpoint

**Why**: Current implementation buffers all operations in memory (H1).

**Files**:
- `Garazyk/Sources/Network/HttpResponse.h` — Add chunked transfer encoding support
- `Garazyk/Sources/Network/HttpResponse.m` — Implement streaming write
- `Garazyk/Sources/PLC/PLCServer.m` — Rewrite `handleExport:` to stream
- `Garazyk/Sources/PLC/PLCPersistentStore.m` — Add batched export method

### Step 10: Add stricter PLC validation

**Why**: `alsoKnownAs` entries not validated for `at://` prefix, service endpoints not validated for HTTPS (L2).

**Files**:
- `Garazyk/Sources/PLC/PLCServer.m` — Add validation in `PLCValidateIncomingOperation`

### Step 11: Add PLC recovery window

**Why**: Key rotation is instant with no grace period (L1).

**Files**:
- `Garazyk/Sources/PLC/PLCPersistentStore.m` — Add pending operation storage
- `Garazyk/Sources/PLC/PLCServer.m` — Implement recovery window logic
- `Garazyk/Sources/PLC/PLCAuditor.m` — Check recovery window during verification

---

## Phase 4: Testnet Improvements (Medium — 1-2 days)

### Step 12: Fix Docker key persistence

**Why**: Keys in `/tmp` are lost on reboot (M1).

**Files**:
- `docker/local-network/docker-compose.yml` — Use named volumes

### Step 13: Add AppView to E2E stack

**Why**: Cannot test full pipeline without AppView (M2).

**Files**:
- `docker/e2e/docker-compose.yml` — Add syrena service

---

## Phase 5: Account Migration (Large — 6-10 weeks)

### Step 14: Implement migration endpoints

**Why**: Core AT Protocol feature completely absent (H4).

**Scope**: See [[files/migration.md]] for detailed plan.

This is a large scope item that should be planned separately after Phases 1-4 are complete.

---

## Dependency Graph

```
Step 1 (generic broadcastAccountStatus)
  → Step 2 (notification pattern)
    → Step 3 (creation events)
    → Step 4 (lifecycle events)
  → Step 5 (relay forwarding)

Step 6 (separate deactivate/takedown)
  → Step 4 (uses correct status in broadcast)

Step 7 (wire getAccount)
Step 8 (remove email from getAccount)

Step 9 (streaming export)
Step 10 (stricter validation)
Step 11 (recovery window)

Step 12 (Docker keys)
Step 13 (E2E AppView)

Step 14 (migration) — depends on Steps 1-8
```

## Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1 | 1-2 days | None |
| Phase 2 | 2-3 days | Phase 1 |
| Phase 3 | 3-5 days | None (parallel with Phase 2) |
| Phase 4 | 1-2 days | None (parallel with Phase 2-3) |
| Phase 5 | 6-10 weeks | Phases 1-2 |

**Total for Phases 1-4**: ~1-2 weeks
**Total including Phase 5**: ~2-3 months
