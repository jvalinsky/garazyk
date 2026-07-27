---
title: Security and Protocol Correctness
status: active
last_verified: 2026-07-26
---

# Security and Protocol Correctness

## S1. Duplicate XRPC ownership

**Status: complete (verified 2026-07-26).** All three previously-duplicated
registrations have been resolved:

- `app.bsky.graph.getListMutes` — registered exactly once in
  `XrpcAppBskyGraphPack.m:76`.
- `app.bsky.graph.getListBlocks` — registered exactly once in
  `XrpcAppBskyGraphPack.m:125`.
- `app.bsky.labeler.getServices` — registered once via `registerMethod` in
  `XrpcAppBskyPack.m:111`; a parallel `addRoute:path:handler:` call in
  `AppViewXRpcRoutePack.m:211` uses a different routing mechanism (HTTP server
  route vs. XRPC dispatcher) and is not a duplicate.

Runtime enforcement exists: `XrpcHandler.m:101-108` throws
`NSInternalInconsistencyException` on any duplicate registration. Two
characterization tests cover same-file and cross-pack duplicates
(`XrpcMethodRegistryCharacterizationTests.m:134,155`). CI enforces
no-scoped-duplicates via `generate_xrpc_coverage_report.cjs --fail-on-duplicates`
in `.github/workflows/ci.yml:90`.

## S2. Canonical lexicon generation

**Status: complete (verified 2026-07-26).** Both generators now read from the
single canonical root `Garazyk/Resources/lexicons/` (557 JSON files, 13
top-level namespaces):

1. **Canonical root chosen** — `Garazyk/Resources/lexicons/` is the sole
   source of truth. Both the TypeScript client generator
   (`packages/gruszka/scripts/generate.ts`) and the Objective-C NSID constants
   generator (`scripts/generate_nsid_constants.ts`) read from it.

2. **Fail-on-empty** — The NSID generator fails before overwriting output when
   the inventory or endpoint set is empty. The TypeScript generator's
   `generate_test.ts` verifies deterministic output against the checked-in
   artifact.

3. **Deterministic output** — Both generators produce deterministic output.
   The NSID constants cover 419 endpoints; the TypeScript artifact covers 519
   lexicons.

4. **CI drift check** — The NSID constants generator has a CI drift check
   (`nsid-constants-drift-check` job in `.github/workflows/ci.yml:19-42`) that
   runs `--check` on every push/PR. The same CI job also runs the raw-literal
   lint (`nsid_registration_literal_check.ts`). The TypeScript client generator's
   drift detection runs via `deno task test` (which includes
   `generate_test.ts`'s artifact-matching assertion), not a separate CI job.

## S3. Truthful XRPC coverage

**Status: complete (report-only).** Split metrics report built at
`reports/xrpc_split_metrics.md` (2026-07-17). Six separate metrics published:
registered (213), schema-covered (207), behavior-verified (124), static routes
(213), dynamic AppView routes (0), Garazyk extensions (0). 89 endpoints
without behavior verification identified. Script:
`scripts/docs/generate_xrpc_split_metrics.cjs`.

Semantic fixes applied (2026-07-17):

- `chat.bsky.actor.declaration` phantom query removed from
  `XrpcChatBskyActorPack.m` — lexicon declares type "record", not "query".
- `app.bsky.labeler.getServices` now validates required `dids` parameter and
  returns 400 on missing/empty; spurious `cursor` field removed from response.
  Both registration sites fixed (`XrpcAppBskyPack.m`, `AppViewXRpcRoutePack.m`).
  Tests updated.
- `com.atproto.admin.getRecord` uses `ATURI` class for proper AT-URI parsing
  instead of naive string splitting; explicit compatibility policy documented
  in code comment.

## S4. Absolute HTTP deadlines

**Status: complete (verified 2026-07-26).** `HttpConnectionIOCoordinator`
implements two independent timeout mechanisms (header, lines 60-183):

1. **Idle header deadline** (default 30s) — a per-receive-cycle timer armed
   before each `connection receive` call. If no bytes arrive within the window,
   the connection is terminated. Cancelled every time data arrives. Implemented
   at `HttpConnectionIOCoordinator.m:208-226`.

2. **Aggregate header deadline** (default 30s) — a wall-clock timer set when the
   first header byte arrives (`headerStartTime`). It does **not** reset on
   subsequent trickle bytes. If the total time from first byte to header
   terminator (`\r\n\r\n`) exceeds the timeout, the connection is terminated.
   Implemented at `HttpConnectionIOCoordinator.m:228-244,288-291`.

Both mechanisms use generation counters to safely invalidate stale
`dispatch_after` blocks. A `didEmitTerminalTimeout` flag ensures at most one
timeout error per coordinator instance. The designated initializer accepts
explicit `idleHeaderTimeout:` and `aggregateHeaderTimeout:` values.

Characterization tests:

- `testIdleHeaderDeadlineTerminatesStalledReceiveExactlyOnce` — 50ms idle
  timeout, verifies exactly one error emitted.
- `testAggregateHeaderDeadlineDoesNotResetForTrickleInput` — 4 single-byte
  chunks at 0/30/60/90ms with 140ms aggregate timeout; verifies the aggregate
  deadline fires (not idle), confirming trickle bytes do not reset the clock.
- `testCompletedSplitHeaderDoesNotApplyAggregateDeadlineToBody` — verifies
  body arrival after header completion is not subject to the aggregate deadline.

## S5. Functional federation and lifecycle checks

The May adversarial scenarios exist, but some exercise only Deno parsers. Add
tests that send malformed or oversized data through the live Objective-C ingress
boundary and assert PDS, Relay, and AppView health afterward.

Firehose tests must set low pending-send and byte limits in the scenario
topology so `ConsumerTooSlow` is deterministic and independent of OS TCP
buffering. Production defaults stay unchanged.

Account lifecycle tests must follow the current specifications:

- downstream services stop redistributing inactive accounts;
- `active` controls visibility while `status` refines the state;
- event sequences increase monotonically and persisted cursors resume without
  gaps;
- suspension and takedown behavior is tested at both write and read boundaries.

### Backpressure and adversarial ingress (2026-07-17)

**Complete.** `SubscribeReposHandler`'s pending-send/byte limits
(`maxPendingSendsPerConnection`/`maxPendingBytesPerConnection`) were already
configurable via `PDS_FIREHOSE_MAX_PENDING_SENDS`/`_BYTES` env vars, and
`docker/local-network/docker-compose.yml` already set them low
(1 / 10000) for its topology — the gap was that the topology-compiler preset
(`scripts/scenarios/topologies/garazyk-default.json`) and `--binary` mode
(`packages/hamownia/binary_services.ts`) did not, and that scenario
33 (`33_tortoise_consumer.ts`) slept a blind 90 seconds hoping OS-level TCP
buffering would eventually trip `ConsumerTooSlow`, rather than checking
early. Added the same two env vars to the topology JSON and to
`binary_services.ts`'s `"pds"` case (as a default, overridable via the
existing `options.env` extension point), and rewrote scenario 33 to poll
for the connection closing instead of sleeping — it now passes in ~1-2s
instead of ~95s, deterministically, verified over multiple runs via
`deno run -A packages/hamownia/cli.ts run --binary --setup --teardown 33`.
(Note: `WebSocketConnection.closeWithCode:` clears the outbound message
queue before writing the close frame, so the server's `#error` frame
naming `ConsumerTooSlow` is not reliably flushed before the abrupt close —
the scenario checks for it as a soft/informational signal, not a hard
assertion; the functionally-important behavior, the connection actually
being dropped, is the hard assertion and is now reliable.)

New scenario 95 (`95_adversarial_ingress.ts`) closes the gap the existing
adversarial scenarios left: 65 (firehose fuzzing) and 66 (CBOR bombs) only
ever exercise the Deno-side firehose *client* parser, never the live PDS;
64 (MST poisoning) hits a live endpoint but with well-formed, merely
numerous/colliding JSON. Scenario 95 sends genuinely malformed
(truncated-JSON), oversized (10MB record body), and junk-binary
(`uploadBlob`) payloads directly at the live `com.atproto.repo.*`
endpoints and asserts a 4xx (not 5xx/crash) plus a passing health check
after each. Verified green via
`deno run -A packages/hamownia/cli.ts run --binary --setup --teardown 95`.

### Account lifecycle (2026-07-17) — partially verified, real gaps found

A focused code audit (not just testing) found the write/read enforcement
boundary on the PDS itself works correctly and is already proven by
scenario 55 (`rejectUnavailableRepoDid`/`rejectUnavailableSyncDid` in
`XrpcRepoPack.m`/`XrpcSyncPack.m`, gated on `account.status` and
`admin_takedowns.applied`). One concrete bug was found and fixed:
`com.atproto.sync.getRepoStatus` (`XrpcSyncPack.m`) hardcoded
`active: true` unconditionally, ignoring both `account.status` and
takedown state — a takendown/deactivated account's own status endpoint
lied about being active. Fixed to compute `active`/`status` from both
signals, matching the `#account` lexicon's `knownValues`; covered by a new
test, `AdminAuthSyncTests testApplicationSyncGetRepoStatusReturnsInactiveAfterTakedown`.

Two items from workstream 01 S5's list are **not implemented**, not just
untested — closing them is real feature work, out of scope for a test-writing
slice, and is filed as a follow-up rather than rushed here:

- **"Downstream services stop redistributing inactive accounts" — not
  wired at all.** User-initiated deactivate/activate does post
  `PDSAccountActivatedNotification`/`PDSAccountDeactivatedNotification`,
  which `SubscribeReposHandler` observes and turns into a real `#account`
  firehose event. Admin-initiated takedown
  (`PDSAdminService.takeDownAccount:reason:error:`) posts no notification
  at all — `SubscribeReposHandler`'s `-broadcastAccountTakedown:` exists
  but has zero production callers anywhere in the codebase. Even when an
  `#account` event *is* emitted, `RelayClient`'s
  `-firehoseSubscription:didReceiveAccountEvent:` only updates
  `currentSeq` and never forwards it — `RelayClientDelegate` doesn't even
  declare an account-event method, so `AppViewIngestEngine` has no hook to
  implement one. `RelayRepoStateManager` has the right model
  (`RelayRepoStatus`: Active/Desynchronized/InProgress/Throttled/Tombstoned)
  and the right methods (`-handleAccountEventForRepo:status:` etc.) but
  zero callers anywhere — dead code. `RelayDownstreamHandler` does
  passively re-broadcast an incoming `#account` event to its own
  subscribers, so simple passthrough works; there is no enforcement layer
  anywhere that stops indexing/redistributing an inactive account's
  records.
- **Gap-free cursor resume across a real disconnect/reconnect — untested.**
  `FirehoseProtocolSession` monotonically increments one sequence counter
  shared across all event types and correctly seeds from the persisted max
  on restart (`SubscribeReposHandler.m:1179-1200`); `RelayUpstreamManager`
  tracks per-upstream sequence and reconnect backoff. But no test (ObjC or
  Deno) proves a live consumer reconnecting with `?cursor=N` mid-stream
  resumes with no gap and no duplicate — `09_firehose_streaming.ts` has no
  cursor/resume/reconnect references at all.

Implementing the downstream-propagation wiring (admin takedown →
notification → firehose event; `RelayClientDelegate` account-event method;
`AppViewIngestEngine` and `RelayRepoStateManager` actually enforcing it) is
a moderation-relevant, multi-file feature change that deserves its own
scoped, reviewed implementation — not something to fold into a
verification slice. Filed as a follow-up. The cursor-resume test is
smaller and more self-contained; left as the next actionable item here.

**Both gaps closed (2026-07-17).** Cursor resume: scenario 96
(`96_firehose_cursor_resume.ts`, `6387245a8`) proves gap-free resume
across a live disconnect/reconnect (no gap, no duplicates, monotonic,
disconnect-window records delivered; 10/10 structured steps), enabled by
the `closeForUpgrade` WebSocket-handoff fix (`80f5a56e6`). Downstream
propagation: `28641e671` wires admin takedown/reinstate to the account
notifications so `SubscribeReposHandler` emits real `#account` events,
adds the `RelayClientDelegate` account-event method, and has
`AppViewIngestEngine` durably persist and forward account events;
`a3f8d3c53` closes the last hop (`RelayUpstreamManager` forwards account
events downstream). Scenario 97 (`97_account_takedown_propagation.ts`,
`7bde0e0b6`) proves the takedown chain E2E. - **AppView un-indexing on takedown — Complete (2026-07-24).** `RelayRepoStateManager`'s status-tracking model is now integrated with AppView's indexing pipeline to un-index records when an account is taken down.

### Gated Objective-C coverage into CI

Twenty-nine `AllTests` classes are gated (now via the test binary's
`--gated=run` flag; the old `PDS_RUN_INTEGRATION_TESTS`/`PDS_RUN_SOCKET_TESTS`
env vars were replaced) and are skipped in the default run. Before folding
them into CI, they must pass. (Folded here from the retired 2026-07-13
remediation plan, WS5.)

**Repaired (2026-07-17).** The 2026-07-16 baseline (full `AllTests
--gated=run`, 3454 tests) measured 76 assertion failures across 11 gated
classes, each reproducible when the class is run in isolation — suite rot,
not cross-suite interference. All 11 are now fixed, each with an isolated
root cause:

- `ATProtoMediaServiceRuntimeTests` (7) and `XrpcIntegrationTests` (18) both
  registered routes onto the process-wide `[XrpcDispatcher sharedDispatcher]`
  singleton from a `start`/`setUp` that XCTest calls more than once per
  process, hitting "Duplicate XRPC handler registration"; switched both to a
  private `[[XrpcDispatcher alloc] init]` instance (a no-op behavior change
  for `jelcz`, the only production caller, which only ever starts one
  runtime per process).
- `FollowersCountIntegrationTests` (1): `PDSRecordService`'s single-record
  `putRecord:` path only extracted `subject_did` when a follow/block
  record's `subject` was a plain string, unlike the batch and read-side
  paths, which already handled the `{"did": ...}` object form too — added
  the missing case so follower counts see both.
- `PDSWebSocketServerTests` (1): the test's mock `ATProtoNetworkListener`
  never set a nonzero `port` on start, unlike the real listener it stands
  in for; `testServerStartsAndPortIsNonzero` could never observe the port
  becoming available. Fixed the mock, not the server.
- `PDSApplicationTests` (2): `testDefaultPortValues` read `httpPort`/`wsPort`
  before calling `startWithError:`, but ports are intentionally ephemeral
  (0) under test config until the HTTP server actually binds; added the
  missing `start` call to match this file's other port-assertion tests.
- `CommitChainTests` (3) and `FirehoseIntegrationTests` (13): both construct
  a standalone `SubscribeReposHandler` and drive it through a mock
  connection instead of a real WebSocket server, but only `-startOnPort:`
  (which they skip) calls `-startObservingNotifications`; without it,
  `-handleRecordChange:` never fires and no commit is ever broadcast. Added
  the missing call in both tests.
- `OAuthIntegrationTests` (5): seeded authorization codes with scope
  `"atproto:identify"`, a literal string matching an `OAuth2ScopeIdentify`
  constant that's declared in `OAuth2.h` but wired up nowhere — the granular
  OAuth-scopes feature these constants anticipate is still the "Decision
  needed" P1 item in the priority table, not implemented. `OAuth2ScopeIsValid`
  correctly requires the bare `atproto` scope token; fixed the test to
  request `OAuth2ScopeAtproto` instead of inventing a feature.
- `OAuth2EndpointTests` (6): `setUp` never registered `test-client` as a
  known OAuth client or seeded a matching account, so every request that
  expected success (revoke, token exchange) hit `invalid_client`/"Account
  handle is nil" before reaching the behavior under test — the requests
  that expected rejection happened to still get rejected, masking the gap.
  Added client + account fixtures and a real PKCE/DPoP-bound authorization
  code, mirroring `OAuthIntegrationTests`.
- `UILabIntegrationTests` (14): every login/logout test predates the U3
  CSRF hardening (double-submit `ui_admin_nonce` cookie + `X-UI-Admin-Nonce`
  header) and never sent a nonce, so `POST /admin/login` and
  `/admin/logout` uniformly hit `invalid_csrf_token`. Added a
  `csrfHeadersFromPath:` test helper that fetches a fresh nonce from a GET
  first. Separately, `testGetLabContainsLabConfig` checked for a literal
  `LAB_CONFIG` string that the U2 CSP hardening moved out of the inline
  page into `<meta>` tags read by the external `/js/lab.js`; updated the
  assertion to match.
- `EmailIntegrationTests` (6): `setenv("PDS_EMAIL_PROVIDER", "mock", 1)` in
  `setUp` had no effect because `ATProtoServiceConfiguration.sharedConfiguration`
  is a `dispatch_once` singleton realized once per process and never
  re-reads env vars afterward; by the time this test ran, an earlier test
  class had already forced its creation with the provider defaulted to
  `"none"`. Built a standalone `ATProtoServiceConfiguration` + `PDSApplication`
  instead of going through the stale shared instance.

A full `AllTests --gated=run` pass (2026-07-17) is green: 3454 tests, 0
failures. `E2EDockerTests` self-skips without a reachable docker stack (as
before). `--gated=run` is now the default in `CMakeLists.txt`'s `add_test`
(so `ctest` runs it), `scripts/test/run-tests.sh`, and
`scripts/test/run-asan-tests.sh`.

**Known flake (pre-existing, not one of the 11 above) — fixed:**
`ATProtoVideoTranscoderIntegrationTests/testTranscodeInvalidURLError`
SIGSEGV'd once under `ctest -R '^AllTests$'` on 2026-07-17
(`EXC_BAD_ACCESS`/`objc_storeStrong` inside the test's own frame — a
use-after-free, not a hang or OOM). Root cause: the synchronous
`transcodeVideoAtURL:toQuality:error:` wrapper in
`Garazyk/Sources/Video/VideoTranscoder.m` wrote into the caller's
`NSError **` out-parameter directly from inside the background-queue
completion block, racing that queue's autorelease pool drain against the
caller reading `*error` after `dispatch_semaphore_wait` returned. Fixed
by capturing the error into a `__block __strong` local inside the block
and writing `*error` only after the wait returns, on the caller's thread;
this also let us drop the `-Wblock-capture-autoreleasing` suppression
that had been papering over the same spot.

Two direct-binary and one ctest retry ran clean immediately after the
original crash was reported, so it reproduced intermittently rather than
reliably — consistent with a race.

**Separate, still-open flake:** three other crash reports from the same
day (2026-07-16, 21:47, 22:12, 22:15), previously misattributed to this
same signature, are actually a distinct bug: a null-pointer SIGSEGV
(`EXC_BAD_ACCESS`/`KERN_INVALID_ADDRESS` at `0x0`) inside
`-[PDSDatabase(Private) safeExecuteSync:]` (`PDSDatabase.m:48`), called
from `-[PDSDatabase openWithError:]` (`PDSDatabase.m:122`) — seen once
from `PDSDatabaseBlobsTests/testGetBlobsForDidWithPagination` (21:47) and
twice from `PDSDatabaseLRUTests setUp` (22:12, 22:15). Undiagnosed;
tracked as a follow-up. Possibly related to disk pressure given
`PDSDatabase`'s use of SQLite, but not yet confirmed.

**Open path hardened (2026-07-23), flake watch continues.** Auditing
`-[PDSDatabase openWithError:]` for this flake found three concrete
contract bugs on the same code path, all fixed: (1) a failed
`sqlite3_open` never closed SQLite's error-holding handle and left `_db`
non-NULL (documented SQLite contract violation; leak plus a stale handle
that later close/reopen paths would act on), and would crash boxing
`sqlite3_errmsg` if open failed with a NULL handle (OOM); (2)
`createSchema:` failure — the exact `SQLITE_FULL` disk-pressure shape —
was ignored, so `openWithError:` returned YES with `isOpen = YES` on a
database with missing tables, failing every later query obscurely; now
fails closed like the migration branch; (3) `setWalMode:`/
`setPerformanceOptimizations:` failures wrote `*error` alongside a YES
return, violating the error-only-on-NO convention; now logged locally and
non-fatal. New registered suite `PDSDatabaseOpenFailureTests` pins the
failed-open cleanup (NO + error + NULL handle + safe re-open attempt);
the database/actor-store suites stay green (72 targeted tests). The
original 0x0 crash never reproduced, so the flake is **mitigated but
open as a watch item** — its most plausible mechanisms on this path are
closed (2026-07-26 verification).

**Regression discovered 2026-07-19 (during phase 8), fully root-caused and
repaired 2026-07-22.** A full `AllTests --gated=run` was no longer clean —
12 suites failed, roughly 68 individual assertion failures, contradicting
the 2026-07-17 "3454 tests, 0 failures" baseline above. None of the
failing suites or files were touched by phase 8 (Admin UI/dashboard
accessibility). Each suite had its own isolated root cause (theorized
2026-07-19 as mostly DID-format fixture debt; verified 2026-07-22 to be
more varied — several were genuine product bugs, not just stale fixtures):

- **DID-format fixtures (`PDSSQLiteRepositoryTests`).** `+[ATProtoValidator
  validateDID:error:]` requires `did:plc:` identifiers to be exactly 24
  lowercase-base32 characters; fixtures like `kTestDID = @"did:plc:repo123"`
  (7 chars) don't conform, so `-[PDSDatabasePool dbPathForDid:]` refuses
  them. Fixed the fixtures to valid-length DIDs. Two more bugs surfaced
  once the DIDs validated: `recordWithURI:did:did:` hardcoded
  `collection`/`rkey` regardless of the URI passed in (so two records with
  different collections collided), and `PDSSQLiteRepoRepository
  allReposWithError:` was declared in `PDSRepoRepository.h` but never
  implemented — `PDSDatabasePool` already had the working
  `getAllReposWithError:` (cached `knownDids`, falls back to a directory
  walk only when empty); the repository method just never delegated to it.
  Both fixed.
- **`PDSDatabaseAdminAuditTests`:** fixture dictionaries used stale keys
  (`actor`/`subject`/`comment`) that don't match
  `insertAuditLogEntry:`'s real contract (`admin_did`/`subject_type`/
  `subject_id`/`details`) — `admin_did` landed as `NSNull`, tripping the
  column's `NOT NULL` constraint. Fixed the fixtures.
- **`PDSDatabaseModerationTests`:** `createLabel:` never defaulted `cts`
  (NOT NULL, no default) when the caller omitted it — a **real product
  bug**, not just a test gap: `PDSAdminService.createLabel:` only computes
  a fallback `cts` for the *response* dict, never for what's actually
  inserted, so a real `chat.bsky` API caller omitting `cts` would hit the
  same constraint failure. Fixed by stamping `cts` server-side in
  `PDSDatabase+Moderation.m`, matching the pattern already used for
  `created_at` elsewhere. Separately, `activateAccount:` only ever touched
  `accounts.status`, never `admin_takedowns.applied` — so activating an
  account after a takedown left `isAccountTakedownActive:` still reporting
  active takedown. `activateAccount:` has zero production callers today, so
  this was safe to fix directly: it now clears both. Test fixture also
  needed a real `accounts` row (via `createAccount:`) before asserting on
  `accountStatusForDid:`.
- **`PDSDatabaseOAuthClientsTests`:** asserted on `client_name`, a field
  `oauth_clients` has never had a column for (confirmed: not in
  `Schema.m`'s DDL, not in any migration). Fixed the fixtures to assert on
  `redirect_uris`, which the roundtrip actually persists.
- **`AppViewIndexerTests` (`testGroupIndexerIndexGroup`/
  `testGroupIndexerDeleteRecord`):** **real product bug.** AppView's
  `groups`/`group_members` DDL (`AppViewDatabase.m`) used stale column
  names (`id`, `group_id`, `member_did`, `joined_at`) that don't match what
  `AppViewGroupIndexer.m` — the only reader/writer of these two
  AppView-internal tables — actually writes/reads (`uri`, `cid`,
  `group_uri`, `did`, `added_at`). `chat.bsky.group.definition` indexing
  was completely broken (every insert failed with "no such table" / "no
  such column"). Fixed the DDL to match the indexer's contract; no existing
  data to migrate since every write had been failing.
- **`PDSDatabaseWebAuthnTests`:** the test opened a bare `PDSDatabase` via
  `databaseAtURL:` + `openWithError:`, which only runs
  `pdsDatabaseMigrationManager` (V10-V12, the legacy monolithic schema).
  `webauthn_credentials` lives in the *service* schema
  (`PDSSchemaManager.serviceSchemaSQL`), which production only ever applies
  through `PDSActorStore`'s `"__service__"` shard handling (see
  `ServiceDatabases.serviceDatabaseWithError:`) — never through a bare
  `PDSDatabase`. This is test-setup drift, not a production bug: real
  WebAuthn/second-factor callers (`WebAuthnRegistrationHandler.m`,
  `OAuth2Handler.m`, `PDSSecondFactorService.m`) always get their
  `PDSDatabase` by way of `PDSActorStore`, so the service schema is always
  present in production. Fixed the test to open a real `PDSActorStore` for
  `PDSServiceStoreDID` instead of reimplementing its bootstrap sequence.
  One more bug surfaced once the schema existed: `deleteWebAuthnCredential:`
  used the generic `executeParameterizedUpdate:` helper, which only reports
  SQL errors, not match count — deleting a nonexistent credential silently
  "succeeded". Added an explicit `sqlite3_changes()` check.
- **`PDSSequencerAnalyticsCollectorTests`:** two independent bugs.
  `startCollecting` used `dispatch_async`, so `isCollecting` wasn't set by
  the time the method returned — three tests raced the private queue.
  Changed to `dispatch_sync` (the queue is private to this class; no
  reentrancy risk). Separately, `currentSnapshot` never checked
  `self.serviceDatabases` for nil before calling a method on it — Objective-C
  message-to-nil returns zeroed values without touching the error
  out-param, so the "no database configured" case silently returned a
  zero-filled snapshot instead of `nil`. Added an explicit nil guard.
- **`MSTPreorderTests/testRefusesWhenFlagOff`:** not a runner
  attribution bug or cross-test leakage as first suspected — `
  buildMultiLevelTree`'s stopping condition unconditionally calls
  `capturePreorderMSTOnly:`, which itself requires the streamable-CAR flag
  on. Every other test flips the flag on before calling
  `buildMultiLevelTree`; this test intentionally leaves it off (to test
  refusal), so tree construction itself failed before the test ever
  exercised what it meant to test. Fixed by building the tree with the flag
  on, then turning it off before the refusal assertions.
- **`OAuthClientAuthPolicyTests/testValidateRequestParametersClientSecretInNonLegacyRejected`:**
  `+[OAuthClientAuthPolicy legacyOAuthEnabled]` hardcodes `YES` for `DEBUG`
  builds, so the non-legacy `client_secret` rejection path this test wants
  to exercise is unreachable from any DEBUG-compiled test binary. Marked
  `XCTSkip` with the reason recorded in the test; testing the non-legacy
  path meaningfully needs a way to override the flag under test, which is
  a separate follow-up.
- **`ATProtoVideoProcessorTests` (MPEG signature validation):** **real
  product bug.** `validateContentSignature:declaredMimeType:` rejected any
  input under 12 bytes before checking format-specific signatures, even
  though the MPEG/WebM/Ogg checks each only need 4 bytes and already gate
  correctly on their own minimum length. Valid 4-byte MPEG signatures were
  being rejected outright. Removed the blanket 12-byte gate.
- **`AtprotoInteropFixturesTests/testInteropSignatureFixtures` — resolved
  (2026-07-22).** The decision this item was pending: does PLC operation
  verification specifically require low-S (matching the reference
  implementation and the interop fixture), even though DPoP/JOSE/WebAuthn
  correctly don't? Yes — did:plc's own spec defines low-S as part of what
  makes a signature valid, independent of curve, and ADR 0007's blast-radius
  list was wrong to include `PLCAuditor` among the paths that should accept
  both S forms. `PLCAuditor.verifyP256Signature:` now calls
  `[AuthCryptoECDSA isLowS:error:]` and rejects non-canonical signatures
  before verification, local to that caller only — `AuthCryptoJWK`'s shared
  verifier (DPoP/JWT/WebAuthn) is unchanged and still accepts both forms, so
  ADR 0007's original fix for those callers is unaffected. Full evidence
  trail in ADR 0007's 2026-07-22 amendment. All 5 interop fixtures now pass;
  new regression test `PLCAuditorTests/testAuditorRejectsHighSP256Signature`.
- Two suites (`ATProtoVideoTranscoderIntegrationTests`'s prior use-after-free
  signature, and the null-pointer `PDSDatabase(Private) safeExecuteSync:`
  crash from `PDSDatabaseBlobsTests`/`PDSDatabaseLRUTests`) did not
  reproduce during this pass — both suites are green in isolation now. The
  `safeExecuteSync:` null-pointer crash (above) remains recorded as an
  unconfirmed, possibly disk-pressure-related flake since it didn't
  reproduce enough times to root-cause.

Working theory for why long-standing fixture debt was newly visible,
confirmed: most of these suites' assertions were failing quietly all
along but the specific code paths they exercise (actor-store DID
validation, AppView group indexing, service-schema bootstrap) simply
weren't reached until other changes (recent schema/migration work, gated
tests folding into the default run) made them execute. Not one incident —
a backlog of drift across test fixtures and two real product bugs
(`createLabel:`'s missing `cts` default, and the AppView `groups` schema
mismatch) that would have surfaced in production the first time each
feature was actually exercised.

## S6. Published-spec conformance matrix

**Status: complete (report-only).** Matrix built at
`docs/reports/spec-conformance-matrix.md` (commit `703723c4c`,
2026-07-17). 20 spec rows + Proposal 0016 = 21 rows total. 16 supported,
4 partial, 0 gap. Every "supported" row names at least one executable
proof (unit test, scenario, or CI gate).

Known gaps verified against codebase and seeded as backlog leads:

- **G1: Permissions — granular scope evaluation — Complete (2026-07-25).**
  OAuth validates standard scope syntax and enforces `repo:`, `rpc:`, `blob:`,
  `account:`, and `identity:` at their owning operation boundaries. `include:`
  now resolves the authenticated Lexicon permission set before an access token
  is minted, accepts only its concrete `repo` and `rpc` permissions, and
  persists only those fixed effective grants in the session. Resolution uses a
  24-hour in-process cache, permits a verified stale entry for at most 90 days
  on resolution failure, and otherwise fails closed. The underlying Lexicon
  resolver persists fetched schemas across process restarts.
- **G2: Sync 1.1 remainder — Complete (2026-07-24).** Export block ordering
  implemented properly. Collection subsets were already served by Garazyk's own
  `tools.garazyk.sync.getRepoFiltered` vendor extension.
- **G3: Account management surfaces.** S5 covers propagation; confirm
  deactivation/deletion/export UX endpoints against accounts spec.
- **G4: Labels — self-signing key (Complete).** Label distribution and query endpoints
  implemented (`XrpcLabelPack.m`, 671 lines); `#atproto_label` key
  generation and label signature verification completed.

The matrix builds on S3's truthful XRPC metrics but is broader: spec pages,
not endpoints, are the unit. Report-only; a red row is a lead, not a release
blocker, until triaged into a workstream.

Rollback: documentation-only until a gap lane starts; each gap lane carries
its own rollback notes.

Primary sources:

- [Specification index](https://atproto.com/specs/atp)
- [Account lifecycle](https://atproto.com/specs/account)
- [Event streams](https://atproto.com/specs/event-stream)
- [Synchronization](https://atproto.com/specs/sync)
- [OAuth profile](https://atproto.com/specs/oauth)
- [Permissions](https://atproto.com/specs/permissions)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)

## S7. STAR conformance and verifying import

**Status: complete (2026-07-23).** All three slices landed (V-flag fix,
verifying `parseL0Body`, dead converter deletion + ADR 0009). 6 new test
methods; all 20 STARPreorderTests pass. Evidence in
[the STAR conformance plan](../../archive/planning/star-conformance-plan.md)
and mega-plan Phase 4 item 9.

Evidence: `Garazyk/Sources/Repository/STAR.m` — the export writer
(`STARL0Writer`) is correct and fixture-tested and the negotiated public
sync export path uses it (phase-10 brief correction section), but
(1) the writer emits `V: true` on layer-0 entries whose `v` is omitted,
violating the spec's "`V` must not be present when `v` is not present"
and making archives non-canonical; (2) `STARReader.parseL0Body`
(STAR.m:756) is non-verifying and computes node CIDs over STAR wire
bytes, so `carDataFromSTARData:` produces CARs whose node blocks cannot
match `commit.data` or `t`/`l` links and which lack a commit block —
the STAR import paths (`XrpcRepoPack.m:1260` importRepo,
`AppViewIngestEngine.m:683`, `AppViewBackfillWorker.m:291`) cannot
round-trip a real STAR-L0 tree and verify nothing; (3) the CAR→STAR
converters are degenerate dead code (FIXME at STAR.m:974, zero callers).

Owner boundary: `Garazyk/Sources/Repository/STAR.m` plus its tests;
import call sites are consumers only and stay untouched.

Gate: existing STAR fixture tests regenerated and passing; new
round-trip (CAR → STAR → CAR) and malformed-input rejection suites;
global gates.

Rollback: each slice is a single-commit revert; fixtures regenerate
deterministically. Slice A changes emitted bytes, but STAR is negotiated
only via Garazyk's vendor MIME types with no known external consumer.

Primary source: https://tangled.org/microcosm.blue/star

## S8. Untyped JSON at auth trust boundaries

**Status: not started (identified 2026-07-26).** A review of Auth, Security,
PLC, and Identity found one defect class repeated at every trust boundary that
parses attacker-supplied JSON: values are read out of an `NSDictionary` and
assigned to typed properties or sent typed messages without an
`isKindOfClass:` check. Because `NSDictionary` and `NSArray` implement
`-copyWithZone:`, assignment into a `copy` `NSString *` property succeeds and
stores the wrong class; the failure surfaces later as an unrecognized selector,
which is an uncaught `NSInvalidArgumentException` and therefore process abort.

Confirmed by harness, not by reading alone: assigning `@{@"x":@1}` to a
`copy NSString *` property yields `NSConstantDictionary`, and the subsequent
`-hasPrefix:` raises `NSInvalidArgumentException`.

The same review found a second, unrelated class: several security components
exist but are never constructed, so their defects are latent while their
presence implies coverage that does not exist.

### Evidence

Live, reachable from unauthenticated request handling:

- `Auth/JWT.m:38-90` — `headerFromDictionary:` and `payloadFromDictionary:`
  assign every claim unchecked. Consumers inherit the untyped value:
  `Chat/Server/ChatAuthManager.m:87` (`typ` → `isEqualToString:`) and
  `:108` (`aud` → `-length`), both before any signature check. The `aud` case
  is reachable from a *spec-compliant* client, since RFC 7519 §4.1.3 permits
  `aud` to be an array. Same parse feeds `Video/VideoJWTAuthProvider.m:80`,
  `Auth/OAuth2.m:980`, `Auth/OAuth2Handler+TokenRevocation.m:112`,
  `Auth/PDS/PDSAuth.m:298`.
- `Auth/Crypto/AuthCryptoDPoP.m:111,120,129,172-178` — `typ`, `alg`, `jwk`,
  `htm`, `htu` used as their assumed type. Live via `Auth/OAuth2.m:462`,
  `Auth/DPoPUtil.m:191`, `AppView/Server/Auth/AppViewOAuth2Middleware.m:159`.
- `PLC/PLCOperation.m:348-353,306-307` — collection literals built from
  unchecked lookups (`@[op.data[@"recoveryKey"], …]`); a nil element raises.
  `PLCStateReplayer replayHistory:` performs no signature or `prev`-chain
  check, and `Network/XrpcIdentityPack.m:388-408` feeds it a PLC directory
  audit log directly, without invoking `PLCAuditor`.
- `Auth/JWT.m:351-385` — `exp`/`iss`/`aud` checks are skipped when the claim
  is absent, so an omitted `exp` never expires and an omitted `aud` bypasses
  audience validation. `exp` parses only from `NSNumber`, so `"exp": "170…"`
  also yields a non-expiring token. `_clockOffset` (`:259`) is never read, so
  there is no skew tolerance.
- `Auth/JWT.m:265,280` — `allowedAlgorithms` is optional (nil accepts any
  `alg`), and the header's `alg` selects the verification path rather than the
  key selecting the algorithm.
- `Auth/PDSReplayCache.m` — `initWithDatabasePath:` returns nil on failure and
  `sharedCache` caches that nil permanently via `dispatch_once`;
  `AuthCryptoDPoP.m:258` guards with `if (replayChecker)`, so a nil cache
  silently disables DPoP replay protection on the live OAuth token and PAR
  paths (`OAuth2.m:468`, `DPoPUtil.m:197`). The shared cache is also
  `:memory:`, so protection is per-process and lost on restart.
- `Security/GZInputValidator.m:79,103` — `char c = [s characterAtIndex:i]`
  truncates `unichar` to 8 bits; verified that `U+0132` truncates to `'2'`,
  inside the TID base32 alphabet. Live via `isValidRecordKey:` →
  `isValidTID:` from `Security/Space/PDSSpaceURI.m:95`.
- `PLC/PLCOperation.m:56-71,92-106` and `PLC/PLCAuditor.m:427-430` —
  `GZ_LOG_DEBUG_C` expands to an unconditional message send
  (`Debug/GZLogger.h:272`), so per-byte hex strings (up to 7500 bytes ×2) are
  built on every DID derivation and every signature verification regardless of
  log level, then discarded.

Latent — present but never constructed, so currently unreachable:

- `Auth/Verifier/AuthVerifier.m` — no construction site in `Garazyk/Sources`.
  Contains two self-recursive setters (`:90`, `:94`: `self.localPublicKey =`
  inside `-setLocalPublicKey:`), which are unbounded recursion and are the only
  way to configure local-issuer verification.
- `Auth/PDS/PDSAuth.m:363` — same self-recursive setter shape;
  `PDSAccountPolicy` is never constructed. Takedown enforcement on the real
  path goes through the services-container `adminController`
  (`Network/XrpcAuthHelper.m:369`, `XrpcRepoPack.m:54,95`,
  `XrpcSyncPack.m:184,1265`) and is unaffected.
- `Security/GZAuthzManager.m` — zero callers. Contains
  `validateReadAccess:` (`:216-224`) which denies posts/reposts/likes whenever
  the account row exists (no mute lookup despite the variable name), and
  `isAuthorizedForAdminOperation:` (`:154-187`) which can never return `YES`
  yet runs a discarded `getAccountByDid:` query. Its `isValidDID:` dependency
  (`GZInputValidator.m:33`) rejects every `did:web`, since the character class
  excludes `.`.

### Slices

Ordered so each is independently shippable and revertible.

1. **Fail-closed claim typing.** Add a single typed-accessor helper and apply
   it at the two parse boundaries: `JWTHeader/JWTPayload` construction and
   `AuthCryptoDPoP verifyProof:`. Reject the token on any type mismatch rather
   than coercing or ignoring. `Auth/OAuth2Handler+ClientValidation.m:920-925`
   already does this correctly and is the reference shape. Requires the `aud`
   decision below.
2. **Required-claim and algorithm binding.** In `JWTVerifier`: make `exp`
   mandatory, make `iss`/`aud` mandatory whenever the corresponding
   `expected*` is set, make `allowedAlgorithms` mandatory (fail closed when
   unset), derive the algorithm from the key rather than the header, and apply
   a bounded skew allowance using the existing `clockOffset`. Audit the
   minters first — `mintAccessTokenForDID:`/`mintRefreshTokenForDID:` always
   emit `iss`/`aud`/`exp`, so no self-issued token should regress.
3. **Replay checker fails closed, backed by durable state.** Stop caching a nil
   `sharedCache`, and make the `replayChecker` argument non-optional in
   `AuthCryptoDPoP verifyProof:` so omission is a compile error rather than a
   silent skip. Per the 2026-07-26 decision, the jti cache becomes persistent
   rather than `:memory:`: `sharedCache` takes its path from configuration so
   replay protection survives restart and stays correct behind a load
   balancer. `initWithDatabasePath:` already accepts a path and the schema,
   index, and cleanup timer already exist, so this is wiring plus a config key
   plus disk-budget accounting on the OAuth hot path — not new machinery.
4. **PLC audit-log verification.** Run `PLCAuditor` over the fetched audit log
   in `XrpcIdentityPack` before any state derived from it is trusted, and
   route `PLCStateReplayer` through `normalizedDataForOperation:`
   (`PLCAuditor.m:469-472` already type-checks the identical literal) instead
   of duplicating the construction unsafely. Reject non-string `op.did`
   (`PLCOperation.m:177`).
5. **Charset validation correctness.** Use `unichar` in `isValidTID:` and
   `isValidCID:`, and reject anything above `0x7F` before the alphabet check.
6. **Debug-log evaluation cost.** Gate `GZ_LOG_DEBUG_C` on the active level so
   arguments are not evaluated when disabled. This macro is repo-wide, so
   measure before and after and keep the change mechanical.
7. **Wire the auth cluster.** Per the 2026-07-26 decision, `Auth/Verifier`,
   `PDSAccountPolicy`, and `GZAuthzManager` are the intended auth path and get
   constructed and routed to, not deleted. This inverts the risk on every
   latent finding above: each becomes a release blocker rather than dead code,
   and two of them would cause an outage if wired as-is. Ordering is therefore
   mandatory — **fix before wiring**:

   a. Fix the three self-recursive setters (`AuthVerifier.m:90,94`,
      `PDSAuth.m:363`) — assign the ivar, not the property — and add the
      detection sweep to CI so the shape cannot recur.
   b. Make `PDSAccountPolicy`'s admin controller a constructor-injected,
      `strong` dependency instead of a `weak` optional set after the fact, and
      make the no-controller case a startup failure rather than a per-request
      `return YES`.
   c. Fix `GZAuthzManager validateReadAccess:` (`:216-224`) — it currently
      denies posts/reposts/likes whenever the account row exists, which once
      live would deny owners reading their own repo. Either implement the
      mute/block query the variable name implies or delete the branch.
   d. Fix `GZInputValidator isValidDID:` (`:33`) to accept `did:web`, whose
      identifier contains `.` and percent-encoding. Wiring `GZAuthzManager`
      before this ships a total denial for every `did:web` account.
   e. Resolve `isAuthorizedForAdminOperation:` (`:154-187`), which can never
      return `YES` yet runs a discarded query — either give it a real scope
      check or remove it so no caller can mistake it for a grant.
   f. Close `AuthVerifier`'s own gaps before it carries traffic: the absent
      `aud` check (`:372`), and `:187` where a nil `request` skips DPoP proof
      verification entirely while leaving `isDPoP` true, so a DPoP-bound token
      is accepted with no proof of possession.
   g. Only then construct the cluster and route XRPC auth through it, with the
      existing `XrpcAuthHelper` path kept working until parity is proven.

   This slice is larger than slices 1-6 combined and changes the auth
   architecture, so it is tracked as its own execution phase rather than a
   tail-end slice.

### Owner boundary

Slices 1-3 own `Garazyk/Sources/Auth/` plus their tests; DPoP and OAuth call
sites are consumers and keep their signatures except where slice 3
deliberately tightens the `replayChecker` parameter. Slice 4 owns
`Garazyk/Sources/PLC/` and the single `XrpcIdentityPack` call site. Slice 5
owns `Security/GZInputValidator.m`. Slice 6 owns `Debug/GZLogger.h` and is
otherwise repo-wide by construction — it changes no behavior, only evaluation.
Slice 7 owns the three unwired files and is the only slice that may delete
public headers.

### Gate

Per-slice negative tests are the gate, since every finding here is a rejection
path: malformed-type JWT headers and payloads (number, array, object, and null
for each claim), array-valued `aud`, absent `exp`/`iss`/`aud`, DPoP proofs with
non-string `typ`/`alg`/`htu` and a string `jwk`, a `create` PLC operation
missing `recoveryKey`, an audit log whose `prev` chain does not link, and a TID
containing `U+0132`. Each must produce a clean 4xx, never an abort.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` and a cmake reconfigure, or they silently run zero
tests. Build `AllTests` with bounded parallelism (`-j4`); unbounded
`--parallel` exhausts memory on a 16 GB machine. Confirm free disk before a
full run — gated runs flake with `SQLITE_FULL` near capacity.

### Rollback

Each slice is a single-commit revert. Slices 1-4 tighten rejection and so can
turn previously-accepted malformed tokens into 4xx; if a real client regresses,
revert that slice rather than loosening the check, and capture the client's
actual payload shape as a test case first. Slice 6 is behavior-neutral. Slice 7
is the only destructive slice and should land last, after its ADR.

### Decisions taken (2026-07-26)

All three open questions were resolved by the operator before execution
started. Each still needs its ADR written, because each is a durable,
protocol- or architecture-visible contract:

- **Claim type mismatches are rejected, not coerced.** `aud` accepts the
  RFC 7519 array form: normalize to an array internally and match if any
  element equals the expected audience. Every other claim type mismatch is a
  hard rejection.
- **DPoP replay state is durable.** The jti cache becomes a persistent store
  rather than `:memory:`, so replay protection survives restart and remains
  correct behind a load balancer. The ADR must record the disk budget and the
  added I/O on the OAuth token and PAR paths.
- **The auth cluster is wired, not deleted.** `Auth/Verifier`,
  `PDSAccountPolicy`, and `GZAuthzManager` become the live auth path. The ADR
  must record the parity strategy against the existing `XrpcAuthHelper` path
  and the cutover/rollback trigger.

### Execution phases

Derived prompts live in `../prompts/`:

- `phase-13-auth-json-typing.md` — slices 1-6, no architecture change.
- `phase-14-wire-auth-cluster.md` — slice 7, `depends_on: [13]`.

## S9. Blob lifecycle and storage-pool correctness

**Status: not started (identified 2026-07-26).** A review of Repository,
Database, and Blob found that the blob subsystem implements neither half of
the published blob lifecycle, and that a complete usage-accounting design
exists in the tree but was never installed. Separately, the actor-store pool
returns silently partial results from its enumeration API and evicts stores
out from under live callers.

### The specification contract

Two `atproto.com` pages define the lifecycle Garazyk is missing:

- Uploaded blobs enter **temporary storage** and are "not accessible for
  download or distribution while in this state", and are excluded from
  `listBlobs`. They become publicly accessible only once a record referencing
  them is successfully created.
- Servers **should garbage collect un-referenced temporary blobs** after a
  grace period — "at least one hour a firm lower bound", several hours
  recommended, to tolerate apps that upload well before referencing.
- On record deletion the server "checks if any other current records **from
  the same repository** reference the blob. If not, the blob is deleted along
  with the record." Account deletion removes all hosted blobs.
- On limits, the spec recommends prioritising "limits on overall account
  resource consumption" over per-blob size caps.

This means the reclamation question is not a choice between a sweeper and
reference counting: the spec requires **both** — an immediate per-repository
reference check on record delete, and a time-based sweep for blobs that were
uploaded but never referenced. Garazyk currently implements neither, and also
lacks the temporary/referenced distinction the rest of the contract rests on.

Sources: <https://atproto.com/specs/blob>,
<https://atproto.com/guides/blob-lifecycle>.

### Evidence

Blob lifecycle:

- `Blob/BlobStorage.m:130-132` leaves provider bytes behind when metadata
  save fails, and `:266-268` deletes only metadata on
  `deleteBlobWithCID:`. Both defer to a garbage collector in comments. No
  collector exists: `Admin/Diagnostics/BlobAudit/PDSBlobReferenceScanOperation.m`
  builds an `unreferencedBlobs` report and contains no delete or remove call,
  and no other reclamation path exists in `Garazyk/Sources`.
- The `blobs` table (`Database/Schema/PDSSchemaManager.m:512`,
  `Database/Schema.m:108`) has no temporary/referenced state column, and there
  is no record→blob join table. `getBlobWithCID:did:`
  (`Blob/BlobStorage.m:146-162`) therefore serves any blob the provider holds,
  so an uploaded-but-unreferenced blob is world-readable by CID — contrary to
  the temporary-state rule above.
- The same method's ownership check runs only `if (did)` and only
  `if (store)`, then falls through to the provider regardless. A nil `did`
  or a transient `storeForDid:` failure skips authorization and still serves
  the bytes. `blobFilePathWithCID:did:` (`:195-210`) repeats it.
- The two `blobs` schema definitions above disagree: `Schema.m` carries
  `FOREIGN KEY (did) REFERENCES accounts(did)`, `PDSSchemaManager.m` does not.

Usage accounting and quotas:

- `Database/Schema.m:129-195` defines six complete, correct-looking SQLite
  triggers (`trg_account_usage_blob_insert/delete`, `..._block_...`,
  `..._record_...`) that maintain `account_usage` with upserts and clamped
  decrements. **Every one of the eight `kPDSAccountUsage*` constants has zero
  references outside `Database/Schema*`** — the triggers are never created on
  any database, so `account_usage` is never written.
- Consequently every consumer reads zeros: the soft-quota checks at
  `Network/XrpcVendorPack.m:253-266` compare `blob_bytes`/`record_count`/
  `repo_bytes` against `config.softQuota*` and can never fire;
  `metrics incrementQuotaExceeded:` is unreachable; and the reporting paths
  at `Services/PDS/PDSAccountService.m:585` and
  `Network/XrpcAdminPack+AccountInfo.m:93` report zero usage for every
  account. Nothing gates `uploadBlob` on quota at all.

Storage pool:

- `Database/Pool/DatabasePool.m:342-358` documents `knownDids` as a cache of
  all DIDs and walks the filesystem "only when the set is empty", but `:170`
  adds on store open and `:235` removes on eviction, so it tracks
  currently-open stores. After a single `storeForDid:` call the set is
  non-empty and incomplete, so `getAllReposWithError:`/`getAllAccountsWithError:`
  silently return only that subset. Live via
  `Core/Repositories/PDSSQLiteRepoRepository.m:55`.
- `evictLRUStore` (`:202`) fires whenever `stores.count >= maxSize` (`:149`)
  and closes a store other threads hold; `ActorStore.m:201` `close` is not
  serialized on the store's own `transactionQueue`. This is not memory-unsafe
  — `PDSDatabase close` serializes on `dbQueue` and every statement path
  rechecks `isOpen`/`_db` (hardened in `b4d178c6`) — so the symptom is
  spurious "database not open" failures under load.
- Eviction runs on the serial `poolQueue` and calls `close`, which does
  `dispatch_sync(dbQueue)`, so evicting a busy store stalls all pool traffic
  for the length of the in-flight transaction. Any transaction block that
  re-enters the pool would complete a `poolQueue → dbQueue → poolQueue` cycle;
  no such caller exists today, so this is a landmine rather than a live bug.
- `storeForDid:` holds `poolQueue` across two filesystem syscalls in
  `dbPathForDid:` (`:128-131`) plus a full SQLite open and migration run, so
  every cold-DID request serializes the pool.
- `:72` schedules eviction with `NSTimer scheduledTimerWithTimeInterval:`,
  which needs a live run loop on the constructing thread; off a run-loop
  thread, time-based eviction silently never runs. `PDSReplayCache` already
  uses a `dispatch_source_t` timer for the same job.

Repository:

- `Repository/MST.m` `nodeFromCBOR` silently `continue`s past malformed
  entries (`:1027,1046,1052`) and clamps an over-long `p` prefix (`:1035`)
  instead of rejecting, so malformed bytes decode to a different valid-looking
  tree. It also infers node level from the first key's depth (`:1079-1082`,
  the comment calls it an approximation), so a node whose entries were partly
  skipped gets a wrong level and an empty node always gets level 0.
- `Database/Migrations/PDSMigrationManager.m:1020-1087` passes `&errMsg` to
  `sqlite3_exec` for BEGIN and COMMIT and never calls `sqlite3_free` in the
  method, leaking the message on failure — it logs it at `:1054`, proving
  allocation. Other methods in the file free correctly.

### Decisions taken (2026-07-26)

- **Reclamation follows the spec: both mechanisms.** Delete-on-last-reference
  scoped per repository at record delete, plus a grace-period sweep for
  never-referenced temporary blobs. The grace period is configurable with a
  floor of one hour and a default of several hours.
- **Per-account quota is configurable and enabled by default**, enforced at
  upload and returning a quota-exceeded error. This matches the spec's
  preference for account-wide resource limits over per-blob caps.
- **The MST decoder rejects malformed nodes** rather than silently repairing
  them, per the requirements of a canonical content-addressed format.

### Slices

Blob lifecycle (phase 15):

1. **Model the lifecycle.** Add the referenced/temporary state and a
   record→blob reference table, reconciling the two divergent `blobs` schemas
   into one definition as part of the migration.
2. **Install the usage triggers.** Create the six existing
   `kPDSAccountUsage*` triggers during migration and backfill `account_usage`
   for existing rows, so the already-wired soft-quota checks and reporting
   endpoints stop reading zeros.
3. **Enforce quota at upload** in `uploadBlob`, using the now-live counters.
4. **Reference extraction on write and delete.** Extract blob references when
   records are created and removed; on delete, drop the blob when no other
   current record in the same repository references it.
5. **Grace-period sweep** for temporary blobs, plus provider cleanup on the
   metadata-save failure path at `BlobStorage.m:130`.
6. **Serve only what is servable.** Restrict `getBlobWithCID:did:` and
   `blobFilePathWithCID:did:` to referenced blobs, make the ownership check
   fail closed on both nil `did` and store-lookup failure, and exclude
   temporary blobs from `listBlobs`.

Storage pool and decoder (phase 16):

7. **Fix pool enumeration**: either make `knownDids` a real on-disk index or
   drop the cache and always walk. Silent partial results are the defect;
   pick whichever keeps `getAllRepos`/`getAllAccounts` complete.
8. **Make eviction safe and non-blocking**: do not close stores that have
   in-flight work, move `close` off `poolQueue`, and move SQLite open out of
   the pool's critical section. Replace the `NSTimer` with a
   `dispatch_source_t`.
9. **Strict MST decode** per the decision above.
10. **Low-severity cleanup**: the `sqlite3_free` leak, the
    `performSelector:` bounce at `DatabasePool.m:22`, and the unsigned
    `openFileHandleCount` decrement at `:236`.

### Owner boundary

Phase 15 owns `Garazyk/Sources/Blob/`, the `blobs`/`account_usage` schema and
its migration, and the record write/delete call sites that must emit blob
references. Phase 16 owns `Database/Pool/`, `Repository/MST.m` decode, and the
named low-severity sites. Neither phase touches `Auth/`, which phases 13-14
hold.

### Gate

Phase 15 is conformance-shaped, so the gate is behavioural: an uploaded blob
is not retrievable and not listed until referenced; it becomes retrievable
after the referencing record is created; it is deleted when the last
referencing record in that repo is deleted but retained while another record
still references it; a never-referenced blob survives inside the grace window
and is swept after it; an upload past quota is rejected with a quota error and
leaves no provider bytes; and a blob request with a nil `did` or a failing
store lookup is denied rather than served.

Phase 16's gate is a pool test that opens one store and then asserts
`getAllRepos` returns every on-disk repo, an eviction test under
`maxSize` pressure with concurrent readers, and MST decode rejection cases for
malformed entries, over-long prefixes, and empty nodes. Migration round-trip
(apply/rollback/re-apply) coverage is required for every schema change in both
phases, per the O2 phase B lesson in workstream 07.

New suites need registration in `Garazyk/Tests/test_main.m` plus a cmake
reconfigure, then the mega-plan global gates with bounded `--parallel 4`.

### Rollback

Each slice is a single-commit revert. Slice 6 is the visible behaviour change
— blobs that are currently readable become unreadable until referenced — so it
lands last in phase 15 and after the backfill in slice 2, and should be
verified against a real client upload flow before release. Schema changes
carry apply/rollback/re-apply tests. Phase 16 slices are independent of each
other and of phase 15.

### Execution phases

- `../prompts/phase-15-blob-lifecycle.md` — slices 1-6.
- `../prompts/phase-16-storage-pool-and-decoder.md` — slices 7-10,
  `depends_on: []`.
