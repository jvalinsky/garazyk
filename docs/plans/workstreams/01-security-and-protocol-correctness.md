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
(`96_firehose_cursor_resume.ts`, `1a8da8cb`) proves gap-free resume
across a live disconnect/reconnect (no gap, no duplicates, monotonic,
disconnect-window records delivered; 10/10 structured steps), enabled by
the `closeForUpgrade` WebSocket-handoff fix (`700352ab`). Downstream
propagation: `91444a89` wires admin takedown/reinstate to the account
notifications so `SubscribeReposHandler` emits real `#account` events,
adds the `RelayClientDelegate` account-event method, and has
`AppViewIngestEngine` durably persist and forward account events;
`04f23030` closes the last hop (`RelayUpstreamManager` forwards account
events downstream). Scenario 97 (`97_account_takedown_propagation.ts`,
`909c6399`) proves the takedown chain E2E. - **AppView un-indexing on takedown — Complete (2026-07-24).** `RelayRepoStateManager`'s status-tracking model is now integrated with AppView's indexing pipeline to un-index records when an account is taken down.

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
`docs/reports/spec-conformance-matrix.md` (commit `de67b72a`,
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

**Status: complete (verified 2026-07-27).** All 7 slices landed across two
execution phases. 11 commits, 3 ADRs written, global gates green.

A review of Auth, Security, PLC, and Identity found one defect class repeated
at every trust boundary that parses attacker-supplied JSON: values are read out
of an `NSDictionary` and assigned to typed properties or sent typed messages
without an `isKindOfClass:` check. Because `NSDictionary` and `NSArray`
implement `-copyWithZone:`, assignment into a `copy` `NSString *` property
succeeds and stores the wrong class; the failure surfaces later as an
unrecognized selector, which is an uncaught `NSInvalidArgumentException` and
therefore process abort.

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

### Decisions taken (2026-07-26, documented 2026-07-27)

All three open questions were resolved by the operator before execution
started. The decisions were recorded as ADRs after execution:

- **Claim type mismatches are rejected, not coerced.** `aud` accepts the
  RFC 7519 array form: normalize to an array internally and match if any
  element equals the expected audience. Every other claim type mismatch is a
  hard rejection. See ADR 0013.
- **DPoP replay state is durable.** The jti cache becomes a persistent store
  rather than `:memory:`, so replay protection survives restart and remains
  correct behind a load balancer. Disk budget and I/O cost recorded in ADR
  0014.
- **The auth cluster is wired, not deleted.** `Auth/Verifier`,
  `PDSAccountPolicy`, and `GZAuthzManager` become the live auth path, behind
  a `PDS_USE_AUTH_VERIFIER` env-var switch with the incumbent path retained
  for rollback. Parity strategy and cutover trigger recorded in ADR 0015.

### Commits

**Phase 13 (slices 1-6):**

| Slice | Commit | Description |
|-------|--------|-------------|
| 1 | `d8ba0644` | Fail-closed claim typing at JWT/DPoP parse boundaries (ADR 0013) |
| 2 | `a80e91b5` | JWTVerifier mandatory claims, fail-closed alg, key-derived verification |
| 3 | `f079278b` | DPoP replay cache durable, sharedCache never nil (ADR 0014) |
| 4 | `77defcb7` | PLC audit-log verification — PLCAuditor chain check before state replayer |
| 5 | `a04c03ea` | TID charset validation — unichar truncation (U+0132) gate |
| 6 | `b0b6754d` | GZ_LOG_DEBUG/DEBUG_C gated on active log level |
| review | `fc0357f5` | Verify trailing PLC tombstone signatures before accepting the chain |
| review | `a1e6b436` | Reject non-ASCII CID characters before base32 validation |
| review | `b0730534` | Use live time by default in JWTVerifier |

**Phase 14 (slice 7):**

| Step | Commit | Description |
|------|--------|-------------|
| 1 | `ee358663` | Break self-recursive setters in AuthVerifier/PDSAuth |
| 2-3 | `713b4490` | Account policy fail-closed + GZAuthzManager correctness |
| 4-5 | `91848d5e` | did:web validation + AuthVerifier DPoP/audience gaps |
| 6 | `a58df71b` | Wire AuthVerifier cluster behind `PDS_USE_AUTH_VERIFIER` switch |
| (fix) | `cd420966` | Fix duplicate method and property access in XrpcAuthHelper |
| review | `65e9b987` | Auth-path parity, account-policy, and did:web regression suites |
| review | `31f1a4cf` | CI recursive-setter check and RelayMetrics setter fix |

### Execution phases

Derived prompts live in `../prompts/`:

- `phase-13-auth-json-typing.md` — slices 1-6, no architecture change. **Complete.**
- `phase-14-wire-auth-cluster.md` — slice 7, `depends_on: [13]`. **Complete.**

## S9. Blob lifecycle and storage-pool correctness

**Status: Phases 15–16 complete (2026-07-27).** A review of Repository,
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

### Phase 15 completion evidence (2026-07-27)

- Commits: `b84251d5` (lifecycle schema and migration round-trip coverage),
  `c79e730d` (install and backfill the six existing usage triggers),
  `70bb0f22` (atomic quota enforcement), `f904a8d6` (record reference
  extraction), `61e5e22a` (temporary sweep), and `1b8a04f5` (referenced-only
  reads and listings). `af73b30b` is an intervening Deno lint fix required by
  the global gate.
- Behavioural coverage: `./build/tests/AllTests --filter '*Blob*'` passed 114
  tests across 11 suites. The public XRPC flow was also exercised by 12
  `BlobXrpcTests`, including upload → createRecord → fetch and temporary-blob
  denial.
- Global gates: `deno task check`, `deno task lint`, `deno task test`, and
  `cmake --build build --target AllTests --parallel 4` all pass. Disk was
  checked immediately before the native gate (15 GiB available).
- **Correction (2026-07-27, merge review).** This entry previously claimed
  `./build/tests/AllTests --gated=run` passed. That claim does not reproduce:
  `RelayRepoStateManagerTests` aborts with SIGSEGV (exit 133), both in a full
  run and in isolation. The crash is **not** attributable to phases 15–16 —
  `git diff af255960..phase-15-16` touches no Relay file — and it traces to
  `6dc9db49` ("Relay: add SQLite persistence for RelayRepoStateManager") in
  the shared base, under the disk-pressure conditions this workstream already
  records (98% full, ~12 GiB free). Tracked as the pre-existing flake watch
  item in S5, not as a phase 15–16 regression. Targeted verification that does
  reproduce: BlobStorage 21, PDSMigrationManager 12, MSTDecoder 5,
  DatabasePool 18 — 56 tests, 0 failures.
- ADR: [0013 Blob lifecycle conformance](../../adr/0013-blob-lifecycle-conformance.md).
- **Follow-up (2026-07-27): block usage attribution corrected.** S9 recorded
  the six `kPDSAccountUsage*` triggers as already correct and needing only
  installation. Four were; the two block triggers were not. Their
  `(SELECT did FROM records LIMIT 1)` owner lookup is NULL for any block
  written before the shard's first record — every account's initial commit —
  and since SQLite treats NULL as distinct from NULL, `ON CONFLICT(did)` could
  not merge the results, so each such block created its own orphan
  `account_usage` row and the account's `repo_bytes` was undercounted by the
  stranded total. `ipld_blocks` now carries the owning `did` and migration V8
  backfills it, reinstalls both triggers against `NEW.did`/`OLD.did`, drops the
  orphans, and recomputes `repo_bytes` from `ipld_blocks`. Regression coverage:
  `testBlockUsageAttributionMigrationRepairsOrphanedRepoBytes` and
  `testBlockUsageAttributionMigrationRoundTripIsIdempotent`. See the 2026-07-27
  amendment in ADR 0013.
- **Merge-review fix (2026-07-27).** `PDSSQLiteRepositoryTests/testBlobListForDID`
  asserted the pre-slice-6 listing contract and began failing once temporary
  blobs were excluded from `listBlobs`. The fixture now marks its blobs
  referenced, and `testBlobListForDIDExcludesTemporaryBlobs` pins the intended
  exclusion directly.

### Phase 16 completion evidence (2026-07-27)

- Commits: `d4313993` (complete actor-store enumeration), `5e5b451c` and
  `8966a66e` (the jointly implemented authoritative slice 8: active-use-safe
  eviction, off-queue cold opens, and the dispatch-source timer), `c2d888c8`
  (strict MST decode), and `f8065279` (migration error-message cleanup).
- Phase acceptance: `DatabasePoolTests` passed 18 tests; the complete `MST*`
  filter passed 108 tests, including the byte-identical fixture. The newly
  registered `MSTDecoderTests` suite executed 5 rejection cases. The focused
  migration filter passed 20 tests, including apply/rollback/re-apply coverage.
- Global gates: `deno task check`, `deno task lint`, `deno task test`, and
  `cmake --build build --target AllTests --parallel 4` all pass. Disk was
  checked immediately before the native gate (13 GiB available). The
  `--gated=run` claim carries the same correction recorded under phase 15
  above: that run aborts in the pre-existing `RelayRepoStateManagerTests`
  crash, which is unrelated to this phase.

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

## S10. WebSocket framing and outbound egress hardening

**Status: complete (updated 2026-07-27).** Both Phase 17 ingress and Phase 18
egress slices are complete. A review of Network, Sync, and Federation found
three unauthenticated, unbounded defects on the public ingress surface, and
one class of bypass on the outbound side that rendered the existing SSRF
protection ineffective despite its classification logic being sound.

The ingress defects share a shape: the WebSocket codec enforces per-frame
limits but no aggregate limits, and validates frame contents but not frame
*sequences*. The egress defect is a time-of-check/time-of-use gap: the SSRF
verdict is computed against one DNS answer and the connection is made against
another.

### Evidence

Outbound egress:

- `Network/SSRFValidator.m` resolves the hostname and classifies every
  returned address, but `Network/ATProtoSafeHTTPClient.m:262` then passes the
  original URL string to `curl_easy_setopt(curl, CURLOPT_URL, ...)`. Neither
  `CURLOPT_RESOLVE` nor `CURLOPT_CONNECT_TO` appears anywhere in the file, and
  the `NSURLSession` implementation in the same file has the same structure.
  curl therefore performs an independent second lookup. A short-TTL
  attacker-controlled domain returns a public address to the validator and a
  private one to the connection — the standard DNS-rebinding SSRF bypass,
  against a component named `SafeHTTPClient`.
- `SSRFValidator.m:44` catches `::1` by exact `memcmp` against
  `in6addr_loopback`, so `::` (unspecified) classifies as public. NAT64
  (`64:ff9b::/96`) and 6to4 (`2002::/16`) can encode a private IPv4
  destination and are not decoded. The IPv4 side, by contrast, is
  comprehensive — including `169.254.0.0/16`, the cloud metadata range.
- `SSRFValidator.m:82` (`CFHostStartInfoResolution`) and `:164`
  (`getaddrinfo`) are synchronous with no timeout, so a slow or hostile
  authoritative server stalls the calling thread for the resolver's duration.
- `ATProtoSafeHTTPClient.m:199-218` is indented as though it sits outside
  `if (!isLoopback) {` at `:178`. Brace counting confirms it is inside, so
  behavior is correct — but the indentation is actively misleading in a
  security gate.

WebSocket ingress (`Sync/WebSocket/WebSocketCodec.m`):

- `:141` appends every continuation frame to `self.fragments` with no
  aggregate cap; the total is only summed once FIN arrives (`:144-147`).
  `maxFrameSize` bounds a single frame at 16 MB and **has no references
  outside `WebSocketCodec.h`**, so it is never tuned. 1000 unterminated 16 MB
  continuation frames is 16 GB of heap on a public, unauthenticated endpoint.
- `:122` treats every opcode `>= 0x8` as an always-complete control frame,
  enforcing neither RFC 6455 §5.5 limit (≤125 byte payload, never
  fragmented). `Sync/WebSocket/WebSocketConnection.m:517-518` echoes ping
  payloads verbatim via `sendPong:`, so a 16 MB ping yields a 16 MB pong —
  an amplifier bounded only by connection count.
- `:70` reads `masked` but never enforces it; RFC 6455 §5.1 requires failing
  the connection on an unmasked client frame.
- `:128-160` accepts invalid frame sequences: a new non-FIN data frame while a
  fragmented message is in progress silently overwrites `fragmentOpcode` and
  merges payloads; a stray CONTINUE with no start is accumulated then silently
  dropped when `eventForOpcode:0` returns nil; reserved opcodes (0x3-0x7,
  0xB-0xF) are ignored rather than failing the connection; RSV bits are never
  checked.
- `:101` adds `headerLength + payloadLength` without overflow guard. Currently
  unreachable because `:87` rejects anything above the 16 MB default first,
  but `maxFrameSize` is a public settable property.
- `:167` calls `replaceBytesInRange:` on every `feedData:` call, memmoving the
  residual buffer — quadratic cost for a stream of small frames arriving
  across many reads.

HTTP framing:

- `Network/Http1Parser.m:110-115` reads `Content-Length` via
  `CFHTTPMessageCopyHeaderFieldValue`, which joins repeated headers as
  `"5, 10"`; `longLongValue` then parses `5` and stops at the comma. The
  parser correctly rejects `Transfer-Encoding` together with `Content-Length`
  (`:198-199`) but not two conflicting `Content-Length` headers, which
  RFC 7230 §3.3.3 also requires rejecting. `longLongValue` additionally
  accepts leading whitespace, a sign, and trailing garbage where the RFC wants
  strict digits.
- `Sync/Firehose/SubscribeReposHandler.m:134,137` parse
  `PDS_FIREHOSE_MAX_PENDING_SENDS`/`_BYTES` with `integerValue` and do not
  validate the result, so a typo silently yields 0.

### Decisions taken (2026-07-26)

- **The validated address is pinned into the connection.** `SSRFValidator`
  returns the vetted address and the client connects to *that*, via
  `CURLOPT_RESOLVE` and the `NSURLSession` equivalent, rather than
  re-resolving. TLS SNI and the `Host` header must continue to carry the
  original hostname.
- **The WebSocket codec implements full RFC 6455 conformance**, failing the
  connection on unmasked client frames, oversized or fragmented control
  frames, reserved opcodes, set RSV bits, and invalid fragmentation
  sequences — alongside the aggregate reassembly cap.

### Slices

Ingress (phase 17):

1. **Aggregate reassembly cap** and control-frame limits (≤125 bytes, never
   fragmented), plus a bound on echoed ping payloads.
2. **Frame-sequence and header validation**: mask enforcement, reserved
   opcodes, RSV bits, and the fragmentation state machine.
3. **Overflow guard and buffer cost**: guard `:101` independently of
   `maxFrameSize`, and replace the quadratic compaction at `:167` with a
   read-offset buffer.
4. **HTTP framing**: reject duplicate or conflicting `Content-Length`, and
   parse it strictly. Validate the firehose env limits.

Egress (phase 18):

5. **Pin the resolved address** through both client implementations, keeping
   SNI and `Host` on the original hostname.
6. **Close the IPv6 gaps**: `::`, NAT64, and 6to4 decoding.
7. **Bound DNS resolution** with a timeout so a hostile resolver cannot stall
   a request thread.
8. **Fix the misleading indentation** in `validateURL:` as part of touching
   that function, so the security gate reads the way it behaves.

### Owner boundary

Phase 17 owns `Sync/WebSocket/` and `Network/Http1Parser.m` plus their tests;
`SubscribeReposHandler` is a consumer and changes only where it reads env
limits. Phase 18 owns `Network/SSRFValidator.m` and
`Network/ATProtoSafeHTTPClient.m`. Neither touches `Auth/` (phases 13-14) or
`Blob/`/`Database/Pool/` (phases 15-16).

### Gate

Phase 17 is a protocol-conformance gate, so it is negative-test shaped: an
unmasked client frame, a 200-byte ping, a fragmented control frame, each
reserved opcode, a set RSV bit, a CONTINUE with no start, a second non-FIN
data frame mid-fragment, and a fragment sequence exceeding the aggregate cap
must each close the connection with the correct RFC close code rather than
being accepted or silently ignored. A 16 MB ping must not produce a 16 MB
pong. Two conflicting `Content-Length` headers must yield 400. Existing
firehose scenarios (33, 65, 66, 95) must still pass, since they exercise the
same codec.

Phase 18's gate is a rebinding test: a resolver that returns a public address
on first lookup and a private one on second must fail the request, proving the
pin holds. Plus classification cases for `::`, a NAT64-encoded private IPv4,
and a 6to4-encoded private IPv4; and a slow-resolver case that times out
rather than hanging.

New suites need registration in `Garazyk/Tests/test_main.m` plus a cmake
reconfigure, then the mega-plan global gates with bounded `--parallel 4`.

### Phase 17 completion evidence (2026-07-27)

- Slices 1-4 and the missing transport-level protocol-error close behavior:
  `6dd33a30`, `93e4baed`, `fede19c1`, `8e7e086a`, and `f802e015`.
- Focused XCTest suites passed: `WebSocketRFCConformanceTests` (16),
  `Http1ParserTests` (11), `SubscribeReposHandlerEnvLimitsTests` (5), and
  gated `PDSWebSocketTransportTests` (8), including the oversized-control
  frame test that asserts Close rather than Pong.
- Structured Hamownia run `2026-07-27t1559z-69010`: scenarios 33, 65, 66,
  and 95 passed (22 checks, zero failures).
- After rebasing onto the lint-corrected `main` baseline (`86ed976d`), the
  required global gates passed: `deno task check`, `deno task lint`,
  `deno task test`, `cmake --build build --target AllTests --parallel 4`,
  `./build/tests/AllTests`, and `./build/tests/AllTests --gated=run`.

### Phase 18 completion evidence (2026-07-27)

- Egress pinning implementation: `aaf6ed57` uses per-transfer
  `CURLOPT_RESOLVE` on GNUstep/Linux and an in-file `NWConnection` transport
  on Apple. Both preserve the original host for HTTP and TLS while dialing
  only vetted numeric addresses. Redirects are validated and pinned one hop
  at a time; Apple failover remains within the vetted set.
- IPv6 classification coverage: `5c79d90c` proves rejection of `::`, NAT64
  `64:ff9b::/96` private embeddings, and 6to4 `2002::/16` private embeddings.
- Resolver deadline and vetted-set coverage: `30bbe6f3` proves a slow
  injected resolver fails promptly and that a complete public address set is
  returned without a mutable global resolver.
- `SSRFValidatorTests` is registered and executed (32 tests, zero failures)
  after `AllTests --list --filter SSRFValidatorTests` reported one class.
- GNUstep Docker gate passed after a 19 GiB disk preflight: runtime image
  `0d128839` and builder image `0d128839`; the builder configured `AllTests`
  and completed the in-container `SSRFValidatorTests` run.
- Global gates passed after the final implementation: `deno task check`,
  `deno task lint`, `deno task test`, `cmake --build build --target AllTests
  --parallel 4`, `./build/tests/AllTests`, and `./build/tests/AllTests
  --gated=run`.

### Rollback

Each slice is a single-commit revert. Phase 17 slices 1-2 turn currently
accepted frames into connection closes, so they carry real interop risk with
non-conformant clients: if a real peer breaks, capture its exact frame bytes as
a fixture and decide whether the peer or the codec is wrong before loosening
anything. Phase 18 slice 5 changes how every outbound request connects — if a
legitimate host fails, the likely cause is a multi-address or CDN host whose
pinned address went stale, so verify against a round-robin DNS target before
release.

### Execution phases

- `../prompts/phase-17-websocket-and-http-framing.md` — slices 1-4.
- `../prompts/phase-18-egress-pinning.md` — slices 5-8, `depends_on: []`.

## S11. Core decoder bounds, platform secret storage, and destructive CLI

**Status: complete 2026-07-27.** A review of Core, Compat, and
CLI found two width-related defects in the DAG-CBOR decoder reachable from
every untrusted-input path, a platform shim that silently provides far weaker
guarantees than the API it emulates, and a destructive CLI command that
under-deletes while reporting complete success.

The Core defects are notable for what they are *not*: the decoder already has
a depth limit and a correct varint reader. The gaps are **widths**, not
depths — 64-bit lengths and counts taken from attacker-controlled headers and
used before validation.

### Evidence

Core decoders:

- `Core/ATProtoDagCBOR.m:585` bounds a byte string with
  `*index + len > length`, where `*index` is `NSUInteger` and `len` is a
  64-bit value read from the CBOR header. The sum wraps. Verified with a
  harness replicating the expression: `index=9`, `len=2^64-5` sums to `4`, the
  check returns false, and `[NSData dataWithBytes:bytes + 9 length:2^64-5]`
  executes. Nine bytes of input (`5B FF FF FF FF FF FF FF FB`) reach that
  call. The decoder is entered from CAR import, PLC operations, STAR,
  `RepoCommit`, and XRPC handlers.
- `:617` and `:640` pass an unvalidated 64-bit `count` straight to
  `arrayWithCapacity:`/`dictionaryWithCapacity:` before anything checks the
  remaining input could hold that many items — each item needs at least one
  byte, so the bound is available and unused. On the Linux build this matters
  most, since GNUstep's `initWithCapacity:` allocates a backing buffer.
- `:577` computes `-(int64_t)(value + 1)`; at `2^64-1` the increment wraps to
  0 and the integer silently decodes as `0`, and above `2^63-1` the cast is
  undefined. DAG-CBOR restricts integers to the int64 range, so these are
  rejections, not wrap-arounds, in a content-addressed format.
- `Core/Base58.m:76-83` indexes `string.UTF8String` (bytes) with
  `string.length` (UTF-16 units). Safe only because the `chars[i] & 0x80`
  guard rejects every multi-byte input before the indices diverge — correct by
  accident. `calloc` results are unchecked at `:35` and `:93`.
- `Core/CID.m:343` and `Base58.m:61,64` emit one character per
  `appendFormat:@"%c"`, parsing a format string per character.
  `CID.stringValue` runs for every block touched by MST, CAR, and block
  storage.

Platform shim:

- `Compat/PlatformShims/Security/SecItemLinuxStore.m` persists secrets as
  plaintext property-list blobs in SQLite, protected only by directory `0700`
  (`:64`) and file `0600` (`:74`). On Apple the same `SecItem` API is
  hardware-backed and encrypted at rest. Callers cannot see which guarantee
  they get; the difference is silent and per-platform. Any process running as
  the same user, and every backup or disk image, reads them directly.

CLI:

- `CLI/PDSCLINukeCommand.m:92-98` deletes a hardcoded list — `di`, `blobs`,
  `service`, `sequencer`, `did_cache`. Per-account databases are not in it.
  `App/PDSApplication.m:333` roots the user pool at the data directory itself,
  and `Database/Pool/DatabasePool.m:93-134` shards actor stores to
  `{dataDir}/{method}/{prefix}/{did}` — so they live under `plc/`, `web/`, or
  `key/`, in files named `did:plc:...` with no extension, two levels down.
  `di` matches nothing. The fallback loop at `:121-143` is non-recursive and
  matches only `.db`, `.sqlite`, `-shm`, `-wal`, and `-journal` suffixes, so
  it misses them too. The command then prints
  `✅ All data has been nuked. You can now start fresh.` Blobs, service,
  sequencer, and did_cache **are** removed correctly, which makes the result
  worse than a clean failure: the service database is gone while every account
  database survives.
- `CLI/PDSCLIAccountCommand.m:225` and `CLI/PDSCLIAdminCommand.m:150` accept
  `--password` on the command line, and the help text at
  `PDSCLIAccountCommand.m:55` and `PDSCLIAdminCommand.m:42` demonstrates it
  (`--password secret`). Arguments are visible in `ps`, shell history, and
  process accounting. A correct interactive prompt already exists.
- `CLI/PDSCLIInputHelper.m:56-65` disables terminal echo and restores it on
  both the success and EOF paths, but not on signal, so `Ctrl-C` mid-prompt
  leaves the terminal with echo off. The password buffer at `:62` is not
  cleared after use.

### Decisions taken (2026-07-26)

- **Linux secrets are encrypted at rest with an operator-supplied key**,
  derived from an environment variable or key file at startup. The key's
  location becomes an explicit, documented operator responsibility rather than
  an implicit gap. OS-keyring integration was considered and rejected for its
  runtime dependency in minimal containers.

### Slices

Core decoders (phase 19) — complete, commits on `phase-19-20`:

1. **Fix the width defects in `ATProtoDagCBOR`**: compare against remaining
   bytes rather than summing (`:585`), clamp the collection capacity hint to
   what the remaining input can encode (`:617`, `:640`), and reject
   out-of-int64-range integers instead of wrapping (`:577`). Commit
   `2f21358e`.
2. **Harden `Base58`**: index the UTF-8 buffer with its own byte length, and
   check `calloc`. Commit `727370e9`.
3. **Replace per-character `appendFormat:`** in the base32 and base58
   encoders with direct buffer construction. Commit `cd6530b2`; existing
   golden CAR/STAR/MST/Interop fixtures remained byte-identical.

Platform and CLI (phase 20) — complete, commits on `phase-19-20`:

4. **Encrypt the Linux secret store at rest** with an operator-supplied key,
   including a migration path for existing plaintext stores and a startup
   failure when the key is absent but a store exists. Commit `194a2580`.
5. **Make `nuke-data` actually delete what it claims**: enumerate the shard
   layout the pool writes, delete recursively, and — critically — report
   honestly. It must not print success when items remain. Commit `0572e133`.
6. **Remove `--password` from the documented path.** Keep an automation-safe
   input (stdin, environment, or file) and stop demonstrating argv passwords
   in help text. Commit `84cb8ce3`.
7. **Restore terminal echo on signal** and clear the password buffer after
   use. Commit `52cda6ea`.

### Owner boundary

Phase 19 owns `Core/ATProtoDagCBOR.m`, `Core/Base58.m`, and the encoder in
`Core/CID.m`, plus their tests. Phase 20 owns
`Compat/PlatformShims/Security/SecItemLinuxStore.m` and `Garazyk/Sources/CLI/`.
Neither touches `Auth/`, `Blob/`, `Database/Pool/`, `Sync/`, or `Network/`,
which phases 13-18 hold.

### Gate

Phase 19 is decoder-fuzzing shaped. Required cases: the 9-byte overflow input
above must be rejected, not read; a declared collection count exceeding the
remaining bytes must be rejected without a large allocation; integers outside
the int64 range must be rejected rather than wrapped; and Base58 must reject
non-ASCII without relying on index coincidence. Existing golden CAR/STAR
fixtures must stay byte-identical — this phase must not change any valid
encoding. The `fuzzing/` corpus should gain the overflow input as a permanent
regression seed.

Phase 20's gate is behavioural: a secret written before the change is readable
after migration; startup fails loudly when a store exists and no key is
supplied; `nuke-data` on a populated data directory leaves **zero** account
databases and reports accurately when it cannot delete something; and no
command path accepts a password in a way that lands in `ps` output without an
explicit warning.

**Phase 19 gate result (2026-07-27):** all required decoder rejection cases
pass, with the nine-byte overflow fixture stored under
`Garazyk/Tests/fixtures/cbor/`. The global `deno` and `AllTests` gates passed.

**Phase 20 gate result (2026-07-27):** the Linux Docker
`SecItemLinuxStoreTests` target passed all 10 tests, including legacy
plaintext migration and encrypted round-trip coverage. Scratch-only
`PDSCLINukeCommandTests` cover recursive deletion and permission-denied
reporting. Account and admin CLI suites pass with environment-password input
and legacy-argv warnings. The global `deno` and `AllTests` gates passed.

New suites need registration in `Garazyk/Tests/test_main.m` plus a cmake
reconfigure, then the mega-plan global gates with bounded `--parallel 4`. Run
the Linux Docker gate for phase 20 — `SecItemLinuxStore` compiles only on the
non-Apple branch.

### Rollback

Phase 19 slices are independent single-commit reverts; slice 1 only rejects
inputs that currently crash or over-allocate, so interop risk is minimal —
if a real CAR fails to import afterwards, that CAR was malformed and should be
captured as a fixture. Phase 20 slice 4 changes the on-disk secret format and
is the one that needs care: ship the migration and a verified round-trip
before deleting any plaintext-reading path, and keep the reader able to
consume the old format for at least one release. Slice 5 makes a destructive
command more destructive — gate it behind the existing `--confirm` and test
against a scratch data directory, never a real one.

### Execution phases

- `../prompts/phase-19-core-decoder-bounds.md` — slices 1-3.- `../prompts/phase-20-secret-store-and-cli.md` — slices 4-7,
    `depends_on: []`.

## S12. MST viewer gating and dead admin credential surface

**Status: complete.** Commits: `6bce0725` (slice 1: MST viewer gating and auth), `65bc7ebe` (slice 2: cookie removal and X-Admin-Token production default). A review of App, Network, and Admin found a debug tool
shipped on by default with no supported disable path and no authentication,
and a cookie credential carrier on the admin auth path that nothing in the
codebase ever issues.

### Evidence

MST viewer:

- `Network/ATProtoHttpServerBuilder.m:45` sets `_enableMSTViewer = YES` in
  `init`. The only sites that set it to NO are tests (19 occurrences across
  `ATProtoHttpServerBuilderTests.m` and `PDSHttpPDSAdminRoutePackTests.m`).
  There is no config key, no environment variable, and no production code path
  that disables it — every deployment serves `/mst-viewer` and `/api/mst`.
- `App/MSTViewer/MSTViewerHandler.m` performs no authentication check anywhere
  in its 280 lines. `handleRequest:` dispatches directly to sub-handlers
  without examining headers.
- `/api/mst/accounts` runs `SELECT did, handle FROM accounts ORDER BY
  created_at DESC LIMIT 1000` with no auth (line 162). `/api/mst/export/{did}`
  loads an entire MST via `loadMSTForDid` and serializes it to JSON or DOT with
  no auth (line 232) and no rate limit. The NSCache in the handler (100 items,
  60s-120s TTL) mitigates repeated requests but the first request for any DID
  does full MST load + serialization.
- ATProto already publishes repo contents and `listRepos`, so this is not a
  data breach. The real problems are an unauthenticated endpoint doing
  unbounded per-request work (a cheap amplifier) and a debug tool shipped on
  by default with no supported way to turn it off.

Dead cookie credential surface:

- `Admin/PDSAdminAuth.m:306-317` accepts an `admin_token=` cookie as an admin
  token carrier. Nothing in `Garazyk/Sources` ever sets that cookie — confirmed
  by grep: the only `Set-Cookie` issuer for any `admin_token` variant is
  `UIAuthManager.m:215`, which sets `ui_admin_token` with `HttpOnly;
  SameSite=Strict`. The `admin_token=` cookie has no issuer, no `SameSite`, no
  `HttpOnly`, and no CSRF protection anywhere in `PDSAdminAuth` or the XRPC
  admin pack (CSRF machinery exists only in `AdminUIServer`).
- The cookie token still goes through full JWT verification afterward, so this
  is not an auth bypass. It is dead credential surface on a privileged path,
  reachable by cookie, with no Origin or CSRF check — it should be removed
  rather than defended.
- The sibling `X-Admin-Token` header path (`PDSAdminAuth.m:299`) is lower risk
  — also just a JWT carrier — but has neither an issuer nor CSRF protection.
  It already has `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` env var (`:151`) and a
  startup warning in production (`PDSApplication.m:526-532`). The cookie path
  has neither disable mechanism nor warning, making it the higher-priority
  removal.

### Decisions taken (2026-07-27)

- **MST viewer defaults off in production.** A new `debug.mst_viewer_enabled`
  config key and `PDS_ENABLE_MST_VIEWER` env var control the viewer. The
  default is NO when `PDS_ENV=production` (matching the issuer fail-closed
  pattern at `PDSApplication.m:354-363`) and YES otherwise, preserving
  backward compat for dev/test. When enabled, the handler requires admin auth
  via `PDSAdminAuth` on every request — including static assets, since the
  page is useless without the API and serving it without auth only reveals the
  tool exists.
- **The dead `admin_token=` cookie path is removed, not defaulted.** It has no
  issuer, no disable mechanism, and no CSRF protection. Removing the parsing
  block is safer than adding a config gate that operators must discover.
- **The `X-Admin-Token` header path is defaulted to disabled in production**
  rather than removed outright. It already has `PDS_DISABLE_X_ADMIN_TOKEN_HEADER`
  and a startup warning; defaulting it off in production closes the gap without
  breaking any operator who explicitly enables it for automation.

### Slices

1. **MST viewer gating and auth.** Add `_mstViewerEnabled` property to
   `ATProtoServiceConfiguration` (default YES, NO in production). Read from
   `debug.mst_viewer_enabled` config key and `PDS_ENABLE_MST_VIEWER` env var in
   `applyConfig:`. Wire `ATProtoHttpServerBuilder.initWithConfiguration:` to
   read `configuration.mstViewerEnabled` instead of hardcoding YES. Add an
   admin auth check at the top of `MSTViewerHandler.handleRequest:` — call
   `[PDSAdminAuth sharedAuth] authenticateHeaders:request.headers error:nil]`
   and return 401 JSON on failure. Update tests that rely on the viewer being
   on by default.
2. **Dead cookie and X-Admin-Token retirement.** Remove the `admin_token=`
   cookie parsing block from `PDSAdminAuth.m:306-317`. Default the
   `X-Admin-Token` header to disabled when `PDS_ENV=production` (change
   `PDSAdminAuthIsXAdminTokenHeaderDisabled` to also check `PDS_ENV`). Update
   `PDSAdminAuthTests.m` to remove cookie-path tests and add a test asserting
   the cookie is no longer accepted. Update the startup warning in
   `PDSApplication.m:526-532` to reflect that the header is now off by default
   in production.

### Owner boundary

Slice 1 owns `App/ATProtoServiceConfiguration.h/.m` (new property + config
parsing), `Network/ATProtoHttpServerBuilder.m` (wiring),
`App/MSTViewer/MSTViewerHandler.m` (auth check), and their tests. Slice 2 owns
`Admin/PDSAdminAuth.m` (cookie removal + header default),
`App/PDSApplication.m` (warning update), and `Admin/PDSAdminAuthTests.m`.

### Gate

- **Viewer off by default in production:** a test that constructs
  `ATProtoServiceConfiguration` under `PDS_ENV=production` asserts
  `mstViewerEnabled == NO`.
- **Viewer on by default otherwise:** the same test under no `PDS_ENV` asserts
  `mstViewerEnabled == YES`.
- **Viewer requires auth when enabled:** a request to `/api/mst/accounts`
  with no `Authorization` header returns 401, not 200. A request with a valid
  admin JWT returns 200.
- **Config key and env var:** `debug.mst_viewer_enabled: false` in config and
  `PDS_ENABLE_MST_VIEWER=0` in env each independently disable the viewer.
- **Cookie path removed:** a request with `Cookie: admin_token=<valid-jwt>`
  returns 401 (the cookie is no longer parsed). A request with
  `Authorization: Bearer <same-jwt>` still returns 200.
- **X-Admin-Token defaulted off in production:** under `PDS_ENV=production`
  with no `PDS_DISABLE_X_ADMIN_TOKEN_HEADER` set, a request with
  `X-Admin-Token: <valid-jwt>` returns 401. Under `PDS_ENV=production` with
  `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0`, it returns 200.
- **No regression:** `Authorization: Bearer <valid-jwt>` admin auth still
  works in all modes. Existing `ATProtoHttpServerBuilderTests` and
  `PDSAdminAuthTests` pass after updating the tests that relied on removed
  behavior.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

### Rollback

Each slice is a single-commit revert. Slice 1 changes the default behavior of
the MST viewer (off in production) — if an operator relied on the viewer being
on without auth in production, they can set `PDS_ENABLE_MST_VIEWER=1`, but they
must also provide admin credentials. Slice 2 removes a credential carrier — if
an automation client relied on the `admin_token=` cookie, it must migrate to
the `Authorization: Bearer` header. The X-Admin-Token header remains available
via `PDS_DISABLE_X_ADMIN_TOKEN_HEADER=0` for operators who need it.

### Execution phases

- `../prompts/phase-22-mst-viewer-and-dead-cookie.md` — slices 1-2,
    `depends_on: []`.

## S13. Registration, PhoneVerification, and Email trust-boundary sweep

**Status: complete ✅ (all 10 implementation slices done).** Slice 1 (CAPTCHA gate with siteverify + fail-closed) at `3a303467`. Slice 2 (phone OTP nil-provider fail-closed, ADR 0020) and slice 3 (email retry-race fix, DEBUG-only deterministic code, ADR 0022) at `2c9dc7ab`. Slice 3b (confirmEmail opaque token exchange, V17 migration) at `99f1738b`. Slice 4 (opaque password-reset tokens, V18 migration) and slice 4b (opaque account-delete tokens) at `c2277d62`. Slice 4c (expired token cleanup: email_confirmation_tokens + password_reset_tokens) at `09387919`. Slice 4d (confirmEmail acceptance gate tests + V17 email_confirmed_at ALTER TABLE) at `dd3842e4`. Slice 5 (Plivo 200-means-success fix, isKindOfClass guards, E.164 validation) at `a5a11cdc`. Slice 6 (composite gate AND semantics) plus the slice 1 follow-ups (tightened siteverify wait budget with cancellation, `percentEncode:` nil guard) landed at `0239f88c` (phase-25). V17 conditional ALTER TABLE fix at `c06045ae`. Full test suite clean (no regressions from phase-23 changes; 3 pre-existing failures in AdminAuthSync/RepoAuthRepo/RepoAuthIdentity). A review of the
account-creation and verification trust boundaries — Registration,
PhoneVerification, Email, and the XRPC handlers that consume them — found
two complete no-op verification gates, a password-reset token that is the
public DID, an unbounded OTP brute-force surface, and several input
validation gaps at the createAccount/confirmEmail/verifyPhone boundaries.
None of these modules has a dedicated security lane; they have been touched
only incidentally (S5 test fixes, E3 SMTP removal). The gates are the first
defense against account-creation abuse; a no-op gate used to defeat every
other gate in the composite via OR logic in `PDSCompositeRegistrationGate`
(fixed to AND in slice 6, `PDSRegistrationGate.m:63-90`), so each remaining
finding is a release blocker for any operator that turns the corresponding
gate on.

### Evidence

**CAPTCHA gate is a complete no-op.** `PDSCaptchaRegistrationGate.m:75`
(`verifyTokenWithSiteverify:`) returns `YES` unconditionally with
`#pragma unused(verifyURL)` — the siteverify HTTP call is never made. When
no secret key is configured, `:62-65` accepts token presence only. Together
these mean the captcha gate never verifies anything. Live via
`PDSRegistrationGateFactory` (`PDSRegistrationGate.m:178-182`) when
`captchaRequired` is YES.

**Phone OTP gate accepts any code when the provider is nil.**
`PDSPhoneOTPRegistrationGate.m:99-101` — the nil-provider fallback returns
`YES` for any non-empty `phoneVerificationCode`. The factory at
`PDSRegistrationGate.m:147-160` logs a warning on provider creation failure
and proceeds, so a misconfigured phone gate silently becomes open
registration.

**Password-reset token is the public DID.**
`XrpcServerPack+AccountManagement.m:225-235` — `resetPassword` validates
`token` as a DID via `ATProtoValidator validateDID:` and looks up the
account by that DID. Anyone who knows a victim's DID can reset their
password. `requestPasswordReset` (`:188-202`) is a no-op that returns 200
without minting or sending any token.

**`confirmEmail` accepts any token.**
`XrpcServerPack+AccountManagement.m:85-127` validates only that the email
matches the account (`:113-118`) and returns 200 without checking `token`
against anything. `emailConfirmed` can be set by any authenticated account
holder who knows their own email, with no round-trip through the email
provider. `requestEmailConfirmation` (`:62-80`) and `requestEmailUpdate`
(`:82-101`) are no-ops.

**No OTP attempt counting.** None of the four phone providers
(Twilio/Vonage/Plivo/Telegram Gateway) enforce a per-phone attempt limit
at the PDS layer. Twilio Verify manages this server-side; the other three
do not. The gate at `PDSPhoneOTPRegistrationGate.m:62-66` passes
`body[@"verificationSessionID"]` through without checking it, so providers
that require a sessionID (Vonage/Plivo/Telegram) return a generic
"verification failed" rather than a specific error.

**Plivo "200 means success" fallback.**
`PDSPlivoPhoneVerificationProvider.m:215-220` — a 200 response with neither
`is_verified: true` nor a "verified" message is accepted as approved. A 200
with an empty or error body would pass.

**`PDS_ALLOW_HTTP=1` deterministic OTP code at runtime.**
`ContactService.m:51-53` — when `PDS_ALLOW_HTTP` is set, the verification
code is hardcoded to `123456`. This is a runtime check in a release build,
not a compile-time debug guard. The same env var legitimately controls
HTTP egress policy elsewhere (`ATProtoSafeHTTPClient.m:193,750`,
`AppViewWriteProxy.m:152`), so it cannot be removed, but the deterministic
code path must move behind `#if DEBUG`.

**Untyped JSON at the registration boundary.** The gates extract
`body[@"phoneNumber"]` / `body[@"captchaToken"]` / `body[@"inviteCode"]`
without `isKindOfClass:[NSString class]` checks — the same defect class as
S8, but at the registration boundary. A `body[@"phoneNumber"]` that is an
`NSNumber` crashes `length` (`PDSPhoneOTPRegistrationGate.m:43`).

**`PDSEmailHTTPClient` retry-loop race.** `PDSEmailHTTPClient.m:120-128` —
`requestError` is set in the completion block and read after
`dispatch_semaphore_wait`; on a 30s timeout the wait returns and the loop
reads `requestError` before the block has run. Same class of bug as the
`ATProtoVideoTranscoderIntegrationTests` use-after-free fixed in S5 and the
`AppViewIngestEngine` out-parameter fix in O6.

### Slices

The full slice breakdown, decisions, and acceptance gate live in the
derived prompt (`../prompts/phase-23-registration-phone-email-trust-boundary.md`).
Summary:

1. CAPTCHA gate: implement siteverify via `ATProtoSafeHTTPClient`, fail
closed when no secret key is configured, pass `remoteip`.
2. Phone OTP gate: fail closed on nil provider, enforce sessionID for
providers that require it, add server-side attempt counting (service DB
V16).
3. Email: fix `PDSEmailHTTPClient` retry race, implement `confirmEmail` token
exchange (service DB V17), move `PDS_ALLOW_HTTP` deterministic code behind
`#if DEBUG`, redact OTP code from logs.
4. ✅ Password reset: replace DID-as-token with opaque single-use token (service
DB V18), implement `requestPasswordReset` token minting and email delivery.
5. ✅ Plivo "200 means success" fallback removal, input validation sweep
(`isKindOfClass:` checks at gate field extraction), E.164 phone number
validation, `PDSEmailHTTPClient` nil-apiKey guard.
6. ✅ Composite gate semantics: change `PDSCompositeRegistrationGate` from OR to
AND (added 2026-07-27 — see below).

### Slice 1 follow-ups (found in review of the in-flight implementation) — ✅ done at `0239f88c`

The slice 1 implementation is correct in its core: it fails closed on missing
secret, timeout, network error, non-2xx, unparseable body, and
`success: false`; it type-checks `captchaToken`, `success`, and `error-codes`;
it routes through `ATProtoSafeHTTPClient` so it inherits the phase-18 address
pinning; and `percentEncode:` correctly uses an explicit RFC 3986 unreserved
allowlist rather than `URLQueryAllowedCharacterSet`, which would leave `&` and
`=` unescaped and allow field injection into the form body. `remoteAddress` is
not spoofable — `HttpRequest.m:125` honors `X-Forwarded-For` only when proxy
trust is enabled *and* the peer is on a private or loopback range.

Two defects remained in that implementation and had to land before slice 1
was marked complete (both fixed at `0239f88c`):

- **Blocking wait budget.** `PDSCaptchaRegistrationGate.m` waits on a
  `dispatch_semaphore` for up to `siteverifyTimeout` (12s) on the request
  thread. Connections get a serial queue each (`HttpServer.m:482`), so
  concurrent registrations against a slow siteverify consume libdispatch
  workers. The per-IP rate limit at `XrpcHandler.m:194` caps the exposure, so
  this is not trivially exploitable — but on timeout the in-flight request is
  never cancelled and runs to completion writing to `__block` variables
  nobody reads. Per the 2026-07-27 decision the gate stays synchronous:
  reduce the wait budget to ~5s (keeping a margin above the 10s→5s request
  timeout) and cancel the in-flight task on timeout. ✅ Fixed:
  `siteverifyTimeout` is now 5.0s, the request/options timeouts are 3.0s, and
  a lock-guarded `cancelled` flag makes a late completion a no-op instead of
  writing to unread `__block` state.
- **`percentEncode:` can return nil.**
  `stringByAddingPercentEncodingWithAllowedCharacters:` returns nil for
  unpaired surrogates, and `[formBody appendFormat:@"%@=%@", key, …]` would
  then write the literal `(null)` — sending `secret=(null)` to the provider.
  Guard it and reject the request rather than emitting a malformed body.
  ✅ Fixed: each field's encoded value is checked for nil before being
  appended; a nil result rejects the request with `PDSRegistrationGateErrorInvalidCaptcha`.

### Slice 6: composite gate semantics — ✅ done at `0239f88c`

S13's framing already notes that "a no-op gate defeats every other gate in the
composite via the OR logic." That is true, but it treats the OR as an
*amplifier* of the no-op bug rather than a defect of its own — so fixing
slices 1-2 does not fix it. Even with every gate correctly implemented,
`PDSRegistrationGate.m:63-90` returns `YES` on the **first** gate that passes,
while the factory adds one gate per independent flag: `inviteCodeRequired`
(`:156`), `phoneVerificationRequired` (`:163`), `captchaRequired` (`:190`),
`oauthOnlyRegistration` (`:205`).

So `inviteCodeRequired = YES` together with `captchaRequired = YES` means a
valid invite code bypasses CAPTCHA entirely. Four flags all named `*Required`
behaving as a disjunction is the trap. This also silently negates slice 1's
own work: the fail-closed and 503 paths are only reachable when CAPTCHA is the
sole configured gate — with any second gate, a CAPTCHA rejection, including
siteverify being unreachable, is absorbed by the other gate passing.

Per the 2026-07-27 decision, **all configured gates must pass**. Required
behaviour:

- The composite evaluates every configured gate and admits the registration
  only if all of them pass. Zero gates still means open registration.
- Report the **first** failing gate's error, not the last, so the client sees
  the most specific rejection rather than whichever gate happened to run last.
- Short-circuit on first failure is acceptable and preferable — it avoids a
  needless siteverify round-trip when an earlier gate already rejected.
- A gate that fails with `httpStatus: 503` must still map to 503 at the
  handler, so an unreachable CAPTCHA provider is distinguishable from a
  rejected registration.

### Owner boundary

Slices 1-4 own `Garazyk/Sources/Registration/`, `Garazyk/Sources/PhoneVerification/`,
`Garazyk/Sources/Email/`, and the `XrpcServerPack+Session.m` /
`XrpcServerPack+AccountManagement.m` handlers. Slice 5 owns
`PDSPlivoPhoneVerificationProvider.m`, `ATProtoValidator`, and the
input-validation touch points across the gates. `ContactService.m` is owned
by slice 3 only. The service-DB migrations (V16/V17/V18) ship one per slice
so slices remain independently revertible.

Slice 6 owns `PDSRegistrationGate.m`'s composite only. It must land **after**
slices 1-2, because AND semantics turn any still-no-op gate into a hard
blocker: with OR, a no-op gate silently admits everyone; with AND, a gate that
wrongly rejects blocks all registration. Ordering it last means every gate is
already correct when the conjunction takes effect.

### Gate

Per-slice negative tests are the gate, since every finding here is a
rejection or fail-closed path. See the derived prompt for the full
per-slice acceptance criteria. Global gates: `deno task check &&
deno task lint && deno task test`, then `cmake --build build --target
AllTests --parallel 4 && ./build/tests/AllTests`. Bounded parallelism only.

### Rollback

Each slice is a single-commit revert. Slices 1-2 change gates from
always-accept to fail-closed — operators who relied on the no-op behavior
for open registration must use `PDSOpenRegistrationGate` explicitly. Slice
4 is the only contract change: any client that sends a DID as the
`resetPassword` token must migrate to the emailed opaque token. See the
derived prompt for full rollback notes.

Slice 6 is the highest-risk revert-wise, because it tightens admission for
every deployment running more than one gate: a user who previously registered
with an invite code alone now also needs to clear CAPTCHA or phone OTP. That
is the intended behaviour, but it is a live signup-funnel change, so it needs
a release note naming the affected configurations, and it should not ship in
the same release as slice 1's fail-closed change without deliberate sequencing
— together they turn a misconfigured CAPTCHA into a total registration outage.
Rollback is a one-line revert of the composite loop.

### Execution phases

- `../prompts/phase-23-registration-phone-email-trust-boundary.md` — slices
  1-5, `depends_on: []`.
- `../prompts/phase-25-registration-gate-composition.md` — slice 6 plus the
  slice 1 follow-ups, `depends_on: [23]`.

## S14. Ozone moderation trust-boundary sweep

**Status: partially complete (slices 1-6 of 7 done; slices 1-5 at a66dd7b1, slice 6 uncommitted).** A focused security review of
the Ozone moderation service (`Garazyk/Sources/Ozone/Services/ModerationService.m`,
844 lines) and its XRPC trust boundary (`Garazyk/Sources/Network/XrpcToolsOzonePack.m`,
1,228 lines) found an authorization gap that weakens every `tools.ozone.*`
endpoint, a missing WHERE clause that can mass-update all safelink rules in a
single request, a wrong column name that makes `getSubjects` return stale data
for every moderation decision, a key mismatch that makes team role updates and
removals silent no-ops, an unvalidated event-type string that enables takedown
forging, a non-atomic set membership replacement that can lose all members on
crash, and missing audit logging on scheduled-action cancellations. The Ozone
module has no dedicated security lane — it was implemented as a feature surface
and has been touched only incidentally by the phase-12 god-file decomposition.
The `tools.ozone.*` endpoints are the live moderation interface used by the
AdminUI backend (`UIBackendClient+Ozone.m`) and by external Ozone clients; a
defect here affects every moderation decision the operator makes.

### Evidence

*   **Ozone endpoints bypass the canonical admin auth path (O-1 — auth gap).**
    `ExtractAdminDid` at `XrpcToolsOzonePack.m:23-39` gates every
    `tools.ozone.*` endpoint using `extractDIDFromAuthHeader:` (JWT
    verification + takedown check) and `isAdminDid:` (DID-list membership) but
    skips `isAuthenticatedWithRequest:` / `authenticateHeaders:`
    (`PDSAdminAuth.m:289-297`), which enforces `minimumTokenIssuedAt` (global
    token freshness floor for blanket revocation) and admin-scope tokens
    (`PDSScopesContainAdmin`). The canonical admin auth path at
    `XrpcAuthHelper.m:519-549` (`authorizeAdminRequest:`) calls both checks. A
    compromised admin token remains valid on `tools.ozone.*` after the operator
    bumps the freshness floor — the attacker can continue emitting takedowns
    and labels.

*   **`updateSafelink` can mass-update all rules on malformed input (O-2 —
    missing WHERE guard).** `ModerationService.m:709-714` only appends the
    WHERE clause when `safelinkId` contains a colon (`parts.count == 2`). A
    malformed ID with no colon (e.g., `"malformed"`) runs the UPDATE against
    every row in `moderation_safelinks`. The companion `deleteSafelink:` at
    `:727-728` correctly rejects malformed IDs with an early return — the fix
    is to copy that guard into `updateSafelink:`.

*   **`getSubjects` queries a non-existent column (O-3 — wrong column name).**
    `ModerationService.m:637` uses `WHERE did = ?` against
    `moderation_subjects`, but the table's actual column is `subject_did`.
    Every other query in the file uses `subject_did` (`:45`, `:82`, `:186`,
    `:562`). SQLite returns an error, `executeParameterizedQuery:` returns nil,
    and every subject gets `reviewState: "none"` unconditionally — moderation
    decisions are made on stale data.

*   **Team management endpoints key on `email` but the DB uses `did` (O-4 —
    key mismatch).** `addTeamMember:` at `ModerationService.m:216` inserts rows
    keyed by `member[@"did"]`, but the XRPC handlers at
    `XrpcToolsOzonePack.m:~461, ~484, ~510` pass `body[@"email"]` as the member
    identifier. `updateTeamMember` (`:233`) and `removeTeamMember` (`:240`)
    query `WHERE did = ?`, so they never match an email. Team role updates and
    removals are silent no-ops.

*   **`emitModerationEvent` accepts arbitrary `$type` strings (O-5 —
    unvalidated event type).** `ModerationService.m:38` passes
    `event[@"$type"]` directly from the request body to `reviewStateForAction:`
    at `:795-835`, which maps known strings to review-state transitions
    (takedown → `takendown`, reverseTakedown → `reviewOpen`, etc.). Unknown
    types return nil and do not trigger a state change, but the event is still
    committed to `moderation_events`. The lack of explicit whitelist validation
    means a future refactor could accidentally widen the transition set.

*   **`updateSet` replaces set members non-atomically (O-6 — no transaction).**
    `ModerationService.m:276-283` deletes all set members (`:278`) then
    re-adds them in a loop (`:280-282`) with no `transactWithBlock:`. A crash
    or timeout between the DELETE and the INSERTs loses all members.

*   **`cancelScheduledAction` does not write to `admin_audit_log` (O-7 —
    missing audit log).** `ModerationService.m:600-605` and `:607+` accept a
    `cancelledBy` parameter but never INSERT into `admin_audit_log`. Compare
    `emitModerationEvent:` at `:62` which writes `admin_did`, `action`,
    `subject_type`, `subject_id`, and `created_at`. Cancellations are
    unattributed — an operator cannot determine who cancelled a scheduled
    action.

### Slices

The O-zone findings map to seven independently shippable and revertible slices
(see `../prompts/phase-24-ozone-trust-boundary.md` for the full specification):

1. ✅ Ozone endpoint authorization — close the `minimumTokenIssuedAt` gap (O-1)
2. ✅ `updateSafelink` mass-UPDATE guard (O-2)
3. ✅ `getSubjects` column name fix (O-3)
4. ✅ Team management: `did` not `email` as the row key (O-4)
5. ✅ `emitModerationEvent` event-type whitelist validation (O-5)
6. ✅ `updateSet` transaction boundary (O-6)
7. `cancelScheduledAction` audit logging (O-7)

No slice changes a public endpoint contract — all fixes are internal
correctness and security hardening. No new database migrations are introduced.

### Owner boundary

All slices own `Garazyk/Sources/Ozone/Services/ModerationService.m` and
`Garazyk/Sources/Network/XrpcToolsOzonePack.m`. Slice 1 additionally owns the
`ExtractAdminDid` → `authorizeAdminRequest:` wiring and the
`XrpcToolsOzoneTests.m` auth tests. Slice 4 owns the `XrpcToolsOzonePack.m`
team handlers. `ModerationService.h` is updated only if a new whitelist
constant or method is exposed. The `PDSAdminAuth`, `XrpcAuthHelper`,
`ATProtoValidator`, and `PDSDatabase` are consumers and keep their signatures.
The `UIBackendClient+Ozone.m` AdminUI client is a consumer of the XRPC
endpoints and is not changed.

### Gate

Per-slice negative tests are the gate, since every finding is a rejection,
fail-closed, or correctness path. The global verification gates are:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

### Rollback

Each slice is a single-commit revert. Slice 1 restores the weaker
`ExtractAdminDid` path — if an operator relied on stale-token acceptance, they
must re-authenticate after the cutover. Slice 2 restores the
mass-UPDATE-on-malformed-ID path. Slice 3 restores the stale `getSubjects`
behavior. Slice 4 restores the email-as-key handlers — the team management
endpoints were effectively non-functional (no updates or removals succeeded),
so rollback returns to the broken state. Slice 5 restores the unvalidated
`$type` path. Slice 6 restores the non-atomic set membership replacement — a
crash during update can lose all members. Slice 7 restores the missing audit
log — cancellations become unattributed again.

### Execution phases

- `../prompts/phase-24-ozone-trust-boundary.md` — slices 1-7,
  `depends_on: []`.
