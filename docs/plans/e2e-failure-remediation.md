# E2E Failure Remediation Plan

Goal: Resolve all 30 scenario failures from the 2026-05-21 E2E run.
Context: Run against Docker Compose (standalone), mock Twilio containerized, nix flake dev environment for Playwright.

Sub-plans for complex steps are linked in each section. See `docs/plans/e2e-<ID>-*.md`.

## Categorization

| Priority | Category | Count | Scenarios |
|----------|----------|-------|-----------|
| P0 | Infrastructure / Container Networking | 4 | 53, 59, 60, 61 |
| P1 | AppView Handler Gaps | 7 | 39, 45, 55 |
| P2 | Auth / Token / Session Edge Cases | 5 | 43, 54, 55 |
| P3 | Rate Limiting / PLC / Firehose | 4 | 31, 32, 33, 30 |
| P4 | Known Gaps / Stubbed / Pre-existing | 9 | 26, 15, 06, 10, 51, 58, 11 |

---

## P0: Infrastructure & Container Networking

### 53 — Phone Verification (Twilio)
- **Symptom**: PDS returns HTTP 500 "Not Found" on `requestPhoneVerification`
- **Root cause**: PDS constructs URL `{baseURL}/{serviceSID}/Verifications` but mock expects `/v2/Service/{serviceSID}/Verifications`
- **Sub-plan**: [docs/plans/e2e-053-twilio-path-fix.md](e2e-053-twilio-path-fix.md) — detailed investigation and fix options
- **Verification**: Re-run scenario 53 standalone within nix flake dev shell.

### 59 — Web Client Browser Flow
- **Symptom**: Playwright Chromium executable missing
- **Root cause**: Chromium not installed in the host environment
- **Fix**: Run `nix shell nixpkgs#playwright-driver.chromium` or install via `playwright install chromium` inside nix flake. The scenario runner should check for Playwright availability before running.
- **Note**: This scenario must run INSIDE the nix flake dev environment where Playwright is available. Update the run script to detect and warn.

### 60 — Mikrus Links
- **Symptom**: Connection refused on `http://localhost:3210/xrpc/blue.microcosm.repo.getRecordByUri`
- **Root cause**: Mikrus service (port 3210) not running in Docker Compose or not started
- **Sub-plan**: [docs/plans/e2e-060-mikrus-service.md](e2e-060-mikrus-service.md) — adding the service to Docker Compose
- **Verification**: `curl localhost:3210/xrpc/_health` before running scenarios.

### 61 — Graph Read Verification (`getFollows`)
- **Symptom**: `getFollows` returns 0 follows (Marcus not found in Luna's follows)
- **Root cause**: Unknown — needs investigation (handler routing vs. indexing gap)
- **Sub-plan**: [docs/plans/e2e-061-graph-read-verification.md](e2e-061-graph-read-verification.md) — root cause investigation
- **Potential fix**: Add wait/retry in the scenario for AppView index propagation, or fix the indexing path.

---

## P1: AppView Handler Gaps

### 39 — List Management
- **Failures**: `app.bsky.graph.getLists` (404), `app.bsky.graph.getList` (404)
- **Root cause**: XRPC handlers not registered in AppView for these methods
- **Sub-plan**: [docs/plans/e2e-039-list-management-handlers.md](e2e-039-list-management-handlers.md) — add service methods + route registrations
- **Lexicon**: See `lexicons/app/bsky/graph/getLists.json` and `getList.json`

### 45 — Labeler Subscription
- **Failures**: Record creation fails (missing `labelValues`); `app.bsky.labeler.getServices` (404)
- **Root cause**: Client doesn't include required field `labelValues`; handler for `getServices` not registered
- **Sub-plan**: [docs/plans/e2e-045-labeler-subscription.md](e2e-045-labeler-subscription.md) — scenario fix + handler registration

### 55 — Takedown Read Enforcement
- **Failures**: `updateSubjectStatus` (400 "Missing subject DID"); `getRecord` (404 "MethodNotFound"); takedown not enforced on read
- **Root cause**: Three distinct issues:
  1. Admin `updateSubjectStatus` payload missing `subject.did` — scenario API mismatch
  2. `com.atproto.admin.getRecord` handler not registered
  3. Takedown enforcement logic not implemented on the read path
- **Sub-plan**: [docs/plans/e2e-055-takedown-enforcement.md](e2e-055-takedown-enforcement.md) — all three fixes
- **Fix**: Fix scenario payload, register handler, implement read-path enforcement

---

## P2: Auth / Token / Session Edge Cases

### 43 — Multi-Device Session Management
- **Failure**: Deleting one session revokes all sessions (ExpiredToken)
- **Root cause**: Session revocation scope too broad — should only revoke the targeted session
- **Sub-plan**: [docs/plans/e2e-043-multi-device-sessions.md](e2e-043-multi-device-sessions.md) — per-device revocation design
- **Fix**: Implement per-device session revocation in the auth layer (PDS `com.atproto.server.deleteSession`)

### 54 — Negative Auth Paths
- **Failures**: Suspended account write succeeds (expected 403); suspended account read succeeds (expected 403)
- **Root cause**: Suspension enforcement not implemented on write/read paths
- **Sub-plan**: [docs/plans/e2e-054-suspension-enforcement.md](e2e-054-suspension-enforcement.md) — middleware changes
- **Fix**: Add suspension checks to repo write and read handlers

### 55 — (see P1 also) — Record takedown enforcement on reads
- **Failure**: Takedown not enforced on public read paths
- **Sub-plan**: [docs/plans/e2e-055-takedown-enforcement.md](e2e-055-takedown-enforcement.md) — read-path filtering
- **Fix**: Add takedown filter to `com.atproto.repo.getRecord` and related read endpoints

---

## P3: Rate Limiting / PLC / Firehose

### 31 — Noisy Neighbor (Rate Limiting)
- **Failure**: 61st request succeeds (expected HTTP 429)
- **Root cause**: Rate limiter not configured or threshold too high in test environment
- **Fix**: Ensure rate limiter is active in Docker Compose PDS config; verify limit matches scenario expectation (60 req/min)

### 32 — Identity Fatigue (PLC)
- **Failure**: PLC hourly limit not enforced (expected HTTP 400, got 200)
- **Root cause**: PLC rate limit not configured in mock PLC server
- **Fix**: Configure rate limiting in the PLC container config

### 33 — Tortoise Consumer (Firehose Backpressure)
- **Failure**: Firehose disconnect test timed out — connection still open
- **Root cause**: Tortoise consumer backpressure mechanism not triggered within the timeout window
- **Sub-plan**: [docs/plans/e2e-033-firehose-backpressure.md](e2e-033-firehose-backpressure.md) — subscription timeout investigation
- **Fix**: Investigate firehose subscription timeout / disconnect logic; may need to adjust the scenario timeout or fix the backpressure trigger

### 30 — Temporal Distortion
- **Failure**: Missing root in `getHead` — MST root not found after concurrent operations
- **Root cause**: Race condition in MST commit logic under concurrent writes
- **Sub-plan**: [docs/plans/e2e-030-temporal-distortion.md](e2e-030-temporal-distortion.md) — MST concurrency debugging
- **Fix**: Debug the MST/compatibility layer for concurrent write commit ordering

---

## P4: Known Gaps / Pre-existing

### 26 — AppView Ingest Load (Timeout)
- **Failure**: Timed out after 120s
- **Root cause**: AppView ingestion pipeline cannot keep up with load
- **Sub-plan**: [docs/plans/e2e-026-appview-ingest-load.md](e2e-026-appview-ingest-load.md) — performance investigation
- **Fix**: Backpressure / batch processing optimization in AppView; increase timeout as temporary workaround

### 15 — Mutes, Relationships & Starter Packs
- **Failures**: Starter pack not found in AppView; `getStarterPack` returns 404
- **Root cause**: Starter pack indexing gap in AppView
- **Fix**: Implement starter pack indexing in AppView subscription/ingestion

### 06 — Chat DMs (allowIncoming)
- **Failure**: `getConvoForMembers` not rejected when `allowIncoming=none`
- **Root cause**: Chat allowIncoming policy not enforced in the Chat service
- **Sub-plan**: [docs/plans/e2e-006-chat-allow-incoming.md](e2e-006-chat-allow-incoming.md) — enforcement implementation
- **Fix**: Implement allowIncoming policy check in the DM acceptance path

### 10 — Performance & Resilience
- **Failure**: Non-existent collection not rejected (call succeeded)
- **Root cause**: No validation that collection exists in the lexicon registry
- **Fix**: Add collection existence check in `com.atproto.repo.createRecord` handler

### 51 — Blob Garbage Collection
- **Failure**: Keep-alive blob missing after GC
- **Root cause**: Blob GC doesn't respect keep-alive references
- **Sub-plan**: [docs/plans/e2e-051-blob-gc-keepalive.md](e2e-051-blob-gc-keepalive.md) — GC reference tracking fix
- **Fix**: Track keep-alive references during blob enumeration before deletion sweep

### 58 — Account Delete Cascade
- **Failures**: Records, CAR, and blobs remain after account deletion
- **Root cause**: Account deletion cascade not fully implemented — cleanup tasks for records, CAR archive, and blob storage are missing
- **Sub-plan**: [docs/plans/e2e-058-account-delete-cascade.md](e2e-058-account-delete-cascade.md) — cascade implementation
- **Fix**: Implement full account deletion cascade in the PDS

### 11 — Lab OAuth2 Login
- **Failures**: `client_id` mismatch; admin login returns 403
- **Root cause**: OAuth2 lab client metadata URL scheme mismatch; admin auth check too strict
- **Fix**: Fix client_id URL in scenario; review admin auth middleware

### 13 — OAuth2 E2E Client Integration
- **Status**: Resolved / not currently reproducible
- **Verification**: `./scripts/run_scenarios.ts 13` passed 12/12 on 2026-05-22 local time.
- **Observed DID endpoint**: `serviceEndpoint=http://127.0.0.1:2583`
- **Notes**: The current Docker local-network config sets the PDS issuer to `http://127.0.0.1:2583`, account creation writes `services.atproto_pds.endpoint` into the signed PLC operation, and PLC DID rendering emits it as DID `serviceEndpoint`.

---

## Execution Order

Each item links to its sub-plan where one exists.

### Phase 1: Infrastructure (runs first, unblocks verification)
- [ ] 59: Install Playwright Chromium (nix flake or playwright install)
- [ ] 60: Add Mikrus service to Docker Compose + health check ([sub-plan](e2e-060-mikrus-service.md))
- [ ] 53: Debug PDS → mock Twilio URL path mismatch ([sub-plan](e2e-053-twilio-path-fix.md))
- [ ] 61: Investigate follow indexing gap in AppView ([sub-plan](e2e-061-graph-read-verification.md))

### Phase 2: AppView Handlers (high impact, missing endpoints)
- [ ] 39: Register `app.bsky.graph.getLists` and `getList` handlers ([sub-plan](e2e-039-list-management-handlers.md))
- [ ] 45: Register `app.bsky.labeler.getServices` handler; fix scenario payload ([sub-plan](e2e-045-labeler-subscription.md))
- [ ] 55: Register `com.atproto.admin.getRecord` handler ([sub-plan](e2e-055-takedown-enforcement.md))

### Phase 3: Auth & Enforcement
- [ ] 54: Add suspension checks to write/read handlers ([sub-plan](e2e-054-suspension-enforcement.md))
- [ ] 43: Implement per-device session revocation ([sub-plan](e2e-043-multi-device-sessions.md))
- [ ] 55: Implement record takedown enforcement on read path ([sub-plan](e2e-055-takedown-enforcement.md))

### Phase 4: Rate Limiting & Protocol
- [ ] 31: Configure/enable rate limiter in PDS Docker Compose config
- [ ] 32: Add rate limits to mock PLC server
- [ ] 33: Debug firehose backpressure disconnect ([sub-plan](e2e-033-firehose-backpressure.md))
- [ ] 30: Debug MST/concurrent-write race condition ([sub-plan](e2e-030-temporal-distortion.md))

### Phase 5: Known Gaps
- [ ] 26: Optimize AppView ingestion or increase timeout ([sub-plan](e2e-026-appview-ingest-load.md))
- [ ] 15: Implement starter pack indexing
- [ ] 06: Implement chat allowIncoming enforcement ([sub-plan](e2e-006-chat-allow-incoming.md))
- [ ] 10: Add collection existence validation
- [ ] 51: Fix blob GC keep-alive tracking ([sub-plan](e2e-051-blob-gc-keepalive.md))
- [ ] 58: Implement account delete cleanup cascade ([sub-plan](e2e-058-account-delete-cascade.md))
- [ ] 11: Fix OAuth2 lab client_id; debug admin auth
- [x] 13: PLC DID document service endpoint registration verified

---

## Verification

Each fix is verified by running the affected scenario(s) standalone inside the nix flake dev environment:

```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario <ID>"
```

After all Phase 1-2 fixes, run a full suite to confirm no regressions:

```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --all"
```
