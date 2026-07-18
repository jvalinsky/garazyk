# Permissioned Spaces Compatibility and Security Note

This document tracks the experimental Proposal 0016 implementation against
the pinned upstream reference (`3f6c96d5d2d25438bd40fa89d6ecc37865f8e354`).
`permissionedSpacesEnabled` is off by default. Operators must not enable it
for production workloads until every item marked pending has passed the
multi-PDS acceptance scenarios.

| Area | Current behavior | Status |
| --- | --- | --- |
| Lexicons | Vendored exact `com.atproto.space` and `com.atproto.simplespace` contracts from the pinned reference. | Implemented |
| Storage | Separate SQLite database, WAL, migrations, per-space/per-author LtHash, operation log, membership, writer set, and replay state. No public repository, firehose, search, or moderation path opens it. | Implemented |
| URIs and scopes | Strict unqualified space URI parser and fail-closed `space:` OAuth parser, including `read_self`, collection, tuple, and management semantics. | Implemented |
| Delegation and credentials | ES256K signed, typed, bounded lifetime JWTs. Delegations are atomically single-use. Credentials use the documented account-key fallback until a dedicated key is published. | Implemented |
| Space policy | `public` and `member-list` with authority membership enforcement at credential minting. | Implemented |
| App attestation | `managing-app` and `appAccess#allowList` reject requests. | Intentionally disabled |
| Reads and writes | Scoped record reads/writes, signed current commits, current-operation listing, writer listing, and deterministic two-root CAR snapshot export. | Implemented; scenario 93 runtime pass 2026-07-18 (3-PDS binary, 19/19) |
| Notifications | Authenticated writer notification updates the authority writer set and fans out to registered recipients; authenticated deletion notification tombstones replicas. Recipient registrations are persisted and expire after 24 hours unless renewed. | Implemented; scenario 93 runtime pass 2026-07-18. Two fixes landed en route: DPoP P-256 low-S verification ([ADR 0007](adr/0007-p256-ecdsa-verification-must-not-enforce-low-s.md)) and service-auth `allowMissingSubject` on `notifyWrite` |
| DID resolution | Exact `#atproto_space`/`#atproto` key selection and `#atproto_space_host`/`#atproto_pds` endpoint selection. New experimental account/server DID documents explicitly publish same-value dedicated entries and credentials identify that entry. `permissionedSpacesHostEndpoint` supports a validated peer-facing endpoint. | Dedicated independent-key rotation and migration of existing DIDs pending |
| Private blobs | Raw-CID blobs reside only in the isolated space SQLite store and `com.atproto.space.getBlob` requires a matching OAuth read grant or space credential. `com.atproto.repo.uploadBlob` enters that namespace only with the documented `X-Atproto-Space`, `X-Atproto-Space-Collection`, and `X-Atproto-Space-Action` binding headers and a matching scoped write grant. | Implemented locally; needs multi-PDS acceptance test |
| Multi-PDS recovery | Normal notifications are best effort. Each PDS durably replays local writer heads to the authority on startup and at a bounded interval; writer-set updates are monotonic, so duplicate, delayed, and reordered delivery cannot roll a head back. Each reader PDS runs an inbound reconciliation loop that detects gaps and recovers state via incremental ops, lightweight record diff, or full CAR import. Oplog pruning is configurable and bounded by a background compaction timer. | Implemented; multi-PDS acceptance test pending |
| OAuth federation scenario | Scenario 93 obtains PAR + PKCE + DPoP OAuth grants, exchanges signed delegation tokens for credentials, writes from PDS A to a space hosted by PDS B, reads with a member credential from independent PDS C, checks public repo isolation, and rejects a newly minted credential after membership removal. | **Runtime pass 2026-07-18** — 19/19 on the 3-PDS `--binary` topology (PDS/PDS2/PDS3). The former Scenario 94 consent redirect issue is regression-covered by `9000097ba`; its fresh run `2026-07-18t2153z-87263` stopped before execution because AppView failed to start, so reconciliation acceptance remains pending. |

## Security boundaries

- Permissioned data is never added to the public repository database, public
  repo XRPC methods, CAR import/export paths, sync feed, relay, AppView,
  search index, or moderation data.
- Authorization parsing happens before store access. URI, DID, NSID, record
  key, scope, JWT, and DID-document service/key values are parsed into typed
  structures; SQLite calls use bound parameters.
- A credential proves only the authority's space grant. It is accepted for
  reads, never writes. Writes require a normal PDS OAuth token whose verified
  `space:` scope permits the exact action and collection.
- Membership removal blocks subsequent credential issuance. A previously
  issued credential has no member subject by protocol design, so it expires
  naturally within two hours; it is not treated as remotely revocable state.
- Space blobs are never handed to the ordinary blob service or public blob
  tables. Public repo/sync/blob endpoints therefore cannot address them. Space
  blob responses are authenticated, `no-store`, `nosniff`, sandboxed, and
  delivered as attachments.

## Acceptance gate

Before enabling production traffic, test two independent PDS instances for:

1. delegated credential issuance, authenticated remote write, authority
   notification, remote reader credential, and record/CAR read;
2. member removal, expired and replayed delegation rejection, credential
   lifetime behavior, and authority deletion fan-out;
3. notification loss followed by reconciliation, restarts with persisted
   state, and attempted reads through public repo/sync/blob endpoints;
4. private media upload/download through the isolated blob namespace, and
   rejection through ordinary public blob endpoints.

Scenario 93 provides the executable three-PDS OAuth, credential, remote-write,
notification, public-boundary, and membership-revocation portion of this gate
when `PDS3_URL` names an independently operated PDS C. It does not establish
full-state CAR reconciliation after oplog pruning; that case is covered by
the three-path reconciliation protocol (incremental ops, lightweight record
diff, full CAR import) implemented in PDSSpaceReconciler and awaiting a
dedicated multi-PDS reconciliation scenario.
