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

**Known flake (pre-existing, not one of the 11 above):**
`ATProtoVideoTranscoderIntegrationTests/testTranscodeInvalidURLError`
SIGSEGV'd once under `ctest -R '^AllTests$'` on 2026-07-17
(`EXC_BAD_ACCESS`/`objc_storeStrong` inside the test's own frame — a
use-after-free, not a hang or OOM). Crash reports from three earlier runs
this same day (21:47, 22:12, 22:15), all before this session's changes,
show the same signature, so it predates and is unrelated to the S5 repair.
Two direct-binary and one ctest retry ran clean immediately after, so it
reproduces intermittently rather than reliably. Filed as a follow-up
(memory-safety bug in `ATProtoVideoTranscoder`'s synchronous transcode
error path); investigating it needs ASan, which is beyond this slice.

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
- **G2: Sync 1.1 remainder.** Export block ordering and collection-based
  repo subsets still in-progress upstream. Track alongside workstream 02 A6.
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
