---
title: Published-Spec Conformance Matrix
status: report-only
last_verified: 2026-07-23
commit: fe5760967d629bb2f71824132ebdde0417ce515c
---

# Published-Spec Conformance Matrix

## Purpose

Maps every published AT Protocol specification page to implementation
evidence in the Garazyk codebase. Each row records: support level, the tests
or scenarios that prove it, and the owning workstream for any gap.

A red row is a lead, not a release blocker, until triaged into a workstream.

## Support levels

- **Supported** — implementation exists, executable proof found.
- **Partial** — implementation exists for core paths; known gaps remain.
- **Gap** — no implementation found, or implementation is stub/placeholder.

## Matrix

| # | Spec | Status | Implementation | Executable proof | Owning workstream |
|---|------|--------|----------------|-----------------|-------------------|
| 1 | [Data Model](https://atproto.com/specs/data-model) | Supported | `ATProtoDagCBOR.h/.m`, `ATProtoCBORSerialization.h/.m`, `CBOR.h/.m` (DAG-CBOR canonical encoding, DRISL type mappings, `$type`/`$bytes`/`$link`), `CID.h/.m`, `NSDictionary+CID.h/.m` (CID v1 SHA-256) | `CBORSecurityTests.m`, `CARInteropTests.m`; scenario 28 (repo format benchmarks) | 01 (S3) |
| 2 | [Lexicon](https://atproto.com/specs/lexicon) | Supported | `ATProtoLexiconRegistry.h/.m`, `ATProtoLexiconSchema.h/.m`, `ATProtoLexiconValidator.h/.m`, `ATProtoLexiconConstraints.h/.m`, `ATProtoLexiconDef.h/.m`, `ATProtoLexiconError.h/.m`, `XrpcLexiconResolver.h/.m`; lexicon JSON under `Garazyk/Resources/lexicons/` | `XrpcInputValidationTests.m`, `XrpcHandlerTests.m`; XRPC coverage report (213/213 in-scope, 100%); CI gate `--fail-on-duplicates --fail-on-missing` | 01 (S2, S3) |
| 3 | [Cryptography](https://atproto.com/specs/cryptography) | Supported | `AuthCryptoECDSA.h/.m` (p256/k256 ECDSA), `AuthCryptoJWK.h/.m` (multikey/did:key), `AuthCryptoBase64URL.h/.m`, `JWT.h/.m` (ES256/ES256K), `CryptoUtils.h/.m`, `DPoPUtil.h/.m` | `CryptoTests.m`, `JWTTests.m`, `JWTSecurityTests.m`, `AuthCryptoTests.m`, `KeyManagerSecurityTests.m` | 01 |
| 4 | [Accounts](https://atproto.com/specs/account) | Supported | `PDSAccountService.h/.m`, `PDSAccountEvents.h/.m`, `PDSAccountRepository.h`, `PDSDatabase+Accounts.h/.m`, `PDSActorStore+Account.h/.m`; hosting status, activation, deactivation, takedown, downstream `#account` event propagation (takedown/reinstate → firehose → RelayClient/RelayUpstreamManager forwarding → AppViewIngestEngine persistence), gap-free cursor resume | `PDSAccountServiceTests.m`; scenarios 01 (account lifecycle), 12 (account migration), 96 (cursor resume), 97 (downstream account-status propagation); S5 lifecycle propagation complete | 01 (S5) |
| 5 | [Repository](https://atproto.com/specs/repository) | Supported | `MSTAtomicReference.h/.m`, `MSTCacheManager.h/.m`, `MSTViewerHandler.h/.m`; commit signing, MST tree, CAR import/export via `FirehoseCARBuilder.h/.m`; repo write/delete/apply operations | `MSTDiffTests.m`, `MSTInteropTests.m`, `MSTPersistenceTests.m`, `MSTRebalancingTests.m`, `MSTUTF8Tests.m`, `RepoCommitTests.m`, `CARInteropTests.m`; scenario 28 | 01 |
| 6 | [Blobs](https://atproto.com/specs/blob) | Supported | `BlobStorage.h`, `PDSBlobRepository.h`, `PDSBlobAuditManager.h/.m`, `PDSBlobCIDVerificationOperation.h/.m`, `PDSBlobConsistencyCheckOperation.h/.m`, `PDSBlobOrphanScanOperation.h/.m`, `PDSBlobReferenceScanOperation.h/.m`; upload-before-reference, GC, CID verification | `PDSBlobServiceTests.m`, `PDSBlobAuditManagerTests.m`; scenario 07 (blobs/uploads) | 01 |
| 7 | [Labels](https://atproto.com/specs/label) | Partial | `XrpcLabelPack.h/.m` (671 lines: `subscribeLabels`, `queryLabels` endpoints); label header parsing (`atproto-accept-labelers`, `atproto-content-labelers`); no self-signing `#atproto_label` key generation found | scenario 45 (labeler subscription), scenario 85 (labeling endpoints); no unit test for label signature verification | 01 (S3) |
| 8 | [XRPC](https://atproto.com/specs/xrpc) | Supported | `XrpcHandler.h/.m`, `XrpcMethodRegistry.m`, `XrpcRoutePackRegistrar.m`, `ATProtoHttpXrpcRoutePack.m`; 25+ pack files; dynamic AppView routes via `AppViewLexiconEndpointGenerator.m`; 350 implemented methods, 213 in-scope, 100% coverage | `XrpcHandlerTests.m`, `XrpcInputValidationTests.m`, `XrpcErrorResponseTests.m`, `GetServiceAuthMethodTests.m`, `AdminModerationAuthTests.m`; CI coverage gate; scenario suite (94 scenarios) | 01 (S1, S3) |
| 9 | [OAuth](https://atproto.com/specs/oauth) | Supported | `OAuth2.h/.m`, `OAuth2Handler.h/.m`, `OAuthProvider.h/.m`, `OAuthSession.h/.m`, `OAuthClientAuthPolicy.h/.m`, `OAuthServerMetadata.h/.m`, `PKCEUtil.h/.m`, `DPoPUtil.h/.m`, `AuthCryptoDPoP.h/.m`, `AppViewOAuth2Middleware.h/.m`; PAR, PKCE, DPoP, server metadata, introspection, client registration | `OAuth2Tests.m`, `OAuth2HandlerTests.m`, `OAuthDPoPTests.m`, `OAuthConformanceTests.m`, `OAuthIntegrationTests.m`, `OAuthMetadataComplianceTests.m`, `OAuth2IntrospectionTests.m`, `OAuth2OPTIONSHandlerTests.m`, `OAuth2PreservationTests.m`, `OAuth2ATProtoClientTests.m`, `OAuth2ClientMetadataValidationTests.m`; scenarios 08, 11, 13 | 01 |
| 10 | [Permissions](https://atproto.com/specs/permission) | Partial | `PDSSpaceScope.h/.m` (space: scope parsing for permissioned spaces); transitional scopes present; fail-closed `space:` scope parser; **no granular `repo:`/`rpc:`/`blob:`/`account:`/`include:` scope evaluation found** (full gap assessment at `docs/reports/permissions-spec-gap-assessment.md`) | `PDSSpaceURIAndScopeTests.m`; no test for granular resource-type scope evaluation | 01 (S6 known gap G1) |
| 11 | [Event Stream](https://atproto.com/specs/event-stream) | Supported | `Firehose.h/.m`, `FirehoseProtocolSession.h/.m`, `SubscribeReposHandler.h/.m`, `FirehoseCARBuilder.h/.m`; `#commit`, `#identity`, `#account`, `#handle` events; WebSocket framing, sequence numbers, cursors | `FirehoseTests.m`, `FirehoseConformanceTests.m`, `FirehoseProtocolSessionTests.m`, `SubscribeReposHandlerTests.m`, `EventFormatterTests.m`; scenario 09 (firehose streaming), 25 (firehose fanout scale) | 01 (S5) |
| 12 | [Sync](https://atproto.com/specs/sync) | Partial | `XrpcSyncPack.h/.m` (getRepo, getRecord, listRepos, subscribeRepos, getBlocks, getLatestCommit, listReposByCollection); `PLCSyncClient.h/.m`, `PLCSyncEngine.h/.m`; relay infrastructure (`RelayAPIHandler`, `RelayClient`, `RelayUpstreamManager`, `RelayEventBuffer`); **export block ordering and collection-based repo subsets not yet spec-final upstream** | `RelayAPIHandlerTests.m`, `RelayClientTests.m`, `RelayIntegrationTests.m`, `RelayUpstreamManagerTests.m`, `RelayEventBufferTests.m`, `RelayEventFilterTests.m`, `RelayEventValidatorTests.m`, `RelayRepoStateManagerTests.m`, `RelayDownstreamHandlerTests.m`; scenario 05 (federation) | 02 (A6) |
| 13 | [DID](https://atproto.com/specs/did) | Supported | `DID.h/.m` (did:plc, did:web resolution), `DIDPLCResolver.h/.m`, `ATProtoDIDDocumentFields.h/.m`; DID document parsing, verification key extraction | `DIDPLCResolverTests.m`; scenario 05 (federation), 91 (server/repo identity) | 01 |
| 14 | [Handle](https://atproto.com/specs/handle) | Supported | `ATProtoHandleValidator.h/.m` (DNS hostname subset validation), `HandleResolver.h/.m` (DNS TXT, HTTPS well-known); bidirectional DID-handle verification | `HandleResolverSecurityTests.m`; scenario 05 (federation) | 01 |
| 15 | [NSID](https://atproto.com/specs/nsid) | Supported | `ATProtoValidator.h/.m` (NSID parsing/validation); NSID constants used throughout XRPC packs and lexicon registry; no dedicated NSID module file | NSID validation exercised via `XrpcInputValidationTests.m`, lexicon registry tests; XRPC coverage CI gate | 01 |
| 16 | [TID](https://atproto.com/specs/tid) | Supported | `TID.h/.m` (TID generation, parsing, comparison); used in record keys, commit revisions, firehose events | TID implicitly tested via `RepoCommitTests.m`, `FirehoseTests.m`, `SubscribeReposHandlerTests.m` | 01 |
| 17 | [Record Key](https://atproto.com/specs/record-key) | Supported | Record key validation and generation within `ActorStore.h/.m` (rkey parameter), `PDSDatabaseRecord.m`, `PDSRecordCache.h`; no dedicated module file | Record key exercised via `PDSRecordServiceTests.m`, `RepoCommitTests.m`; scenario 03 (content creation) | 01 |
| 18 | [AT-URI](https://atproto.com/specs/at-uri-scheme) | Supported | `ATURI.h/.m` (at:// URI parsing, authority extraction, collection/rkey decomposition); used in record resolution, admin endpoints, label targets | AT-URI parsing exercised via `XrpcInputValidationTests.m`, `AdminModerationAuthTests.m`; scenario 03 (content creation) | 01 |
| 19 | [did:plc](https://web.plc.directory/spec/v0.1/did-plc) | Supported | `PLCOperation.h/.m` (genesis, update, tombstone operations), `PLCPersistentStore.h/.m`, `PLCAuditor.h/.m`, `PLCDIDKey.h/.m`, `PLCConstants.h/.m`, `DIDPLCResolver.h/.m`, `PLCMockStore.h/.m`, `PLCSyncClient.h/.m`, `PLCSyncEngine.h/.m`, `PLCMetrics.h/.m`, `PLCCacheDirectory.h/.m`; operation chain verification, signature validation, rotation logic | `PLCServerTests.m`, `PLCStoreTests.m`, `DIDPLCResolverTests.m`; scenario 05 (federation) | 01 |
| 20 | [Proposal 0016: Permissioned Spaces](https://github.com/bluesky-social/atproto/tree/3f6c96d5d2d25438bd40fa89d6ecc37865f8e354) | Supported | `PDSSpaceCommit.h/.m`, `PDSSpaceJWT.h/.m`, `PDSSpaceLtHash.h/.m`, `PDSSpaceScope.h/.m`, `PDSSpaceURI.h/.m`, `PDSSpaceStore.h/.m`, `PDSSpaceReconciler.h/.m`, `PDSSpaceOplogPruner.h/.m`, `XrpcSpacePack.h/.m`, `PDSSpaceBlake3Dispatch.c`; isolated SQLite DB, space/user keys, oplog, BLAKE3, ltHash, JWT credentials; ADRs 0004 + 0005 | `PDSSpaceCommitTests.m`, `PDSSpaceJWTTests.m`, `PDSSpaceLtHashTests.m`, `PDSSpaceURIAndScopeTests.m`, `PDSSpaceStoreTests.m`; scenarios 93 (permissioned spaces), 94 (space reconciliation) | 03 |

## Known gaps (seeded from S6 task, verified against codebase)

### G1: Permissions — granular scope evaluation

**Spec:** [Permissions](https://atproto.com/specs/permission)

The published spec defines six resource types (`repo:`, `rpc:`, `blob:`,
`account:`, `identity:`, `include:`) with structured scope string syntax.
Garazyk implements the `space:` scope parser for permissioned spaces and
transitional scopes, but no granular resource-type scope evaluation was found
in the codebase.

**Assessment:** This is required for "all specs" production readiness. Plan
implementation as its own lane.

**Owning workstream:** 01 (S6 known gap).

### G2: Sync 1.1 remainder — closed (2026-07-19)

**Spec:** [Sync](https://atproto.com/specs/sync)

Upstream still lists export block ordering and collection-based repository
subsets as in-progress spec work. Both remain "Future Work" prose upstream
(rechecked 2026-07-19), not published spec text. A feature-flagged pre-order
enumerator exists for export block ordering (default off — deferred until
upstream spec text finalizes). Collection subsets are served via Garazyk's
`tools.garazyk.sync.getRepoFiltered` vendor extension.

**Status:** Closed pending upstream spec publication. Owned by workstream 02
(A6); revisit when upstream publishes version-numbered Sync text.

### G3: Account management surfaces

**Spec:** [Accounts](https://atproto.com/specs/account)

The account-lifecycle checks in S5 cover propagation semantics.
Deactivation/deletion/export UX-level endpoints should be confirmed against
the accounts spec in the same pass.

**Owning workstream:** 01 (S5).

### G4: Labels — self-signing key

**Spec:** [Labels](https://atproto.com/specs/label)

Label distribution and query endpoints are implemented, but no self-signing
`#atproto_label` key generation or label signature verification was found.
Labels may be accepted without cryptographic verification.

**Owning workstream:** 01 (S3).

## Verification

- **Commit:** `fe5760967d629bb2f71824132ebdde0417ce515c`
- **Date:** 2026-07-23
- **XRPC coverage:** 392 endpoints, 100% coverage, 0 duplicates
- **Scenario count:** 97 Deno/TypeScript e2e scenarios
- **Registered test classes:** 398 (384 .m test files)
- **Source files:** 1,033 .m/.h files in `Garazyk/Sources/`
- **AllTests --gated=run:** 4,062 tests, 21 known failures (STAR verifying reader pre-existing)

## Rollback

Documentation-only until a gap lane starts; each gap lane carries its own
rollback notes.

## Primary sources

- [Specification index](https://atproto.com/specs/atp)
- [Account lifecycle](https://atproto.com/specs/account)
- [Event streams](https://atproto.com/specs/event-stream)
- [Synchronization](https://atproto.com/specs/sync)
- [OAuth profile](https://atproto.com/specs/oauth)
- [Permissions](https://atproto.com/specs/permission)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)
- [Proposal 0016](https://github.com/bluesky-social/atproto/tree/3f6c96d5d2d25438bd40fa89d6ecc37865f8e354)
