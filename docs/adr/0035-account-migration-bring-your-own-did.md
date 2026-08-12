<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0035: Account Migration via Bring-Your-Own-DID, and importRepo Scaling

**Status:** Accepted
**Date:** 2026-08-11

## Context

A real attempt to migrate a large Bluesky account (`did:plc:vc7f4oafdgxsihk4cry2xpze`,
~180 MB repo CAR) onto a Garazyk PDS (`pds.garazyk.xyz`) failed before size was ever the
issue: `com.atproto.server.createAccount` rejects any request carrying a `did`
("Cannot specify DID during account creation"), so there is no path to create an account
under an existing DID at all. Even with that path open, `com.atproto.repo.importRepo` is
not ready for repos this size:

- Three independent, hard-coded byte caps: the global `Http1Parser`/`HttpServer`
  `maxBodyBytes` (50 MB), and **two separate** `kPDSImportRepoMaxBodyBytes` constants
  (16 MB each) in `XrpcRepoPack+Import.m` and `PDSRepoImportValidator.m` that share a
  name but not a symbol. None are configurable.
- The whole CAR is buffered into memory and then parsed fully into `reader.blocks`,
  a full `PDSDatabaseBlock` array, and full record arrays before the DB transaction
  even opens.
- Hard-coded work limits (`kPDSImportRepoMaxCARBlocks`/`MaxMSTNodes`/`MaxRecords` =
  100,000) that a large real account plausibly exceeds (a 180 MB CAR at ~500–1000
  bytes/record is on the order of 180k–360k records).
- Blob bytes are never imported (spec-correct), and nothing orchestrates the
  fetch-from-source + re-upload loop that would make a migration complete.

The reference TypeScript PDS (`bluesky-social/atproto`, `packages/pds`) solves the
account-creation piece with a bring-your-own-DID path: when the request contains a
`did`, the caller must present a signed service JWT proving control of that DID
(`ctx.authVerifier.userServiceAuthOptional`), the account is created **deactivated**,
no PLC operation is minted (`plcOp = null`), and the DID's document is left untouched so
a failed migration strands nothing. `importRepo` takes the size cap from configuration
(`ctx.cfg.service.maxImportSize`, env `PDS_MAX_REPO_IMPORT_SIZE`) and is gated by an
`acceptingImports` flag (env `PDS_ACCEPTING_REPO_IMPORTS`, default true).

The scaffolding for the service-auth check already exists in Garazyk:
`validateDidWebServiceAuthForAccountCreation` in `XrpcServerPack.m` verifies a Bearer
JWT against the DID document's `atproto` signing key, requiring `lxm =
com.atproto.server.createAccount`, `iss = did`, and a valid audience — but it is gated
off behind `enforceDidWebServiceAuth = NO`, only fires for `did:web:`, and even then the
validated `did` is discarded before `PDSAccountService` is called.

## Decision

### Scope: self-hosted-PDS-to-self-hosted-PDS for v1, not entryway

Garazyk v1 supports the **self-hosted PDS-to-PDS** migration case: an operator who
controls both PDSes (or the DID's signing key outright) can move an account by calling
`createAccount` with the existing `did` plus a service JWT signed by the DID's current
signing key, then `importRepo` the exported CAR. The full entryway-style flow from the
reference — app-driven migration with the old PDS minting `userServiceAuth` tokens on
demand, cross-service preference/state migration, guided PLC cutover UX — is **out of
scope for v1**. The server-side primitive (deactivated BYO-DID account + verified
import) is the same for both; entryway is tooling layered on top, and the AT Protocol
account-migration guide's steps map onto already-implemented XRPC surface
(`com.atproto.server.activateAccount`, `com.atproto.repo.listMissingBlobs`,
`com.atproto.sync.listBlobs`/`getBlob`).

### Proof of DID control: mandatory service-auth JWT, verified against the DID document

When `createAccount` receives a `did`, the request **must** carry an
`Authorization: Bearer <service JWT>` with:

- `lxm` exactly `com.atproto.server.createAccount`;
- `iss` equal to the requested `did`;
- `aud` matching one of this PDS's expected audiences;
- a signature verifying against the `atproto` signing key in the DID's **current,
  resolved** document (via `ATProtoDIDResolver`), so the check is DID-method-agnostic
  (works for `did:plc` and `did:web` alike) and cannot be satisfied by a key that does
  not own the identity.

This reuses and generalizes the existing `validateDidWebServiceAuthForAccountCreation`
(now `validateDidServiceAuthForAccountCreation`); no second mechanism is invented. The
check is **mandatory** when `did` is present (fail closed, matching upstream). It is not
operator-configurable off: allowing unauthenticated DID takeover would be an identity
vulnerability, not a feature. Registration gates (invite codes, CAPTCHA, phone) do **not**
apply to the BYO-DID path: the service-auth proof of DID control is the authorization,
and a migration is not a registration.

For the self-hosted case the operator mints this JWT directly with the signing key (held
by the old PDS or the operator), so no new server primitive is required to produce it.

### The account is created deactivated; PLC is not touched

A BYO-DID account is created with `status = 'deactivated'` (`deactivated_at` stamped),
exactly as upstream creates it with `deactivated = true`. No PLC operation is minted or
submitted. Consequences that make this the safe default:

- The DID's document keeps resolving to the old PDS until the operator explicitly
  performs the cutover (a PLC `update` repointing `atproto_pds` — and rotating the
  signing key, in the full flow). A failed or partial migration never strands or splits
  the identity, because nothing on the network side has changed.
- `loginWithIdentifier:` refuses sessions for deactivated accounts (`AccountDeactivated`,
  401), and session responses (`createSession`, `getSession`) report `active: false`, so
  the half-migrated account cannot be used as if it were hosted here. The migration
  tooling authenticates with the tokens returned by `createAccount` itself.
- `importRepo` accepts the imported repo while the account is deactivated: commit
  signatures verify against the DID document (the old key), which is exactly what an
  imported CAR contains.

The service layer continues to generate and store a fresh keypair for the account
(pre-existing behavior, unchanged by this ADR): after the operator rotates the signing
key as part of the PLC cutover, that key becomes the DID's key and the PDS can sign
commits. Until then the account is deactivated and the stored key is unused for
presentation.

### `maxImportSize` and `acceptingImports` become configuration

`ATProtoServiceConfiguration` gains two values mirroring upstream:

- `maxImportSize` (bytes) — from config `service.maxImportSize`, env
  `PDS_MAX_REPO_IMPORT_SIZE`, default **1 GiB**. This replaces both
  `kPDSImportRepoMaxBodyBytes` constants; the XRPC handler, the import validator, and the
  per-route HTTP body cap all read the one value.
- `acceptingImports` (bool) — from config `service.acceptingImports`, env
  `PDS_ACCEPTING_REPO_IMPORTS`, default **YES**. When NO, `importRepo` fails fast with
  `InvalidRequest` before reading the body (feature-flag style, matching upstream).

Garazyk differs from upstream in giving `maxImportSize` a default (upstream has none and
requires it in config). A safe default avoids breaking existing deployments that upgrade
without adding the key; operators who want the upstream fail-hard behavior can set it
explicitly.

### The HTTP body cap is raised per-route, not globally

The generic 50 MB `Http1Parser`/`HttpServer` cap stays. `importRepo`'s route registers
with `maxBodyBytes = maxImportSize` on the `XrpcDispatcher`, which exposes the limit to
the HTTP layer through a per-path provider block installed on the server by
`ATProtoHttpXrpcRoutePack`. The parser consults the provider when it reads
Content-Length (and for chunked bodies), so the large body is admitted before dispatch
while every other XRPC endpoint keeps the small default cap. This is a blast-radius
surgical change: no global raise.

### importRepo gets a streaming CAR read and batched writes

`Repository/CAR.h` gains `ATProtoCARStreamReader`: header-then-blocks incremental parsing
with per-block strict DASL/CID-hash verification, root-presence enforcement, and a
CID→block index maintained as blocks stream (the index is required by the MST walk,
which needs random access by CID — a documented property, not an oversight). The import
handler now:

1. Streams the CAR once (strict) to verify every block, enforce the block-count limit,
   and build the index — before any database work, preserving today's
   "validation failure is a clean 400 that never touches the store" semantics;
2. Opens the single transaction (retained: upstream also imports atomically) and writes
   blocks in bounded batches of 2,048 via `putBlocks:`, instead of materializing one
   giant `PDSDatabaseBlock` array;
3. Extracts records from the MST via the stream reader's index, lexicon-validates them
   (garazyk's stricter posture is unchanged — ADR 0034's stance applies; this ADR does
   not weaken import validation), writes records, syncs blob references, and updates the
   repo root.

The full request body is still buffered by `Http1Parser` before dispatch, and the index
retains block data for the MST walk. Peak memory is bounded by body + index + batch +
records rather than body + full block array + full `PDSDatabaseBlock` array, which is
comfortable for the ~180 MB case but **not** sub-linear. True socket-level body
streaming with a disk-backed CAR reader (the path to multi-GB repos) is a documented
follow-up, not part of this change.

### importRepo remains initial-import-only for now (no diffing, B4)

Upstream computes a diff against the current repo state and applies only the deltas,
letting `importRepo` double as "catch this repo up to a newer CAR". Garazyk's version
assumes the target repo is empty. For v1 we **explicitly keep initial-import-only** and
document it here rather than in code: the migration case imports into a fresh account,
and a non-empty-target re-import would today overwrite state without a diff. Matching
upstream's `verifyDiff` semantics is a separate workstream item (it interacts with
`PDSRepoImportValidator`'s signature checks and the actor-store transaction). A guard —
`importRepo` rejects with `InvalidRequest` when the target store already holds a repo
root — is NOT added in this pass; the existing behavior of overwriting is unchanged
until the diff work lands, to avoid surprising existing scripted re-imports (e.g. the
scenario suite's "re-import via CAR" step).

### Blob migration is a follow-up script, not an importRepo feature (B5)

Repo CARs never contain blob bytes; `importRepo` correctly writes only blob
*references*. Orchestrating "for each `listMissingBlobs` entry, fetch from the source
PDS via `com.atproto.sync.getBlob` and re-upload via `com.atproto.repo.uploadBlob`" is a
migration-tooling gap, not a missing server primitive — the read-side sync endpoints
already exist. This is scoped as a follow-up script (alongside `scripts/import_repo_car.ts`,
which is investigation tooling and out of scope for this change), not folded into
`importRepo`.

### Hard-coded work limits are raised, still bounded

`kPDSImportRepoMaxCARBlocks` / `kPDSImportRepoMaxMSTNodes` / `kPDSImportRepoMaxRecords`
move from 100,000 to 1,000,000. A 180 MB CAR at realistic record sizes exceeds 100,000
records, so the old limits would have rejected the very case this ADR exists to enable.
The limits remain a DoS bound; with `maxImportSize` capping the body, worst-case work is
bounded by the configuration. `kPDSImportRepoMaxMSTDepth` (512) is unchanged.

## Consequences

- **Positive**: A real existing account can be brought onto a Garazyk PDS without
  breaking its identity: `createAccount` with the existing `did` + service JWT creates a
  deactivated account, `importRepo` accepts the 180 MB+ CAR, and the operator completes
  the cutover by repointing PLC and calling `activateAccount`.
- **Positive**: The identity-takeover decision is now a recorded, reviewed contract
  (mandatory service-auth proof, deactivated by default, no PLC mutation) rather than an
  unimplemented guard.
- **Positive**: Size limits are one config value instead of three unrelated constants;
  operators can raise `maxImportSize` without touching code, and can switch imports off
  entirely with `acceptingImports`.
- **Positive**: The import path's peak memory drops by roughly one full copy of the CAR
  (the `blocks` array and the full `PDSDatabaseBlock` array) and its DB writes are
  batched, at no cost to atomicity.
- **Negative**: The BYO-DID path is the only way to create an account with a `did`, and
  it requires minting a service JWT; scripts that previously "imported a DID" without
  proof must now hold the signing key. That is the point, not a regression.
- **Negative**: Deactivated accounts can no longer create sessions, and `createSession`
  now reports `active: false` for them. This is upstream behavior and the correct
  semantic, but any tooling that assumed deactivated-but-loginable will need updating.
  Refresh-token rotation (`refreshSession`) is deliberately not blocked for deactivated
  accounts, so the migration tool's long-lived session survives the import window;
  operators who want a hard lock should rotate/revoke credentials at activation.
- **Neutral**: `applyConfig:` only overrides keys present in the applied dictionary, so
  removing `service.maxImportSize`/`service.acceptingImports` from a config reload
  retains the previously parsed values rather than falling back to the defaults. This
  matches how every other config section already behaves; set the keys explicitly to
  change them.
- **Neutral/deferred**: diffing (B4), blob-migration orchestration (B5), and
  sub-linear-memory (disk-backed) imports remain open, each recorded above with its
  rationale. None blocks the migration case this ADR targets.
