# ADR 0009: STAR Versioning and Variants

## Status

Accepted (2026-07-23)

## Context

The STAR (STreaming ARchive) format is used as a stricter, verifiable,
deterministic alternative to CAR files for ATProto repository serialization.
The format has two variants with different trade-offs, and the verifier needs
clear version semantics to distinguish them. Additionally, the upstream spec
draft's intro prose differs from its format section on how an empty tree is
encoded; a decision is needed for what our implementation actually produces
and verifies.

The STARMstNode writer had a layer-0 `V`-flag wire-format violation (Slice A
of the star-conformance plan), the STARReader.parseL0Body was non-verifying
(Slice B), and the degenerate CAR→STAR converters had zero production callers
(Slice C). All three slices are now implemented.

## Decision

### Version assignment

- **Version 1** (varint `0x01` in the STAR header): **STAR-L0**. MST-structured,
  depth-first node/record interleaving, streaming verification against the
  commit's `data` CID chain. Canonical, deterministic encoding.
- **Version 2** (varint `0x02` in the STAR header): **STAR-lite**. Flat
  key-record encoding, best compression, no MST node blocks. This is a local
  (Garazyk-specific) variant not covered by the upstream spec draft.

### MIME types

- `application/vnd.atproto.star` — STAR-L0 (version 1)
- `application/vnd.atproto.star-lite` — STAR-lite (version 2)

### Empty-tree encoding

The empty tree (a repository with no records) is encoded by **omitting the
`data` key from the commit object**. The STAR archive for an empty tree
consists solely of a header (magic + version varint + commit-length varint +
commit DAG-CBOR) with no body blocks.

This matches the upstream spec's format section (not its intro prose). The
verifying reader treats `commit.data == nil` as an empty tree and returns zero
blocks without raising an error, but rejects trailing bytes after the header.

### CAR→STAR conversion

CAR→STAR conversion is **not supported**. The two degenerate methods
(`starL0DataFromCARData:` and `starLiteDataFromCARData:`) are deleted with
caller proof (zero production callers). The live-MST writer (`STARL0Writer`)
is the canonical export path; it walks the live MST depth-first and does not
need CAR blocks as input.

### STAR→CAR conversion

The `carDataFromSTARData:` method now performs **verifying** conversion:

1. Parses the STAR archive with the verifying stack-based reader
2. Serializes the commit to DAG-CBOR and computes its CID
3. Sets the CAR root to the commit CID (not the MST root)
4. Prepends the commit block to the verified node and record blocks
5. Rejects sig-less archives (error code 21) — a CAR without a commit
   signature cannot be compliant

## Consequences

- **Positive**: STAR-L0 archives are now fully verifiable on import. Every
  MST node CID is checked against the commit's `data` CID chain; layer-0
  record links are rehydrated before verification; wire-format flags are
  stripped. Trailing bytes, truncated varints, and CID mismatches are all
  rejected with specific error codes (30-44).
- **Positive**: The `V`-flag wire-format violation is fixed. At layer 0,
  entries that omit `v` (because records follow inline) no longer emit `V`;
  the absence of `v` is the archived signal per the spec.
- **Negative**: CAR→STAR conversion is no longer available. No production
  caller existed, so no migration burden.
- **Neutral**: The Error Domain `com.atproto.star` error codes 14-19 remain
  unused; codes 30-44 are the new verifier rejection codes.
