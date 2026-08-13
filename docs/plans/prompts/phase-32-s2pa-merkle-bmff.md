---
phase: 32
title: S2PA c2pa.hash.bmff.v3 Merkle trees
status: pending
agent: worker
depends_on: []
---

# Phase 32: Merkle bmffHash (`c2pa.hash.bmff.v3`)

## Mission

Extend the existing root-box BMFF hard-binding assertion with C2PA Merkle
trees over `mdat` (and optional nested xpath if chosen). Workstream 10 Phase
10 is authoritative.

## Read first

- [`docs/plans/workstreams/10-dasl-conformance.md`](../workstreams/10-dasl-conformance.md)
  — Phase 10: Merkle / nested xpath remainders
- `Garazyk/Sources/Security/S2PA/ATProtoS2PAHashBMFFAssertion.{h,m}`
- `Garazyk/Sources/Security/S2PA/ATProtoS2PAJUMBF.{h,m}` (two-pass BMFF sign)
- C2PA 2.4 §18.6 `bmff-hash-map` / `merkle-map` and §15.12 BMFF hash validation

## What is already correct — do not redo

- Root-box v3 hashing: `offset_be64 || box` with xpath/data/subset exclusions
- Default C2PA `/uuid` exclusion helper
- Two-pass JUMBF sign/verify for non-Merkle bmffHash
- `c2pa.hash.data` and claim store (unchanged by this phase unless wiring)

## Slices

### Slice 1 — `merkle-map` CBOR

Encode/decode: `uniqueId`, `localId`, `count`, `hashes`, optional `alg`,
`fixedBlockSize`, `variableBlockSizes`, `initHash`.

**Acceptance:** canonical CBOR round-trip; reject incomplete maps.

### Slice 2 — `mdat` leaf construction

Compute leaf digests for: (a) whole `mdat` payload as one leaf, (b) fixed
block size, (c) variable block sizes. Validate count/sum rules.

**Acceptance:** unit vectors for each mode; malformed sizes fail.

### Slice 3 — Merkle tree build + verify

Balanced binary tree, minimum depth, null padding only on the right; verify
leaf row and implied parents against `hashes` (as stored for this bounded
profile — document whether you store leaf row only vs a specific row depth).

**Acceptance:** tamper-one-leaf fails; stable encode for identical inputs.

### Slice 4 — Wire into assertion + hash rules

When both `hash` and `merkle` are present, apply v3 rules (no per-leaf file
offset for Merkle leaves). Keep non-Merkle path intact.

**Acceptance:** `verifyAgainstBMFFData:` covers Merkle and non-Merkle fixtures.

### Slice 5 — Nested xpath decision

Either implement nested container xpath (at least one `/moov/…` style path) or
record in WS10 that root-only + `subset` remains the supported profile.

**Acceptance:** decision written in WS10; tests match the chosen scope.

### Slice 6 — Fragmented / `initHash` (optional commit)

Only if needed for jelcz/fMP4 workflows: `initHash` + fragment verify. Prefer
a follow-up commit rather than blocking Slice 4–5.

### Slice 7 — JUMBF + plan

Two-pass sign/verify with a Merkle assertion; update WS10 + mega-plan.

## Out of scope

- Soft-binding algorithms
- Ingredient embedded-manifest verify (phase 31)
- Transcoder changes (auto-sign already landed)
- Full Streamplace exclusion-list parity dump

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'ATProtoS2PAHashBMFFAssertionTests' --gated=run
./build/tests/AllTests -XCTest 'ATProtoS2PAJUMBFTests' --gated=run
./scripts/dev/check_module_boundaries.sh .
```
