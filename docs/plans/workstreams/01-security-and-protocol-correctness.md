---
title: Security and Protocol Correctness
status: active
last_verified: 2026-08-12
---

# Security and Protocol Correctness

Exposed control surfaces, HTTP bounds, XRPC contracts, and federation tests.

The completed items' full detail — evidence, slices, decisions, gates, and
rollback notes — moved to [the completed-items archive](../../archive/planning/workstream-01-completed-items.md)
on 2026-08-05, unchanged. Open item: the S5 residual watch item. S21
(`listRecords` cursor pagination) is complete (2026-08-12).

## Status summary

| Item | Scope | Status |
| --- | --- | --- |
| S1 | Duplicate XRPC ownership | Complete (2026-07-26) |
| S2 | Canonical lexicon generation | Complete (2026-07-26) |
| S3 | Truthful XRPC coverage | Complete, report-only (2026-07-17) |
| S4 | Absolute HTTP deadlines | Complete (2026-07-26) |
| S5 | Functional federation and lifecycle checks | Complete (2026-07-24); **one watch item open**, below |
| S6 | Published-spec conformance matrix | Complete, report-only; G3 and G5 closed (2026-08-08) |
| S7 | STAR conformance and verifying import | Complete (2026-07-23), ADR 0009 |
| S8 | Untyped JSON at auth trust boundaries | Complete (2026-07-27), 7 slices, 3 ADRs |
| S9 | Blob lifecycle and storage-pool correctness | Complete (2026-07-27), phases 15–16 |
| S10 | WebSocket framing and outbound egress hardening | Complete (2026-07-27), phases 17–18 |
| S11 | Core decoder bounds, secret storage, destructive CLI | Complete (2026-07-27) |
| S12 | MST viewer gating and dead admin credential surface | Complete (`6bce0725`, `65bc7ebe`) |
| S13 | Registration, PhoneVerification, Email sweep | Complete, 10 slices (ADRs 0020, 0022, 0030) |
| S14 | Ozone moderation sweep | Complete, 7 slices (`a66dd7b1`, `cf23deba`) |
| S15 | Chat (`syrena-chat`) sweep | Complete, 7 slices |
| S16 | Video + Germ/Mikrus/Beskid sweep | Complete, 5 slices (HEAD `92f0c8b4`) |
| S17 | Admin + AdminUIServer sweep | Complete (2026-07-29, `e340d6de`) |
| S18 | Auth-verifier protocol extraction | Complete (2026-07-29, `1013aa88`, `d47443f5`) |
| S19 | DAG-CBOR routing migration | Complete (2026-07-29) |
| S20 | HTTP transport crash-safety and request boundaries | Complete (2026-07-29), sub-tasks A–E |
| S21 | `com.atproto.repo.listRecords` cursor pagination | **Complete** (2026-08-12) |
| S22 | OAuth `prompt=create` signup + legacy key-seal migration | **Complete** (2026-08-16) |

## Open: S5 residual — `PDSDatabase` null-pointer flake (watch item)

Carried forward verbatim from S5, which is otherwise closed. This is the only
unresolved defect left in this workstream.

A null-pointer SIGSEGV (`EXC_BAD_ACCESS` / `KERN_INVALID_ADDRESS` at `0x0`)
inside `-[PDSDatabase(Private) safeExecuteSync:]` (`PDSDatabase.m:48`), called
from `-[PDSDatabase openWithError:]` (`PDSDatabase.m:122`). Seen three times on
2026-07-16 — once from `PDSDatabaseBlobsTests/testGetBlobsForDidWithPagination`
(21:47) and twice from `PDSDatabaseLRUTests setUp` (22:12, 22:15). Originally
misattributed to a different crash signature. Possibly related to disk pressure
given `PDSDatabase`'s use of SQLite, but never confirmed.

**Mitigated but open (2026-07-26 verification).** Auditing `openWithError:` for
this flake found and fixed three concrete contract bugs on the same path: a
failed `sqlite3_open` never closed SQLite's error-holding handle and left `_db`
non-NULL; `createSchema:` failure — the exact `SQLITE_FULL` disk-pressure shape
— was ignored, so `openWithError:` returned YES on a database with missing
tables; and `setWalMode:`/`setPerformanceOptimizations:` failures wrote `*error`
alongside a YES return. `PDSDatabaseOpenFailureTests` now pins the failed-open
cleanup. The original `0x0` crash never reproduced, so its most plausible
mechanisms on this path are closed but the underlying defect is unproven.

**Recheck (2026-08-12):** `PDSDatabaseOpenFailureTests` (2),
`PDSDatabaseBlobsTests` (8, including `testGetBlobsForDidWithPagination`), and
`PDSDatabaseLRUTests` (6) all passed with 0 failures under `--gated=run`. No
`EXC_BAD_ACCESS` / `0x0` reproduction. Watch item remains open until a future
crash report proves a distinct mechanism.

Next step if it recurs: capture the crash report and diff against the three
closed mechanisms before assuming disk pressure. Related context:
[Garazyk disk pressure](../../../CLAUDE.md) notes that full `--gated=run` runs
fail with `SQLITE_FULL` near disk capacity.

## Complete: S6 gap G3 — Relay `getRepoStatus` status semantics

The checked-in `com.atproto.sync.getRepoStatus` lexicon permits `status` to be
absent for an inactive repository and does not list Relay's private
`in-progress` state. `RelayXrpcRoutePack` now reports that state as
`active: false` without a `status`; it continues to map desynchronized,
throttled, and tombstoned states to the checked-in known values
`desynchronized`, `throttled`, and `deleted`. Active repositories include a
`rev` when known.

`RelayXrpcRoutePackTests` covers the exact response shape for every Relay
status, unknown repositories (inactive/desynchronized), and active `rev`
output.
Source/static evidence passed on 2026-08-08: `deno task check && deno task lint
&& deno task test` (1,264 passed), module-boundary, recursive-setter,
no-host-process-exit, generated-NSID, skill-index, NSID-registration-literal,
and source-only XRPC coverage gates. After integration, the native
`RelayXrpcRoutePackTests` suite passed 18/18.

Report-only: a red row is a lead, not a release blocker, until triaged into a
workstream. Rollback is documentation-only until a gap lane starts; each gap
lane carries its own rollback notes.

Primary sources:

- [Specification index](https://atproto.com/specs/atp)
- [Account lifecycle](https://atproto.com/specs/account)
- [Event streams](https://atproto.com/specs/event-stream)
- [Synchronization](https://atproto.com/specs/sync)
- [OAuth profile](https://atproto.com/specs/oauth)
- [Permissions](https://atproto.com/specs/permissions)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)

## Complete: S6 gap G5 — Relay repository-commit signature integrity

**Source evidence (rechecked 2026-08-08).** The untrusted
`FirehoseCommitEvent` enters
`Garazyk/Sources/Sync/Relay/RelayEventValidator.m:validateCommitEvent:`. Before
this slice, the method checked only `repo` and `commit`, resolved the DID
document, and decoded the advertised signing key, but returned a valid outcome
without decoding the signed repository-commit block or calling
`RepoCommit verifySignatureWithPublicKey:error:`. A forged signed-commit block
can therefore retain a matching advertised CID while its signature is invalid.
`PDSRepoImportValidator validateCommitSignature:…` is the existing comparison
path, but it privately accepts both published DID layouts:
`verificationMethods.atproto` as `did:key:` and the `verificationMethod`
`#atproto` `publicKeyMultibase` entry. The relay must support those forms, not
assume all DID document keys can be interpreted ad hoc.

**Owner and boundary.** Workstream 01 S6 owns the security/protocol outcome.
Implementation is confined to the `ATProtoSync` relay ingress boundary, its
shared protocol-key extraction primitive, and `zuk` composition, which already
owns `DIDPLCResolver` for Relay XRPC. `RepoCommit` remains the sole
repository-signature verifier. Do not make `ATProtoSync` depend on the
PDS/Network importer or duplicate DID-key parsing.

**Delivery and gate.** Add focused valid, tampered, wrong-key, and unresolved-
key commit-event tests, plus lenient/log-only/strict forwarding assertions.
The shared path must decode the signed commit addressed by the event CID,
require its `did` to equal `event.repo`, resolve an accepted `#atproto` key
form, and return `RelayValidationResultInvalidSignature` for every key,
decode, or verification failure. `zuk` must create one `DIDPLCResolver`, pass
it to `RelayEventValidator` created with the parsed validation mode, and install
that validator on `RelayDownstreamHandler`; a narrow Zuk source/composition
assertion guards the wiring. Every `InvalidSignature` outcome must increment
the signature-failure metric through one factory helper. Only secp256k1
repository keys are implemented; an unsupported P-256 key must fail as an
unsupported key, not be passed to the secp256k1 verifier. Run the focused
native suite, module-boundary and applicable source-security gates; run the
full native gate only when disk headroom permits it.

**Implementation and evidence (2026-08-08).** `RelayEventValidator` now
parses the CAR block addressed by the advertised commit CID, recomputes that
CID, decodes `RepoCommit`, binds its `did` to `event.repo`, and verifies the
signature. `ATProtoDIDDocumentFields` now owns the strict `#atproto`
secp256k1 key primitive, including both legacy `did:key:` and modern
`publicKeyMultibase` layouts; `PDSRepoImportValidator` was moved onto that same
primitive. P-256 repository keys are rejected as unsupported; no P-256
verification path is claimed. `zuk` now constructs one `DIDPLCResolver`,
creates `RelayEventValidator` with the parsed mode (log-only by default),
assigns the resolver, installs it on `RelayDownstreamHandler`, and reuses the
resolver for Relay XRPC. `invalidSignatureOutcome:` is the sole
`InvalidSignature` factory and increments `recordSignatureValidationFailure`
before returning the outcome. `RelayEventValidatorTests` adds legacy/modern
valid cases plus matching-CID tampering, wrong-key, unresolved-key, P-256
rejection with metric assertion, and all three forwarding-mode cases;
`ZukCommandTests` adds a narrow source composition assertion.

Passed: `deno task check && deno task lint && deno task test` (1,264 passed,
0 failed, 1 ignored); `scripts/dev/check_module_boundaries.sh .`;
recursive-setter; no-host-process-exit; NSID generation; skill-index;
NSID-registration-literal; source-only XRPC coverage; repository-doc
validation; and `git diff --check`. After integration on `main`, focused native
suites passed: `RelayEventValidatorTests` 15/15, `ZukCommandTests` 5/5,
`RepoAuthRepoTests` 25/25, `ATProtoDIDDocumentFieldsTests` 5/5, and
`ATProtoMultibaseTests` 2/2. The full gated native suite was not run with only
13 GB free.

**Availability policy and rollback.** Outcomes are truthful in every mode:
`strict` drops an invalid commit, while `lenient` and `log-only` continue to
forward it and preserve their existing metrics/log behavior. Rollback is a
single revert of the relay call site and shared extractor; it restores the
previous availability-first forwarding policy but knowingly reopens forged-
commit acceptance. Do not revive the superseded relay continuity graph as a
backlog; this lane is represented only here and in the current graph action.

## Complete: S21 — `com.atproto.repo.listRecords` cursor pagination

**Closed 2026-08-12.** Keyset pagination on `rkey` now matches Bluesky PDS
semantics for the ordinary repo endpoint (space-side cursors were already
fixed in ADR 0005).

### What shipped

- `PDSActorStore` keyset API:
  `listRecordsForDid:collection:limit:cursor:reverse:error:`
  (`ORDER BY rkey DESC` by default; exclusive `rkey < cursor` / `rkey > cursor`
  when reverse).
- `PDSRecordService` pages through that API (no full-collection load + truncate)
  and exposes `nextCursor` when `records.count == limit`.
- `XrpcRepoPack+Records` returns `{ records, cursor? }` with lexicon-shaped
  record views (`uri`, `cid`, `value`) and honors `reverse`.
- Default first-page order changed from ASC to **DESC** for protocol parity.

### Evidence

Commit `d179ae3a`.

```text
./build/tests/AllTests -f 'PDSRecordServiceTests' -f 'ActorStoreTests' --gated=run
  → 73 tests, 0 failures (includes testListRecordsWithCursorPagination,
     testListRecordsKeysetPaginationCoversAllRkeys)
```

### Remaining optional follow-ups (not blockers)

- Teach the STAR-lite export benchmark to optionally verify against a full
  `listRecords` walk.
- Deprecated lexicon params `rkeyStart` / `rkeyEnd` left unimplemented (no
  known Garazyk client sends them).

## Complete: S22 — OAuth `prompt=create` signup + legacy key-seal migration

### What shipped

- `POST /oauth/authorize/signup`: account creation inside the OAuth authorize
  flow for requests carrying `prompt=create` (the ATProto client-signup path,
  e.g. witchsky's `client.signIn(serviceUrl, {prompt: 'create'})`).
  `OAuth2Handler+Authorization.m` — `handleAuthorizeSignup:response:` validates
  CSRF + fields, runs the same `PDSRegistrationGate` invite check as XRPC
  `com.atproto.server.createAccount`, calls `createAccountForEmail`,
  initializes the repo, and returns a pending-consent session token. The
  authorize page (`authorize.html`) now interpolates `{{prompt}}` /
  `{{invite_required}}` and shows a signup step (handle/email/password/invite)
  when `prompt=create`; on success it transitions to the consent step. The
  handler is wired with `registrationGate` + `repositoryService` in
  `ATProtoHttpOAuthRoutePack.m`.
- Rotation-key seal migration: `PLCRotationKeyManager` retries the versioned
  envelope with the pre-2026-05-12 PBKDF2 derivation (100k iterations) when the
  current 600k key fails, then re-seals with the current key. Fixes deployments
  whose `plc_rotation_key.bin` predates the 600k bump, which otherwise failed
  with "Failed to decrypt rotation key" on every account creation.

### Evidence

- `OAuth2HandlerTests` 31→35, 4 new signup tests pass (full flow, missing
  fields, bad CSRF, invite gate). Pre-existing 5 failures (issuer env var +
  JWT-assertion `privateKey != NULL`) reproduce on pristine HEAD.
- `PLCRotationKeyManagerTests` 5/5 pass.
- Live E2E against `pds.garazyk.xyz`: PAR (DPoP + nonce) → 201; authorize page
  renders signup step with `promptMode = "create"`; signup POST → 200 account
  created (`did:plc:*`); consent → 302 with `code`; token exchange (DPoP +
  PKCE) → 200 DPoP-bound access + refresh token.
- Live verification: `plc_rotation_key.bin` re-sealed and decrypts under the
  current 600k derivation.
- Gates: `check_module_boundaries.sh build-linux`, `check_namespace.sh
  build-linux`, `check-recursive-setters.sh`, `check_no_host_process_exit.sh`
  all pass.

### Remaining follow-ups

- Confirm the full witchsky client flow in a real browser (Playwright MCP
  pending client restart).
- Invite codes: E2E testing consumed two admin-created codes; a fresh
  admin-created invite is active on the deployment for manual testing.

## Cross-workstream note

S18 and S19 were the two sub-items activated alongside mega-plan Phase 4 from
[the 2026-07-28 security review](../security-review-2026-07-28.md); both are
complete. S19's consumer table row 10 was later corrected by
[workstream 10](10-dasl-conformance.md) Phase 3, which found `Repository/CAR.m`
was not importer-only and migrated its header decoder for real.
