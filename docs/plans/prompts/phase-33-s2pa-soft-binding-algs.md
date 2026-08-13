---
phase: 33
title: S2PA soft-binding algorithm compute and verify
status: pending
agent: worker
depends_on: []
---

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

## Blocked on (Slice 1 only)

A recorded algorithm choice: pick an entry from the C2PA Soft Binding
Algorithm List, **or** an explicit lab-only identifier with a short ADR /
WS10 note that it is non-interoperable. Do not treat the test string `phash`
as normative.

Until Slice 1 lands a decision in the workstream (or ADR), do not invent
compute code for a fake algorithm id.

## Slices

### Slice 1 — Algorithm decision

Write the choice into WS10 (and ADR if lab-only). Name the `alg` string and
what media inputs are supported (bytes, optional timespan).

**Acceptance:** workstream paragraph exists; this phase unblocked for Slice 2.

### Slice 2 — Compute API

`+computeValueForData:timespan:algParams:error:` (names flexible) producing
block `value` bytes.

**Acceptance:** deterministic fixture → stable value.

### Slice 3 — Verify / match API

Compare computed/extracted value to assertion blocks (exact match or
algorithm-defined tolerance — document which).

**Acceptance:** match + mismatch tests.

### Slice 4 — Params / metadata as needed

Only if the chosen algo requires them: `alg-params`, `bindingMetadata`.
Otherwise skip.

### Slice 5 — Region scope

Implement `scope.region` **or** mark ROI out of scope in WS10. Timespan-only
is acceptable if documented.

### Slice 6 — Claim-store integration

Multi-assertion claim with hard binding **plus** soft binding; soft binding
must not be treated as the hard binding.

**Acceptance:** claim-bound test; hard-binding still required separately.

### Slice 7 — No production auto-enable

Confirm transcoder / VideoWorker do **not** enable soft-binding by default.
Plan evidence in WS10.

## Out of scope

- Replacing hard bindings with soft bindings
- Watermark embedding into media bitstreams (unless the chosen algo is exactly
  that and is scoped in Slice 1)
- Merkle / ingredient / tiles / iroh

## Acceptance gate

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests -XCTest 'ATProtoS2PASoftBindingAssertionTests' --gated=run
./build/tests/AllTests -XCTest 'ATProtoS2PAClaimTests' --gated=run
./scripts/dev/check_module_boundaries.sh .
```
