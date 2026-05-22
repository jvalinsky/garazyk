# PDS Deep Review Findings Scratchpad

This file is temporary working memory for evidence and triage. Confirmed findings should be copied into the final report with file/line references.

## Inventory

- Request boundary files reviewed:
  - `Garazyk/Sources/Network/XrpcRepoPack.m`
  - `Garazyk/Sources/Network/XrpcSyncPack.m`
  - `Garazyk/Sources/Network/XrpcAuthHelper.m`
  - `Garazyk/Sources/Network/Http1Parser.m`
- Repository and storage files reviewed:
  - `Garazyk/Sources/Services/PDS/PDSRecordService.m`
  - `Garazyk/Sources/Services/PDS/PDSRepositoryService.m`
  - `Garazyk/Sources/Repository/CAR.m`
  - `Garazyk/Sources/Repository/RepoCommit.m`
  - `Garazyk/Sources/Database/Pool/DatabasePool.m`
  - `Garazyk/Sources/Database/ActorStore/ActorStore.m`
  - `Garazyk/Sources/Database/Service/ServiceDatabases.m`
  - `Garazyk/Sources/Database/ActorStore/PDSActorStore+Account.m`
- Blob and MIME files reviewed:
  - `Garazyk/Sources/Blob/MimeTypeValidator.m`
  - blob upload/download handlers in `XrpcRepoPack.m` and `XrpcSyncPack.m`

## Scanner Notes

- Security scanner output is stored in `scratchpads/pds-deep-review-2026-05-22/scans/security/`.
- Architecture scanner output is stored in `scratchpads/pds-deep-review-2026-05-22/scans/architecture/`.
- SQL scan found 22 SQL string-formatting sites and 5 concatenation sites, but most externally interesting scanner hits use placeholder construction plus bound parameters. Confirmed SQL concern is limited to a future-footgun migration helper, not a directly exploitable request path.
- Crypto scan found SHA1 use in WebSocket handshake code. This is protocol-required for the WebSocket accept key and is not a weak-password/hash finding.
- Secrets scan did not detect production secrets.
- Log-redaction scan was noisy, but manual review confirmed full `applyWrites` body logging in `XrpcRepoPack.m`.
- Architecture scans had broad path assumptions and many false positives; manual review drove the confirmed findings.

## Manual Review Notes

- `com.atproto.repo.importRepo` parses uploaded CAR/STAR data, checks only that the commit DID matches the authenticated DID, then stores blocks and records directly into the actor store. It does not verify commit signatures and does not recompute CAR block CIDs before storing.
- `walkMST` recursively walks imported MST links without a visited set, depth cap, node cap, or record cap. The HTTP parser caps body size at 50 MB, but the CAR parser materializes the entire block set and the MST walk can still consume substantial CPU/stack.
- `com.atproto.repo.applyWrites` only checks that `writes` is an array. `PDSRecordService` assumes each member is an `NSDictionary` and performs keyed subscripting in the per-DID write queue.
- Public sync listing endpoints load all accounts into memory and then perform per-account repository/store reads.
- Public sync export endpoints have streaming variants, but export preparation still builds whole-repo record/MST/materialized-block structures in memory; `getCheckout` and `getBlocks` return fully materialized `NSData`.
- Blob MIME allowlist includes active web/document types and the magic-number validator returns success for many unsniffed types.
- Actor-store path sinks build filesystem paths directly from DID components and should defend themselves even when callers are expected to validate.

## Candidate Findings

1. P1: `importRepo` accepts repositories without verifying commit signatures or content-address integrity.
2. P1: `importRepo` has unbounded recursive MST traversal and materializes attacker-supplied CAR data.
3. P1: `applyWrites` lacks per-write schema validation and batch limits, allowing malformed write crashes or per-DID write queue monopolization.
4. P2: `applyWrites` logs full request bodies and write arrays at info level.
5. P2: public sync listing endpoints perform full-account scans and N+1 actor-store reads.
6. P2: public sync export/block endpoints materialize large CAR/STAR responses and accept unbounded `cids` lists.
7. P2: blob MIME validation allows active content and trusts unsniffed types.
8. P2: actor-store filesystem path construction lacks sink-level DID/path validation.
9. P3: dynamic SQL helper whitelists table/column names but accepts arbitrary SQL type strings.

## Rejected / Low-Confidence Leads

- `PDSAdminService.m` invite-code `IN` queries use generated placeholders and bound params after manual review.
- `XrpcAdminPack.m` dynamic order-by handling uses a whitelist before string interpolation.
- WebSocket SHA1 scanner hits are protocol-specific and not a password or integrity hash issue.
- The broad XRPC "files without auth" scanner list was not treated as evidence because many listed files are route builders, public endpoints, headers, or non-PDS modules.
