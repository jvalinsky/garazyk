---
phase: 33
title: S2PA soft-binding algorithm compute and verify
status: complete
agent: worker
depends_on: []
---

## Progress

Completed 2026-08-13: Soft Binding Algorithm List entry
`com.joinmonolith.sha256` (exact SHA-256 over supplied bytes; timespan selects
block; ROI out of scope). Compute/verify APIs + claim hard+soft evidence;
transcoder auto-sign remains hard-bind-only and default OFF.

# Phase 33: Soft-binding algorithm compute / verify

## Mission

Move `c2pa.soft-binding` from structure-only to at least one real compute +
match path, without substituting soft bindings for hard bindings. Workstream
10 Phase 10 is authoritative.

## Read first

- [`docs/plans/workstreams/10-dasl-conformance.md`](../workstreams/10-dasl-conformance.md)
- `Garazyk/Sources/Security/S2PA/ATProtoS2PASoftBindingAssertion.{h,m}`
- `Garazyk/Sources/Security/S2PA/ATProtoS2PAClaim.{h,m}`
- C2PA Soft Binding Algorithm List (authoritative `alg` identifiers)
- C2PA 2.4 §18.10 soft-binding-map

## What is already correct — do not redo

- Encode/decode of `alg`, `blocks[{value, scope.timespan?}]`, optional `name` /
  `alg-params`
- Claim store can already carry soft-binding CBOR as a stored assertion

## Slices (landed)

1. Algorithm decision: `com.joinmonolith.sha256` in WS10 (not lab-only; ADR not
   required). Test string `phash` non-normative.
2. Compute: `+computeValueForData:alg:algParams:error:` /
   `+assertionMonolithSHA256ForData:timespan:name:error:`
3. Verify: `-verifyAgainstData:timespan:error:` exact match
4. Params: none required for this alg
5. ROI: out of scope in WS10
6. Claim hard + soft: `ATProtoS2PASoftBindingAssertionTests` /
   `ATProtoS2PAClaimTests`
7. No production soft auto-enable: `enableS2PAAutoSign` hard-bind only, default OFF

## Out of scope

- Replacing hard bindings with soft bindings
- Watermark embedding / `scope.region`
- Merkle / ingredient / tiles / iroh

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'ATProtoS2PASoftBindingAssertionTests' --gated=run
./build/tests/AllTests -XCTest 'ATProtoS2PAClaimTests' --gated=run
./scripts/dev/check_module_boundaries.sh .
```
