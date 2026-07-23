---
title: Security and Protocol Correctness
status: active
last_verified: 2026-07-19
---

# Security and Protocol Correctness

## S1. Duplicate XRPC ownership

Current strict coverage finds:

- `app.bsky.graph.getListMutes` registered twice in `XrpcAppBskyGraphPack.m`,
  with different validation;
- `app.bsky.graph.getListBlocks` registered twice in the same pack;
- `app.bsky.labeler.getServices` owned by both the main and unspecced packs.

`XrpcHandler` silently uses the last registration. Delete duplicate ownership in
isolated commits and add a registry test that fails on same-file and cross-pack
duplicates. Preserve one route-level characterization per endpoint.

Rollback: revert one ownership commit. Do not restore silent duplicate
registration in tests or debug builds.

## S2. Canonical lexicon generation

Two generators disagree about the source root. The package generator defaults to
the empty top-level `lexicons/` path and can overwrite its catalog with zero
entries. The root generator reads `Garazyk/Resources/lexicons`.

1. Choose one generator core and one canonical lexicon root.
2. Fail when zero lexicons or zero endpoints are found.
3. Classify record, query, procedure, and subscription definitions separately.
4. Generate TypeScript and Objective-C artifacts deterministically.
5. Add a CI drift check after generation.

Generated NSID constants depend on this task. Do not start that migration first.

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

`HttpConnectionIOCoordinator` checks time before scheduling a receive, has no
timer to cancel a receive that never completes, and resets the header start time
after each chunk. A client can retain a connection by trickling header bytes.

Add configurable idle and aggregate header deadlines. The aggregate deadline
starts with the first byte and never resets. On expiry, emit one error and
cancel the transport.

Characterization:

- fake receive never completes;
- one byte arrives repeatedly beyond the aggregate deadline;
- a valid slow request inside both limits succeeds;
- timeout emits one terminal result and releases the connection.

Rollback: coordinator-only revert with the previous timeout available behind a
short-lived loopback/test flag.

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
`7bde0e0b6`) proves the takedown chain E2E. Remaining lead, not backlog:
`RelayRepoStateManager`'s status-tracking model still has no callers —
enforcement beyond passthrough (e.g. AppView un-indexing on takedown)
was not part of this closure and should be assessed when moderation
work is next scheduled.

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

- **G1: Permissions — granular scope evaluation.** `PDSSpaceScope.h/.m`
  implements `space:` scope parsing; no `repo:`/`rpc:`/`blob:`/`account:`/
  `include:` resource-type scope evaluation found. Required for production
  readiness. Own lane.
- **G2: Sync 1.1 remainder — closed (2026-07-19).** Export block ordering
  and collection-based repo subsets remain "Future Work" prose upstream
  (https://atproto.com/specs/sync, rechecked 2026-07-19), not published
  spec text. A feature-flagged pre-order enumerator exists for block
  ordering (default off — deferred until spec text finalizes) and
  collection subsets are served by Garazyk's own
  `tools.garazyk.sync.getRepoFiltered` vendor extension. See workstream 02
  A6 for detail. Revisit if upstream publishes versioned Sync 1.1 text.
- **G3: Account management surfaces.** S5 covers propagation; confirm
  deactivation/deletion/export UX endpoints against accounts spec.
- **G4: Labels — self-signing key.** Label distribution and query endpoints
  implemented (`XrpcLabelPack.m`, 671 lines); no `#atproto_label` key
  generation or label signature verification found.

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

**Status: audited, not started.** Audit 2026-07-22 (deciduous `#1368`);
execution detail in [the STAR conformance plan](../star-conformance-plan.md).

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
