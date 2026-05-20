# Garazyk Master Execution Plan

**Date:** 2026-05-15
**Status:** Draft
**Scope:** All active and pending deciduous goals, ordered by dependency and risk

---

## Dependency Graph

```
Sprint 1 (Security P0) ─────────────────────────────────────────────┐
  C1 Ozone Auth Bypass                                               │
  C2 JWT Signature Verification                                      │
  C3 Firehose Sequence Numbers                                       │
  C4 SSRF Proxy Interceptor                                          │
  C5 AppView Schema Mismatch                                         │
                                                                      │
Sprint 2 (OAuth2 Concurrency) ───────────────────────────────────────┤
  A1+A2 @synchronized → dispatch_queue + de-static                   │
  A3+A4 OAuth2Server race conditions + revoke/introspect methods     │
  A5 Safe @synchronized replacements (8 files)                       │
                                                                      ├──► Sprint 5 (OAuth2 Scalability)
Sprint 3 (Refactoring Phase 1) ──────────────────────────────────────┤   │
  1.1 ARC retain cycles in OAuth2Handler                             │   │
  1.2 @synchronized → dispatch_queue_t (remaining)                   │   │
  1.3 dispatch_semaphore_wait removal                                │   │
  1.4 Database re-entrancy safety                                    │   │
  1.5 Object initialization & defaults                              │   │
                                                                      │
Sprint 4 (Script & Nix Hygiene) ─────────────────────────────────────┤
  Batch 1: Stabilize broken scripts                                   │
  Batch 2: Delete stale duplicates                                    │
  Batch 3: Move into clearer ownership                                │
  Batch 4: Revise remaining tools                                     │
  Batch 5: Refresh Nix                                               │
                                                                      │
Sprint 5 (OAuth2 Scalability + Migration) ───────────────────────────┤
  B1 Extend OAuthProviderStorage for sessions                         │
  B2+B3 De-static remaining globals                                   │
  C1 Complete PDSAuth protocol implementations                       │
  C2 Wire OAuthProviderServer into OAuth2Handler                     │
  C3 Feature flag + shadow mode                                       │
  C4 Delete OAuth2Server                                              │
                                                                      │
Sprint 6 (Germ E2EE Phases 4-6) ────────────────────────────────────┤
  Germ scenario test (vanilla chat + swap)                            │
  Germ service config                                                 │
  ChatService mode field                                             │
  Admin UI Germ tab                                                   │
                                                                      │
Sprint 7 (Platform-Native Phases 2-4) ──────────────────────────────┤
  Phase 2: launchd/systemd service lifecycle                         │
  Phase 3: Exit codes                                                │
  Phase 4: Structured logging                                         │
                                                                      │
Sprint 8 (Documentation) ───────────────────────────────────────────┤
  Deslop Phase 1-3                                                    │
  Docs Overhaul Phases 1-5 (Nodes #889-893)                          │
                                                                      │
Sprint 9 (Security Audit Vertical Slices) ───────────────────────────┤
  Slice 1: Crypto & Auth                                              │
  Slice 2: SQLite & Injection                                         │
  Slice 3: Secrets & Log Redaction                                    │
  Slice 4: Web UI & Frontend                                          │
  Slice 5: Synthesis                                                  │
                                                                      │
Sprint 10 (Fuzzing Phases 3-5) ──────────────────────────────────────┘
  Seed corpus enrichment
  Custom mutator design
  CI/CD integration
```

**Parallelism:**
- Sprint 4 (scripts) is independent — can run in parallel with Sprints 1-3
- Sprint 6 (Germ) is independent — can run in parallel with Sprints 2-5
- Sprint 8 (docs) is independent — can run in parallel with anything
- Sprint 2 and Sprint 3 overlap significantly (same files: OAuth2Handler.m) — must be sequenced

---

## Sprint 1: Security P0 — Active Exploit Risks

**Deciduous Goal:** #925
**Estimated Duration:** 3-5 days
**Priority Reason:** Auth bypass, token forgery, SSRF, and firehose corruption are exploitable today

### C1: Ozone Admin Auth Gate Bypass

**Problem:** `XrpcToolsOzonePack.m` checks for `Authorization` header *presence* (`!authHeader`) instead of verifying the parsed `adminDid` result. Any request with any Authorization header bypasses admin checks.

**Target:** `Garazyk/Sources/Network/XrpcToolsOzonePack.m` (1226 lines)

**Steps:**
1. Read `XrpcToolsOzonePack.m` — identify all 12+ endpoint handler methods
2. Locate the guard clause pattern: `if (!authHeader) { return 401; }`
3. Replace with: verify `adminDid` is non-nil AND valid DID format after parsing
4. Extract centralized helper `ensureAdminAccess:request:completion:` to ensure consistency
5. Add test: send request with bogus Authorization header, verify 401

**Validation:**
- `AllTests` binary — all tests pass
- Manual curl test: `curl -H "Authorization: Bearer garbage" http://localhost:2583/xrpc/tools.ozone.moderation.getReports` → must return 401

### C2: Remote-Issuer JWTs Unverified

**Problem:** `AuthVerifier.m` fetches JWKS for remote JWTs but bypasses cryptographic signature verification. Tokens are accepted based on structure alone.

**Target:** `Garazyk/Sources/Auth/Verifier/AuthVerifier.m` (463 lines)

**Steps:**
1. Read `AuthVerifier.m` — trace the remote JWT validation flow
2. Find where JWKS is fetched but signature check is skipped
3. Instantiate `JWTVerifier` with the returned JWKS payload
4. Require `[verifier verifySignature] == YES` before parsing claims
5. Add test: craft a JWT with valid structure but wrong signature, verify rejection

**Validation:**
- `AllTests` binary — all OAuth2 and auth tests pass
- Test with forged remote JWT → must reject

### C3: Firehose Sequence Numbers Unassigned

**Problem:** `_sequenceNumber` increments but `event.seq = seq;` is never executed before encoding. Breaks replay and cursor-based subscription.

**Target:** `Garazyk/Sources/Sync/Firehose/FirehoseProtocolSession.m` (112 lines)

**Steps:**
1. Read `encodeCommitEvent:`, `encodeIdentityEvent:`, `encodeAccountEvent:`, `encodeInfoEvent:`
2. Add explicit `event.seq = seq;` assignment after incrementing `_sequenceNumber` and before serialization
3. Add test: subscribe to firehose, verify events have sequential seq numbers

**Validation:**
- `AllTests` binary — firehose tests pass
- Scenario test: firehose events have monotonically increasing seq numbers

### C4: Client-Controlled `atproto-proxy` SSRF

**Problem:** `XrpcProxyInterceptor.m` allows unrestricted client proxying to arbitrary targets via `atproto-proxy` header.

**Target:** `Garazyk/Sources/Network/XrpcProxyInterceptor.m` (555 lines)

**Steps:**
1. Read `XrpcProxyInterceptor.m` — understand the proxy dispatch flow
2. Implement trust boundary: only honor `atproto-proxy` if request originates from trusted internal IP (loopback, Docker network)
3. Reject absolute URLs from external clients
4. Ensure internal handlers cannot be bypassed by proxy header injection
5. Add test: external request with `atproto-proxy` header → must reject

**Validation:**
- `AllTests` binary — proxy tests pass
- External SSRF attempt → must reject

### C5: AppView Schema Mismatch

**Problem:** AppView services query PDS-style tables that don't exist in `AppViewDatabase`.

**Target:** `Garazyk/Sources/AppView/Server/AppViewRuntime.m`, `AppViewDatabase.m`

**Steps:**
1. Read both files — map the table references
2. Identify which services (DraftService, ContactService, NotificationService, etc.) query missing tables
3. Either add missing tables to AppViewDatabase schema, or route queries through correct table names
4. Add migration for any new tables
5. Add test: AppView service queries return data instead of crashing

**Validation:**
- `AllTests` binary — AppView tests pass
- Scenario test: AppView ingestion and query flow works end-to-end

### Sprint 1 Validation Gate

After all 5 fixes:
```bash
# Full test suite
./build/tests/AllTests --exclude "*Integration*" --exclude "*Socket*"

# Specific security-adjacent tests
./build/tests/AllTests --filter "OAuth*" --filter "Auth*" --filter "Firehose*" --filter "AppView*"

# Scenario smoke test
scripts/scenarios/run_scenario.py --scenario 01,04,09
```

---

## Sprint 2: OAuth2 Concurrency Fixes

**Deciduous Goal:** Part of #925, feeds into OAuth2 Overhaul plan
**Estimated Duration:** 3-4 days
**Prerequisite:** Sprint 1 (C1, C2 must be done first — auth verification must be correct before concurrency changes)
**Priority Reason:** Race conditions in OAuth2 are a stability and security risk; prerequisite for scalability work

### A1+A2: Replace @synchronized + De-static State (One Commit)

**Target:** `Garazyk/Sources/Auth/OAuth2Handler.m` (4110 lines)

**A1 Steps:**
1. Read `OAuth2Handler.m` — locate all 7 `@synchronized(sPendingConsents)` blocks and 2 `dispatch_sync(sPasskeyChallengeQueue)` blocks
2. Create `_oauthStateQueue = dispatch_queue_create("com.atproto.oauth2.state", DISPATCH_QUEUE_SERIAL)` in `-initWithDatabase:`
3. Replace each `@synchronized(sPendingConsents)` block with `dispatch_sync(self->_oauthStateQueue, ...)` (see plan table in dazzling-shiny-willow.md for exact line mappings)
4. Replace `dispatch_sync(sPasskeyChallengeQueue, ...)` with `dispatch_sync(self->_oauthStateQueue, ...)`
5. Remove `sPasskeyChallengeQueue` static and `sPasskeyChallengeOnceToken`

**A2 Steps:**
1. Move `sPendingConsents` → `_pendingConsents` (instance variable)
2. Move `sPasskeyChallenges` → `_passkeyChallenges` (instance variable)
3. Initialize both in `-initWithDatabase:`
4. Update `OAuth2Handler+Testing.h` — `pendingConsentCountForTesting` / `clearPendingConsentsForTesting` to use instance access

**Validation:**
- `AllTests` — OAuth2Tests, OAuthSessionTests, OAuthDPoPTests pass
- No deadlock under concurrent load (run scenario 08 with 10 concurrent OAuth sessions)

### A3+A4: Fix OAuth2Server Race Conditions + Add Revoke/Introspect Methods

**Target:** `Garazyk/Sources/Auth/OAuth2.h` (536 lines), `OAuth2.m` (1254 lines), `OAuth2Handler.m`

**A3 Steps:**
1. Read `OAuth2.m` — locate all unprotected `self.activeSessions` access points (7 methods, see plan table)
2. Wrap `processRefreshTokenGrant:` and `processAuthorizationCodeGrant:` bodies in `dispatch_sync(self.sessionQueue, ...)` — keep pure computation (verifyCodeVerifier, verifyPKCEChallenge) outside
3. Wrap `getSessionByAccessToken:`, `createSessionForDID:`, `refreshAccessToken:` in sessionQueue
4. Ensure no nested queue dispatch (check for re-entrancy)

**A4 Steps:**
1. Add to `OAuth2.h`:
   - `- (void)revokeSessionByToken:clientID:completion:`
   - `- (void)introspectToken:clientID:completion:`
2. Implement in `OAuth2.m` with sessionQueue protection
3. Replace direct `activeSessions` iteration in `OAuth2Handler.m` `handleRevokeRequest:` and `handleIntrospectRequest:` with new methods

**Validation:**
- `AllTests` — all OAuth2 tests pass
- Concurrent token revocation + introspection → no crashes

### A5: Replace Safe @synchronized Blocks (8 Files, Parallel)

These are independent of OAuth2 work and can be done as separate commits in parallel:

| File | Lock Object | Replacement Queue |
|------|-------------|-----------------|
| PLCMetrics.m | self.operationCounts | `com.atproto.plc.metrics` |
| DID.m | self (DIDResolver cache) | `com.atproto.did.resolver` |
| DID.m | results (batch) | `com.atproto.did.batch` |
| HandleResolver.m | results / self.requestTimestamps | `com.atproto.handle.resolver` |
| FirehoseProtocolSession.m | self | `com.atproto.firehose.session` |
| RelayEventValidator.m | self | `com.atproto.relay.validator` |
| PDSResendEmailProvider.m | self | `com.atproto.email.resend` |
| PDSVideoTranscoder.m | self.activeExports | `com.atproto.video.transcoder` |
| PDSVideoWorker.m | self.processingJobIds | `com.atproto.video.worker` |

**Pattern for each file:**
1. Read the file, locate `@synchronized` blocks
2. Create appropriately-named serial dispatch queue as instance variable
3. Replace `@synchronized(obj) { body }` with `dispatch_sync(self.queueName, ^{ body })`
4. Run relevant tests

**Note:** SubscribeReposHandler (7 blocks, 2 lock objects) is DEFERRED — needs separate audit of `_attachedConnections` vs `self` nesting before replacement.

**Validation per file:**
- `AllTests` — relevant test class passes
- No deadlock under concurrent load

### Sprint 2 Validation Gate

```bash
# Full OAuth2 test suite
./build/tests/AllTests --filter "OAuth*" --json | jq '.results[] | select(.status=="failed")'

# Concurrency stress test
scripts/scenarios/run_scenario.py --scenario 08,10

# Run with thread sanitizer
ASAN_OPTIONS=detect_stack_use_after_return=1 ./build/tests/AllTests --filter "OAuth*"
```

---

## Sprint 3: Refactoring Phase 1 — Critical Safety & Concurrency

**Deciduous Goal:** Refactoring Phase 1 (node in documents)
**Estimated Duration:** 4-5 days
**Prerequisite:** Sprint 2 (A1+A2 must be done — same file: OAuth2Handler.m)
**Priority Reason:** ARC retain cycles cause memory leaks; semaphore waits cause deadlocks; DB re-entrancy causes corruption

### 1.1 ARC Invariants & Retain Cycles in OAuth2Handler.m

**Target:** `Garazyk/Sources/Auth/OAuth2Handler.m` (4110 lines)

**Steps:**
1. Search for all blocks capturing `self` directly (no `weakSelf` pattern)
2. Identify retain cycle patterns: `self → property → block → self`
3. Replace with `__weak typeof(self) weakSelf = self;` + `__strong typeof(weakSelf) strongSelf = weakSelf;`
4. Key methods to audit:
   - `validateClient:completion:` (known from plan)
   - `handleAuthorizeConfirm:` (consent flow)
   - `handleTokenRequest:` (token issuance)
   - `handlePARRequest:` (PAR flow)
   - All dispatch_async blocks that reference `self`
5. Add test: create and release OAuth2Handler, verify dealloc is called (no retain cycle)

**Validation:**
- `AllTests` — OAuth2 tests pass
- Instruments Leaks instrument: no leaks in OAuth2 flow

### 1.2 @synchronized → dispatch_queue_t (Remaining Files)

**Already done in Sprint 2 for:** OAuth2Handler.m, OAuth2.m, and 8 other files

**Remaining:**
- `SubscribeReposHandler.m` — 7 blocks, 2 lock objects (`_attachedConnections`, `self`). Needs careful audit of nesting before replacement.
- Any other files discovered during Sprint 2

**Steps for SubscribeReposHandler:**
1. Read full file — map all lock acquisition orders
2. Determine if `_attachedConnections` and `self` locks are ever held simultaneously
3. If yes: replace with single queue to eliminate deadlock risk
4. If no: replace each with separate named queues
5. Add test: concurrent firehose subscribe + unsubscribe → no deadlock

### 1.3 Asynchronous Execution — dispatch_semaphore_wait Removal

**Target files:** `XrpcIdentityMethods.m`, `OAuth2Handler.m`, `DID.m`

**Steps:**
1. Find all `dispatch_semaphore_wait` calls
2. For each: determine if the wait is on the main thread (blocking UI) or background thread
3. Main thread waits: convert to async completion pattern
4. Background thread waits: evaluate if truly necessary; if so, add timeout and cancellation
5. Key method: `resolveDIDSync:` in DID.m (known to block 30s on GNUstep — already has dispatch_after fallback from Node #1105)

**Validation:**
- `AllTests` — identity and auth tests pass
- No main-thread hangs under slow network conditions

### 1.4 Database Re-entrancy Safety

**Target:** `AppViewDatabase.m`

**Steps:**
1. Read `AppViewDatabase.m` — find all database access points
2. Add `dispatch_get_specific` checks to detect re-entrant database access
3. If re-entrancy is detected: either queue the operation or assert (depending on safety)
4. Add test: verify re-entrant access is caught

**Validation:**
- `AllTests` — AppView tests pass
- No silent corruption under concurrent access

### 1.5 Object Initialization & Defaults

**Target:** `PDSAuthzManager.h`, `PDSBiometricKeychain.h`, `PDSConfiguration.m`

**Steps:**
1. Audit each class for: uninitialized ivars, missing `super init` calls, default values that mask bugs
2. Add `NSAssert` for required initialization parameters
3. Ensure `PDSConfiguration.m` validates all required config keys at startup
4. Add test: verify initialization with missing/invalid config → clear error, not silent wrong behavior

**Validation:**
- `AllTests` — auth and config tests pass
- Startup with invalid config → clear error message

### Sprint 3 Validation Gate

```bash
# Full test suite
./build/tests/AllTests

# Memory leak check (macOS)
leaks --atExit -- ./build/tests/AllTests --filter "OAuth*" --filter "Auth*"

# Thread sanitizer
TSAN_OPTIONS=detect_deadlocks=1 ./build/tests/AllTests --filter "OAuth*" --filter "AppView*"
```

---

## Sprint 4: Script & Nix Hygiene

**Deciduous Goal:** #1086
**Estimated Duration:** 3-4 days
**Prerequisite:** None (independent of Sprints 1-3)
**Priority Reason:** Plan is complete and ready to execute; broken scripts (uninstall.sh syntax error, hash_admin_password.sh unsafe fallback) are low-effort high-impact fixes

### Batch 1: Stabilize Broken Active Scripts

**Steps:**
1. Fix `scripts/ops/uninstall.sh` line 67: remove extra `)` after log message
2. Fix `scripts/ops/hash_admin_password.sh`: replace unsafe PBKDF2 fallback with real `hashlib.pbkdf2_hmac` or `openssl kdf`
3. Fix backup/restore helpers: validate retention as integer, add backup manifest
4. Fix `scripts/validate_pds_config.sh`: use real JSON parser, avoid Python string interpolation
5. Run: `git ls-files '*.sh' | xargs -n1 bash -n` — all must pass

**Validation:**
```bash
bash -n scripts/ops/uninstall.sh  # No syntax errors
bash -n scripts/ops/hash_admin_password.sh
scripts/test/run-tests.sh  # No regressions
```

### Batch 2: Delete Stale Duplicates

**Steps:**
1. Check references with `rg` for each file in the Delete table (26 files)
2. Update any docs or wrappers that still call deleted files
3. Delete all 26 files listed in the plan
4. Run: `rg -n '/Users/jack/Software/garazyk|ATProtoPDS/Sources|NSPds|build-linux/bin' scripts docs/scripts .opencode/tools examples objc-jupyter-wasm` — no stale paths

**Validation:**
```bash
git ls-files '*.sh' | xargs -n1 bash -n  # All remaining scripts valid
scripts/test/run-tests.sh  # No regressions
```

### Batch 3: Move Scripts Into Clearer Ownership

**Steps:**
1. Move production scripts: `add-account.sh`, `cloudflare-dns.sh`, `setup-pds.sh` → `scripts/ops/production/`
2. Move WASM scripts: `build-all.sh`, `build-jupyterlite-smoke.sh`, `build-kernel-wasm.sh`, `build-runtime-wasm.sh` → `objc-jupyter-wasm/scripts/`
3. Move fuzzing scripts (7 files) → `scripts/fuzzing/`
4. Merge 4 run-fuzzers variants into one parameterized runner
5. Move docs migration toolkit → `tooling/docs-migration/`
6. Move `.claude/hooks/` → `.agents/hooks/`
7. Leave temporary compatibility wrappers only where docs or external workflows need a deprecation window

**Validation:**
```bash
scripts/test/run-tests.sh
scripts/build/quality_gate.sh
rg -n 'scripts/(add-account|cloudflare-dns|setup-pds)\.sh' docs/  # No stale references
```

### Batch 4: Revise Remaining Active Tools

**Steps:**
1. Build scripts: add `set -euo pipefail`, portable job count, `find -print0 | xargs -0`
2. Ops scripts: add dry-run, safer UID/GID, PID scoping, `mktemp`, trap cleanup
3. Production helpers: URL-encode query params, JSON-escape bodies, remove hard-coded paths
4. Dev scripts: replace `/tmp` with `mktemp`, add timeouts
5. Test scripts: fold retired wrappers into `run-tests.sh`, delete 11 retired test wrappers
6. Docs scripts: fix path to diagram validation, consolidate link checkers

**Validation:**
```bash
git ls-files '*.sh' | xargs -n1 bash -n
shellcheck scripts/ops/*.sh scripts/build/*.sh  # If shellcheck available
scripts/test/run-tests.sh
scripts/build/quality_gate.sh
```

### Batch 5: Refresh Nix

**Steps:**
1. `flake.nix`: add formatter, `shellcheck`, `shfmt`, `jq` to dev shell
2. Add `checks` target for shell syntax validation
3. `objc-jupyter-wasm/flake.nix`: expose only active packages, document compatibility aliases
4. `objc-jupyter-wasm/nix/kernel-wasm.nix`: factor repeated compile invocations
5. `objc-jupyter-wasm/nix/libobjc2-wasm-full.nix`: move inline C stubs to checked-in source/patch files
6. Delete: `libobjc2-real-subset.nix`, `wasi-sysroot.nix` (unused by current flake)
7. `tooling/test-audit-validator/flake.nix`: add Go test checks

**Validation:**
```bash
nix flake check
nix flake check objc-jupyter-wasm
nix flake check tooling/test-audit-validator
```

### Sprint 4 Validation Gate

After all 5 batches:
```bash
# Shell syntax
git ls-files '*.sh' | xargs -n1 bash -n

# JS syntax
node --check scripts/docs/generate_xrpc_coverage_report.cjs
node --check scripts/docs/generate_xrpc_next_steps.cjs

# Quality gates
scripts/test/run-tests.sh
scripts/build/quality_gate.sh

# Nix
nix flake check
nix flake check objc-jupyter-wasm

# Stale path scan
rg -n '/Users/jack/Software/garazyk|ATProtoPDS/Sources|NSPds|build-linux/bin' scripts docs/scripts .opencode/tools examples objc-jupyter-wasm
```

---

## Sprint 5: OAuth2 Scalability + Provider Migration

**Deciduous Goal:** OAuth2 Overhaul plan (dazzling-shiny-willow)
**Estimated Duration:** 5-7 days
**Prerequisite:** Sprint 2 (A3+A4 must be done — session access must be correct before persistence)
**Priority Reason:** In-memory sessions are lost on restart; no horizontal scaling possible; OAuthProviderServer migration is the path to production OAuth2

### B1: Extend OAuthProviderStorage for Sessions

**Target:** `OAuthProviderProtocols.h` (480 lines), `PDSAuth.h/.m` (499 lines), `OAuth2.h/.m` (1790 lines)

**Steps:**
1. Add session methods to `OAuthProviderStorage` protocol (see plan for 7 method signatures)
2. Implement in `PDSAuthStorage`:
   - In-memory mode (testing): NSMutableDictionary with serial queue
   - SQLite mode (production): port schema from `PDSSQLiteSessionStorage`
3. Add `id<OAuthProviderStorage> storage` property to `OAuth2Server`
4. Replace all `self.activeSessions[...]` with `self.storage` calls
5. Deprecate `activeSessions` property
6. Keep `sessionQueue` for atomicity (check-then-mutate still needs queue protection)

**Validation:**
- `AllTests` — all OAuth2 tests pass
- Restart PDS → sessions survive (SQLite mode)
- Concurrent session creation → no corruption

### B2+B3: De-static Remaining Globals

**B2:** Already done in Sprint 2 A2 (pending consents, passkey challenges)

**B3 Steps:**
1. Move `sClientMetadataCache` → `_clientMetadataCache` (instance variable on OAuth2Handler)
2. NSCache is already thread-safe — no queue needed

**Validation:**
- `AllTests` — OAuth2 tests pass
- Multiple OAuth2Handler instances can coexist (test isolation)

### C1: Complete PDSAuth Protocol Implementations

**Target:** `PDSAuth.h/.m`, new files

**Steps:**
1. **PDSAuthClientRegistry** — Wire to PDSDatabase for registered client lookup. Add URL discovery (fetch client metadata from HTTPS client_id). Add `client:supportsAuthMethod:` and `clientIDFromJWTAssertion:error:`. Port 3-tier validation from OAuth2Handler.
2. **PDSAuthUserAuthenticator** — Wire to PDSAccountService for credential verification. Port sign-in logic from OAuth2Handler.
3. **PDSAuthDIDResolver** — New class wrapping DIDResolver.
4. **PDSAuthHandleResolver** — New class wrapping HandleResolver.

**New files:**
- `Auth/PDS/PDSAuthDIDResolver.h/.m`
- `Auth/PDS/PDSAuthHandleResolver.h/.m`

**Validation:**
- `AllTests` — OAuth2 tests pass
- OAuth2 flow works through PDSAuth adapters

### C2: Wire OAuthProviderServer into OAuth2Handler

**Target:** `OAuth2Handler.h/.m`, `PDSHttpOAuthRoutePack.m`

**Steps:**
1. Add `OAuthProviderServer *oauthProvider` property to OAuth2Handler
2. Add conditional dispatch in 5 handler methods (see plan table in dazzling-shiny-willow.md)
3. Create OAuthProviderServer with PDSAuth adapters in `PDSHttpOAuthRoutePack.m`
4. Set on handler

**Validation:**
- `AllTests` — OAuth2 tests pass with both backends

### C3: Feature Flag + Shadow Mode

**Steps:**
1. Add `PDS_USE_OAUTH_PROVIDER` env var (or PDSConfiguration property)
2. Default: off — OAuth2Server remains active
3. Shadow mode: both servers process, OAuthProviderServer results logged but not returned
4. Compare outputs for parity

**Validation:**
- Shadow mode runs for 24h with no discrepancies

### C4: Delete OAuth2Server

**Steps:**
1. Remove `OAuth2Server` class from `OAuth2.h/.m`
2. Remove `oauthServer` property from OAuth2Handler
3. Remove `activeSessions`, `authorizationCodes`, `sessionQueue`, `authorizationQueue`
4. Clean up `OAuth2.m` — keep only data models if still used
5. Full grep for `OAuth2Server` references — remove all

**Validation:**
- `AllTests` — all tests pass
- No references to `OAuth2Server` remain in codebase

### Sprint 5 Validation Gate

```bash
# Full OAuth2 test suite (13 test classes)
./build/tests/AllTests --filter "OAuth*"

# Session persistence test
# 1. Start PDS, create OAuth session
# 2. Restart PDS
# 3. Verify session still valid

# Shadow mode comparison
PDS_USE_OAUTH_PROVIDER=shadow ./build/bin/kaszlak serve --config test-config.yaml
# Run OAuth2 flows, check logs for discrepancies
```

---

## Sprint 6: Germ Protocol E2EE Phases 4-6

**Deciduous Goal:** #1405
**Estimated Duration:** 3-4 days
**Prerequisite:** None (independent)
**Priority Reason:** Phases 1-3 are complete; remaining work is integration and UX

### Phase 4: Scenario Test + Integration

**Target:** `scripts/scenarios/scenarios/`

**Steps:**
1. Create scenario test for vanilla chat + Germ swap (Node #1416)
   - Test: two users start with vanilla chat, one enables Germ, messages upgrade to E2EE
   - Verify: plaintext messages before swap, ciphertext-only after swap
2. Add Germ service config (Node #1417)
   - GermRuntime runs on port 8082
   - Add to `scripts/scenarios/config/` and Docker compose
3. Add ChatService mode field (Node #1418)
   - ChatService needs to know whether a conversation is vanilla or Germ-encrypted
   - Add `mode` field to conversation model

**Validation:**
- `scripts/scenarios/run_scenario.py --scenario 06,11` — chat and OAuth scenarios pass
- New Germ scenario passes all steps

### Phase 5: Admin UI Germ Tab

**Target:** `UIServerRuntime.m`, `UIBackendClient.m`

**Steps:**
1. Add Germ tab to admin shell (Node #1419)
2. Display: active Germ declarations, mailbox status, identity verification results
3. Actions: view declaration records, verify identity chains, inspect mailbox addresses
4. Add XRPC client methods to UIBackendClient for Germ endpoints

**Validation:**
- Admin UI loads Germ tab
- Germ data displays correctly

### Phase 6: End-to-End Verification

**Steps:**
1. Full E2EE round-trip: create account → declare Germ identity → send E2EE message → receive and decrypt
2. Verify mailbox single-read semantics
3. Verify identity succession proof chains
4. Verify ciphertext-only storage (server cannot read messages)

**Validation:**
- All 30+ Germ tests pass
- E2EE round-trip succeeds

---

## Sprint 7: Platform-Native Integration Phases 2-4

**Deciduous Goal:** #1372
**Estimated Duration:** 3-4 days
**Prerequisite:** None (independent, Phase 1 is complete)
**Priority Reason:** Service lifecycle management is needed for production reliability

### Phase 2: launchd/systemd Service Lifecycle

**Steps:**
1. Create `com.garazyk.kaszlak.plist` for macOS launchd
   - KeepAlive, RunAtLoad, StandardOutPath, StandardErrorPath
   - SIGHUP for config reload, SIGUSR1 for status
2. Create `kaszlak.service` for Linux systemd (already exists at `/etc/systemd/system/kaszlak.service` — move into repo under `scripts/ops/production/`)
3. Add `scripts/ops/production/install-service.sh` — detects platform, installs appropriate service file
4. Add graceful shutdown: SIGTERM → drain connections → exit

**Validation:**
- `launchctl load` / `systemctl start` → PDS starts
- SIGHUP → config reload without restart
- SIGTERM → graceful shutdown

### Phase 3: Exit Codes

**Steps:**
1. Define exit code constants in `PDSTypes.h`:
   - `PDS_EXIT_SUCCESS = 0`
   - `PDS_EXIT_CONFIG_ERROR = 1`
   - `PDS_EXIT_DB_ERROR = 2`
   - `PDS_EXIT_BIND_ERROR = 3`
   - `PDS_EXIT_SIGNAL = 4`
2. Replace all `exit(1)` calls with specific exit codes
3. Document exit codes in man page or `--help`

**Validation:**
- Invalid config → exit code 1
- Port in use → exit code 3
- SIGTERM → exit code 0

### Phase 4: Structured Logging

**Steps:**
1. Define log format: JSON structured logs with timestamp, level, component, message, fields
2. Create `PDSLogFormatter` that outputs structured JSON to stderr
3. Replace `NSLog` calls with structured log entries
4. Add `--log-level` CLI flag: debug, info, warn, error
5. Add `--log-format` CLI flag: json, text

**Validation:**
- `kaszlak serve --log-level=debug --log-format=json 2>log.json`
- `jq . log.json` → valid JSON array
- Filter by component: `jq 'select(.component=="OAuth2")' log.json`

---

## Sprint 8: Documentation

**Deciduous Goals:** Docs Deslop + Docs Overhaul (Nodes #889-893)
**Estimated Duration:** 5-7 days
**Prerequisite:** None (independent)
**Priority Reason:** Documentation is the entry point for new contributors; current docs have AI slop

### Deslop Phase 1: High-Visibility & Core Concepts

**Steps:**
1. Rewrite `docs/index.md` and `docs/README.md`
2. Rewrite `docs/01-getting-started/` (Architecture Overview, Request Lifecycle)
3. Rewrite `docs/02-core-concepts/` (ATProto Basics, IPLD, Cryptography)
4. Apply 10 Core Rules from `deslop` skill: directness, rhythm, trust, authenticity, density
5. Grep check for banned phrases: `ecosystem`, `leverage`, `seamless`, `robust`, `not just`, `Here's the thing`

### Deslop Phase 2: Application Layer & Tutorials

**Steps:**
1. Rewrite `docs/03-application-layer/` and `docs/04-network-layer/`
2. Deslop `docs/10-tutorials/` — remove pedagogical voice, no hand-holding
3. Verify: 1-10 dimension scoring >35/50 on revised passages

### Deslop Phase 3: Reference & Operational Docs

**Steps:**
1. Sweep `docs/05-database-layer/` through `docs/09-platform-compatibility/`
2. Clean up `docs/TESTING.md`, `DEPLOYMENT_GUIDE.md`
3. Final grep check for banned phrases

### Docs Overhaul Phase 1: Foundation (Node #889)

- Update `docs/03-application-layer/` for microservice split
- Update `docs/09-platform-compatibility/` for VitePress migration
- Document `PDSCloudStorageBlobProvider`
- Verify microservice boundaries

### Docs Overhaul Phase 2: Network & API (Node #890)

- Document moderation migration (`com.atproto.admin` → `tools.ozone`)
- Cleanup legacy endpoints
- Add OAuth2/DPoP endpoint details
- Run `atproto-coverage-audit`

### Docs Overhaul Phase 3: Data & Storage (Node #891)

- Document migrations V5-V8
- Document FTS5 search schema and `OzoneSubjectsSchema`
- Run `sqlite-sql-best-practices` audit

### Docs Overhaul Phase 4: Tutorials (Node #892)

- Cross-reference Tutorial 10
- Review all tutorials for pattern consistency
- Dry-run tutorials

### Docs Overhaul Phase 5: QA (Node #893)

- Run `python3 scripts/test-doc-links.py`
- Update `GLOSSARY.md` and `index.md`
- Final copy audit
- Build docs: `./scripts/build/build-docs.sh`

### Sprint 8 Validation Gate

```bash
# Banned phrase check
rg -i 'ecosystem|leverage|seamless|robust|not just|Here.s the thing' docs/

# Link validation
python3 scripts/test-doc-links.py

# Build
./scripts/build/build-docs.sh
```

---

## Sprint 9: Security Audit Vertical Slices

**Deciduous Goal:** Security Audit (from plan document)
**Estimated Duration:** 5-7 days
**Prerequisite:** Sprint 1 (P0 fixes must be done first — audit should find NEW issues, not re-find known ones)
**Priority Reason:** Deep verification after P0 fixes; web-search-verified findings only

### Slice 1: Cryptography & Auth

**Steps:**
1. Run `./.agents/skills/objc-security-audit/scripts/scan_crypto.sh . /tmp/audit-crypto`
2. Verify each finding with web search (Apple Developer Docs, OWASP, ATProto spec)
3. Log verified findings to deciduous

### Slice 2: SQLite & Injection

**Steps:**
1. Run `./.agents/skills/objc-security-audit/scripts/scan_sql_injection.sh . /tmp/audit-sql`
2. Verify against SQLite documentation
3. Log findings

### Slice 3: Secrets & Log Redaction

**Steps:**
1. Run `scan_secrets.sh` and `scan_log_redaction.sh`
2. Cross-reference with ATProto credential handling specs
3. Log findings

### Slice 4: Web UI & Frontend

**Steps:**
1. Manual review of HTML/JS/CSS against `web-ui-audit` checklists
2. Verify XSS/CSRF payload viability
3. Log findings

### Slice 5: Synthesis

**Steps:**
1. Compile all verified findings into `SECURITY_REPORT.md`
2. Close all deciduous goals
3. Create remediation plan for any new findings

---

## Sprint 10: Fuzzing Phases 3-5

**Deciduous Goal:** Fuzzing Improvements (from narrative)
**Estimated Duration:** 3-5 days
**Prerequisite:** None (independent)
**Priority Reason:** Phases 1-2 complete; seed corpus and custom mutators are the next high-ROI steps

### Phase 3: Seed Corpus Enrichment

**Steps:**
1. Create minimal valid examples for each fuzzer:
   - CBOR: major types 0-7, indefinite-length, nested structures
   - JWT: valid tokens, expired tokens, missing fields, signature variations
   - HTTP: header variants, chunked encoding, multipart bodies
   - MIME: PNG, JPEG, GIF, WebP headers with valid magic numbers
2. Place in `fuzzing/corpus/` subdirectories
3. Run each fuzzer for 100 iterations against new corpus

### Phase 4: Custom Mutator Design

**Priority:** JWT and HTTP (highly structured inputs)

**Steps:**
1. JWT mutator: decompose into header.payload.signature, mutate parts independently
2. HTTP mutator: decompose into method/path/headers/body, fuzz each structural element
3. Evaluate libprotobuf-mutator vs hand-written mutators

### Phase 5: CI/CD Integration

**Steps:**
1. Create GitHub Actions workflow for continuous fuzzing
2. Run each fuzzer for 5 minutes on push
3. Collect coverage, store results/crashes
4. Add regression test script

---

## Timeline Summary

| Sprint | Duration | Dependencies | Can Parallel With |
|--------|----------|-------------|-------------------|
| 1: Security P0 | 3-5 days | None | Sprint 4, 6, 8 |
| 2: OAuth2 Concurrency | 3-4 days | Sprint 1 | Sprint 4, 6, 8 |
| 3: Refactoring Phase 1 | 4-5 days | Sprint 2 | Sprint 4, 6, 8 |
| 4: Script & Nix Hygiene | 3-4 days | None | Sprints 1-3, 6, 8 |
| 5: OAuth2 Scalability | 5-7 days | Sprint 2 | Sprint 6, 7, 8 |
| 6: Germ E2EE | 3-4 days | None | Sprints 1-5, 7-8 |
| 7: Platform-Native | 3-4 days | None | Sprints 4-6, 8 |
| 8: Documentation | 5-7 days | None | Sprints 1-7 |
| 9: Security Audit | 5-7 days | Sprint 1 | Sprint 6-8 |
| 10: Fuzzing | 3-5 days | None | Sprints 1-9 |

**Critical path:** Sprint 1 → Sprint 2 → Sprint 3 → Sprint 5 (OAuth2 full overhaul)
**Total estimated:** 37-53 days of work, but with parallelism can be compressed to ~25-30 days

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| SubscribeReposHandler @synchronized replacement causes deadlock | High | Defer until full lock-order audit; keep @synchronized as safe default |
| OAuth2Server deletion breaks downstream consumers | High | Shadow mode (C3) for one full release cycle before deletion |
| AppView schema fix requires data migration | Medium | Add migration with backward-compatible fallback |
| Script moves break CI pipelines | Medium | Leave compatibility wrappers during deprecation window |
| Germ E2EE scenario test requires running mailbox service | Low | Add GermRuntime to Docker compose scenario config |
| Documentation rewrite changes technical meaning | Medium | Git revert per file; technical review before merge |
