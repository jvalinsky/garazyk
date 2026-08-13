---
phase: 31
title: S2PA ingredient validationResults and embedded-manifest verify
status: pending
agent: worker
depends_on: []
---

# Phase 31: Ingredient validationResults + embedded-manifest verify

## Mission

Finish the open half of `c2pa.ingredient.v3`: encode/verify `validationResults`,
embed a child claim-bound manifest in the JUMBF store, and validate
`activeManifest` / `claimSignature` hashed URIs. Workstream 10 Phase 10 is
authoritative.

## Read first

- [`docs/plans/workstreams/10-dasl-conformance.md`](../workstreams/10-dasl-conformance.md)
  — Phase 10 remainder: “validationResults and embedded-ingredient hash
  validation remain open”
- `Garazyk/Sources/Security/S2PA/ATProtoS2PAIngredientAssertion.{h,m}`
- `Garazyk/Sources/Security/S2PA/ATProtoS2PAClaim.{h,m}`
- `Garazyk/Sources/Security/S2PA/ATProtoS2PAJUMBF.{h,m}`
- C2PA 2.4 ingredient-map-v3 + §15.11 ingredient validation (claim signature
  hash method)

## What is already correct — do not redo

- Ingredient encode/decode for `relationship`, title/format/instanceID,
  `digitalSourceType`, and `activeManifest`/`claimSignature` hashed URIs
- Mutual exclusion of `activeManifest` ∩ `digitalSourceType`
- Claim-bound multi-assertion stores (`uuidBoxSigningAssertions:`)
- Existing hard-binding / bmffHash / soft-binding *structure* (separate phases)

## Slices

### Slice 1 — `validationResults` CBOR

Add encode/decode for the bounded `validationResults` map:
`activeManifest.{success,informational,failure}` arrays of `{code, url?}`.

**Acceptance:** round-trip test; empty/malformed maps rejected.

### Slice 2 — Require results when `activeManifest` present

When `activeManifest` is set, `validationResults` is required on encode and
parse (C2PA v3). `inputTo` + `digitalSourceType` paths stay without it.

**Acceptance:** negative tests for missing results with activeManifest.

### Slice 3 — Embed child manifest in store

Builder that nests a child claim-bound JUMBF (or uuid-derived store) under a
stable label/URI (`self#jumbf=/c2pa/<instanceID>` shape) and fills ingredient
`activeManifest` + `claimSignature` hashed URIs over those boxes.

**Acceptance:** parent store contains resolvable child boxes; URIs match labels.

### Slice 4 — Hashed-URI integrity

Hash over jumb body (same rule as assertion hashed URIs). Tampering child
bytes fails verify.

**Acceptance:** mismatch test fails with a clear error code.

### Slice 5 — Verify path

Resolve `activeManifest` / `claimSignature`, check digests, optionally
re-verify child COSE (reuse existing leaf+COSE helpers). Do **not** implement
full recursive ingredient-delta validation graphs yet.

**Acceptance:** `ATProtoS2PAIngredientAssertionTests` + claim-bound integration
green; focused filter documented in WS10.

### Slice 6 — Plan evidence

Update WS10 Phase 10 + mega-plan remainder. Explicitly leave
gathered/redacted assertions as a later item (not this phase).

## Out of scope

- Gathered/redacted assertions
- Full §15.11 recursive ingredient tree / ingredientDeltas product UX
- Merkle bmffHash, soft-binding algorithms, tiles, iroh

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'ATProtoS2PAIngredientAssertionTests' --gated=run
./build/tests/AllTests -XCTest 'ATProtoS2PAClaimTests' --gated=run
./scripts/dev/check_module_boundaries.sh .
```

WS10 Phase 10 text records this phase complete with commit hash + date.
