<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0034: STAR-lite v0 Is the Interoperable Lite Variant

**Status:** Accepted
**Date:** 2026-08-11

## Context

ADR 0009 assigned STAR version 2 to "STAR-lite" with the media type
`application/vnd.atproto.star-lite`, and recorded it as "a local
(Garazyk-specific) variant not covered by the upstream spec draft."

Upstream has since published a STAR-lite specification
(https://tangled.org/microcosm.blue/star, `star-lite/readme.md`), and
microcosm's Hubble — a public mirror of the whole Atmosphere — negotiates it
as `application/x.microcosm.star-lite` for repository backfill. Hubble sends
the media type in an `Accept` header, and additionally accepts a
non-standard `?accept=star-lite` query parameter on its own endpoint.

Our version 2 encoding and upstream's version 0 are not the same format. The
record section is byte-identical; the header is not:

| | upstream (`x.microcosm.star-lite`) | ours (`vnd.atproto.star-lite`) |
| --- | --- | --- |
| magic | `2A 6C 00` (`*l\0`, version 0) | `2A` + varint(2) |
| MST root CID | 36 raw bytes in the header | absent |
| commit | partial — `data` stripped | full — `data` included |
| records | `varint keyLen \| key \| varint recLen \| record` | identical |

The header layout was confirmed against a live archive served by
hetz-test-hubble.microcosm.blue and decoded byte-for-byte.

## Decision

### Version assignment

Version 0 (magic `2A 6C 00`) is **STAR-lite v0**, the interoperable upstream
variant, exported as `application/x.microcosm.star-lite`. ADR 0009's version 1
(STAR-L0) and version 2 (local STAR-lite) are unchanged and keep their
`vnd.atproto.*` media types. The local variant is not deprecated; it has no
external consumer, so there is no migration.

### Export is full-repository only

`repoContentsSTARLiteV0ChunkProducer:error:` takes no `since` argument. The
header names an MST root that a reader rebuilds from the record stream, so a
filtered archive could never verify. Making the parameter absent — rather
than accepting and ignoring it — also makes the `noChangesSince` header-only
early return unreachable by construction, since that flag is only ever set
when a `since` revision is supplied.

`com.atproto.sync.getRepo` **ignores** a `since` parameter when STAR-lite v0
is negotiated rather than rejecting it. A full archive is a valid superset of
a diff, so a client that appends `since` reflexively gets correct data; a 400
would turn a harmless over-fetch into a broken backfill.

### The partial commit is stripped, not rebuilt

The header commit is produced by decoding the stored commit block, removing
the `data` key, and re-encoding. It is **not** rebuilt from a fixed field
list. A reader re-inserts `data` from the header CID and verifies `sig` over
the result, so every other field — including a present-but-null `prev`, and
any field we do not model — must survive byte-faithfully.

Before serving, the writer performs that re-insertion itself and compares the
result to the stored commit block. A mismatch fails the export with
`com.atproto.star` code 59 and a 500 `RepoExportFailed`, rather than serving
an archive whose signature cannot verify on the far side. The check costs one
CBOR encode of ~150 bytes per request.

### Empty repositories

A zero-record repository still names a root: the empty MST node, computed via
`ATProtoMSTEmptyRootCID()` rather than hard-coded, so the header can never
disagree with the tree this implementation builds.

**This diverges from the upstream readme**, which states the empty-repository
CID as `bafyreihmh6lpqcmyus4kt4rsypvxgvnvzkmj4aqczyewol5rsf7pdzzta4` and
describes it as "the CID of a single empty atproto MST node". That appears to
be an error in the spec. An empty MST node is `{e: [], l: null}`, which in
canonical DAG-CBOR hashes to
`bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm` — the
well-known atproto empty-repo root, and what our MST computes. Seven
plausible alternative encodings (`{e: []}`, non-canonical key order,
undefined `l`, empty map, empty bytes, empty array, raw codec) were checked;
none produce the readme's digest.

Serving a root CID that contradicts our own tree would guarantee verification
failure, so we serve the computed one. Hubble's own encoder agrees with this
reading: `hubble/src/serve/get_repo.rs` populates the archive's header CID
from `spec.commit.data` unconditionally, so it never emits the readme's
constant either. The divergence is pinned by
`STARLiteV0Tests/testEmptyTreeCIDIsComputedFromAnEmptyMST` and should be
raised upstream as a readme fix.

### Query-parameter negotiation

`getRepo` and `getCheckout` accept an `accept` query parameter mirroring
Hubble's own convention. A recognized value overrides the `Accept` header;
an unrecognized one leaves negotiation to the header. This is a convenience
for operators and debugging, not a protocol requirement.

## Consequences

- **Positive**: Hubble can back-fill from a Garazyk PDS by sending
  `Accept: application/x.microcosm.star-lite`, with no CAR conversion.
- **Positive**: Records stream one at a time, so peak memory during export is
  bounded by the largest single record rather than by the whole archive. The
  local lite producer still buffers the entire archive.
- **Positive**: The pre-serve guard turns a silent cross-implementation
  verification failure into a loud local one.
- **Negative**: Two lite variants now exist with near-identical names. The
  media types are the disambiguator; `STARVariant` in the reader is unchanged
  because no v0 *reader* is implemented — we export only.
- **Resolved**: STAR-L0 rebuilt its commit from a fixed field list and had the
  same latent present-but-null `prev` drop. `ATProtoSTARL0Writer` now has
  `-initWithCommitBlock:error:` / `-initWithCommitBlock:outputBlock:error:`,
  which embed the stored commit verbatim (STAR-L0 keeps `data` in the header,
  unlike v0, so nothing needs stripping) after decoding it and verifying our
  own re-encoding reproduces it byte-for-byte — the same guard philosophy as
  `ATProtoSTARLiteV0Writer`. `PDSRepositoryService+Export.m`'s three STAR-L0
  call sites use the new initializer; `starCommitFromExport:` (still
  fixed-field-list) remains in use only for STAR-lite v2, which has no
  external consumer.
- **Resolved**: our initial commit omitted `prev` entirely, which the atproto
  repository spec forbids — in v3 repos `prev` "must exist in the CBOR
  object", and the spec notes that specifying it as optional "caused
  interoperability issues". Consumers reconstruct the unsigned commit per
  spec and would therefore verify a five-key map against a signature we made
  over four keys. Hubble does exactly this
  (`hubble-sync/src/commit/commit_object.rs`: `UnsignedCommit.prev` is
  `Option<DaslCid>` with no `skip_serializing_if`, commented "must be present
  (null when unset)").

  `ATProtoRepoCommit` gained a `prevKeyExplicit` flag
  (`Garazyk/Sources/Repository/RepoCommit.m`/`.h`): commits created via
  `+createCommitWithDid:data:rev:prev:` now always serialize `prev` (as null
  when there is no previous commit), matching the spec. Commits decoded via
  `+fromSignedBlockData:` preserve whatever the wire actually did — key
  present (CID or null) vs. absent — so re-serializing a decoded commit (as
  `-verifySignatureWithPublicKey:error:` does, since verification rebuilds
  the signed bytes from the parsed object rather than comparing raw bytes)
  reproduces exactly what was signed. This means existing stored genesis
  commits, which omitted `prev` under the old code, keep verifying under
  Garazyk's own signature check without any data migration — only newly
  created genesis commits changed shape. It also fixes federation import: an
  externally-created commit with an explicit `prev: null` (spec-compliant)
  previously failed `PDSRepoImportValidator` verification because decoding
  and re-serializing it silently dropped the null.
