---
title: Security and Protocol Correctness
status: active
last_verified: 2026-07-17
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

**Regression discovered 2026-07-19 (during phase 8):** a full
`AllTests --gated=run` (`build/tests/AllTests --gated=run`, full log
`/tmp/alltests_phase8_gated.log`) is no longer clean — 12 suites now fail,
roughly 68 individual assertion failures, contradicting the 2026-07-17
"3454 tests, 0 failures" baseline above. None of the failing suites or
files were touched by phase 8 (Admin UI/dashboard accessibility); this is
tracked here rather than in the phase-08 prompt. Two root causes
identified, the rest undiagnosed:

- **DID-format/fixture mismatch (majority of failures):**
  `PDSSQLiteRepositoryTests`, `PDSDatabaseWebAuthnTests`,
  `PDSDatabaseModerationTests`, `PDSDatabaseAdminAuditTests`,
  `PDSDatabaseOAuthClientsTests`, `PDSSequencerAnalyticsCollectorTests`,
  `AppViewIndexerTests` all fail with `"Invalid DID for actor store path"`
  or downstream nil/zero-count assertions. Root cause:
  `+[ATProtoValidator validateDID:error:]`
  (`Garazyk/Sources/.../ATProtoValidator.m`) requires `did:plc:`
  identifiers to be exactly 24 lowercase-base32 characters; test fixtures
  like `kTestDID = @"did:plc:repo123"` (7 chars) don't conform, so
  `-[PDSDatabasePool dbPathForDid:]` refuses them. Both the validator
  logic and the offending fixtures predate this session by many commits
  (`07c96d421`, `65abe6e6f`) — this is old debt, not a new regression in
  the code itself, but something changed to make it actually execute now
  (see below).
- **`MSTPreorderTests/testRefusesWhenFlagOff`:** fails deterministically
  (reproduced 3/3 in isolation via `--filter "MSTPreorderTests*"`) with an
  assertion message (`"Pre-order walk (records disabled) must succeed"`)
  that belongs to a different helper (`capturePreorderMSTOnly:`) than the
  one the failing test actually calls — either a test-name-attribution bug
  in this project's custom `test_main` runner, or genuine cross-test state
  leakage via the shared static `MST.streamableCARBlockOrderingEnabled`
  flag. From phase 7's Sync 1.1 pre-order work (`ed01c8085`); needs its
  own investigation.
- **Undiagnosed:** `AtprotoInteropFixturesTests` (1/5),
  `OAuthClientAuthPolicyTests` (1/30),
  `ATProtoVideoProcessorTests`/`ATProtoVideoTranscoderUnitTests`
  (MPEG signature validation, blob-provider default).

Working theory for why long-standing fixture debt is newly visible: these
suites may not have been reaching `--gated=run` execution before (compare
the "new XCTest suites need cmake reconfigure + `test_main.m`
registration, else 0 tests silently run" trap already noted in this
repo's operational lore) rather than a code change breaking previously-
passing tests. Not confirmed — needs a bisect, which is out of scope for
phase 8. Own lane.

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
