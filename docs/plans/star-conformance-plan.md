# STAR Conformance: Verifying Reader and Wire-Format Fix

## Status: complete (2026-07-23) — all three slices landed

## Summary

Bring STAR support up to the spec it claims to implement
(https://tangled.org/microcosm.blue/star). The export side is correct
and fixture-tested; the read/import side does not implement the spec's
read model, and the writer has one wire-format conformance bug.
Workstream 01 S7; mega-plan Phase 4 item 9.

## Audit findings (2026-07-22)

All code in `Garazyk/Sources/Repository/STAR.m` unless noted.

**Sound (keep, do not touch):**

- `STARL0Writer` walks the live MST depth-first and emits spec-shaped
  headers, nodes, and records; `STARPreorderTests.m` pins header
  chunking and preorder emission.
- The negotiated public sync export path
  (`PDSRepositoryService.repoContentsSTARL0ChunkProducer:`) uses this
  writer — verified working by the phase-10 brief's correction section.
- Content negotiation (`PDSRepoFormatFromAcceptHeader`) and `0x2A`
  format detection.

**Defects:**

1. **Writer `V`-flag violation** (STAR.m:198): at layer 0 the writer
   omits `v` for archived records but still emits `V: true`. Spec: `V`
   "must not be present when `v` is not present" — at layer 0, absence
   of `v` *is* the archived signal. Self-consistent locally (our reader
   ignores flags) but non-canonical and un-parseable by a conformant
   implementation.
2. **`STARReader.parseL0Body` is non-verifying** (STAR.m:756): splits
   the stream into length-prefixed blobs and computes a CID over each
   blob's raw bytes. STAR-L0 node blocks are wire-format nodes (omitted
   layer-0 `v`, extra `L`/`V`/`T` flags), so computed node CIDs can
   never match `commit.data` or parent `t`/`l` links. Nothing is
   verified; trailing garbage is accepted.
3. **`carDataFromSTARData:` emits a non-repo-spec CAR**: root is the
   MST root (not the commit CID), no commit block is included, and node
   blocks carry wrong CIDs (defect 2). Consequence: the STAR import
   paths — `importRepo` (`XrpcRepoPack.m:1260`), AppView ingest
   (`AppViewIngestEngine.m:683`), backfill
   (`AppViewBackfillWorker.m:291`) — cannot round-trip any STAR-L0
   archive containing a tree.
4. **`starL0DataFromCARData:` / `starLiteDataFromCARData:` are
   degenerate** (FIXME at STAR.m:974): no MST reconstruction from CAR
   blocks. Zero production callers (phase-10 brief correction section).
5. **No bounded-memory streaming read** — reader buffers the whole
   archive; spec motivation 1 (bounded-resource streaming, early
   rejection of garbage) unrealized.

## Slices (one commit each, lowest risk first)

### Slice A: writer `V`-flag fix + fixture regeneration

- Emit `V` only when `v` is present: at depth 0, archived records get
  neither `v` nor `V`; at depth > 0, `v` is always present and `V: true`
  marks the record as following in the stream.
- This changes emitted bytes: regenerate the byte-identical STAR
  fixtures (`STARPreorderTests.testEmitsSTARL0FixtureForComparison` and
  any phase-11 CAR/STAR fixtures) in the same commit, and assert the
  new bytes contain no `V` key in layer-0 entries.
- STAR-lite (version 2 header) is untouched — it has no MST nodes.

### Slice B: verifying stack-based L0 reader + correct STAR→CAR

Rewrite `parseL0Body` to the spec's read model:

- Parse the commit; push the root expectation (`commit.data`). Maintain
  a stack of expected items derived from `l`/`L`, `t`/`T`, and layer-0
  implicit records, in depth-first order.
- For each layer-0 node, buffer the records that follow it (≈4 per node
  on average — this is the spec's bounded-buffering compromise), compute
  their CIDs, reinsert `v` links, strip `L`/`V`/`T`, re-serialize to
  repo-spec node form, and verify the node's CID against the expected
  link (root verifies against `commit.data`).
- Reject: `V` without expected record, `L`/`T` without `l`/`t`,
  trailing bytes after the tree completes, depth-order violations,
  CID mismatches, truncated varints.
- Fix `carDataFromSTARData:`: reconstruct the repo-spec commit block
  (error when `sig` is absent — the spec says sig-less STARs cannot
  become compliant CARs), set the CAR root to the commit CID, and emit
  re-serialized repo-spec node blocks plus records under their now
  verified CIDs.
- Round-trip test: fixture CAR → `STARL0Writer` → new reader → CAR,
  byte-compared block sets and root; malformed-input suite for every
  rejection case above; empty-tree and unarchived-subtree (`L`/`T`
  false) cases.
- Bounded input streaming (chunked reader API) is explicitly out of
  scope here; the internal structure (stack + per-node record buffer)
  must not preclude it.

### Slice C: dead converter removal + ADR

- Delete `starL0DataFromCARData:` and `starLiteDataFromCARData:` with
  caller proof (phase-10 brief already established zero production
  callers; re-verify with grep at commit time). CAR→STAR export does
  not need a converter: the live-MST writer is the export path.
- Record an ADR for STAR versioning and variants: version 1 = STAR-L0,
  version 2 = STAR-lite (local variant, flat key/record, not covered by
  the upstream spec draft), MIME types
  `application/vnd.atproto.star{,-lite}`, and the decision that the
  empty tree is encoded by an absent `data` key (matching the spec's
  format section over its intro prose).

## Constraints

- Repository-module work: never share a slice with a phase-11/12 lane
  touching the same files. The Phase 12 route-pack slices touch
  `XrpcRepoPack.m` — Slice B changes only `STAR.m` and tests, so the
  import call sites are unaffected; if Phase 12 Step 3 is in flight,
  land it first or sequence this after it.
- Slice A changes public wire output. STAR is negotiated only via our
  own vendor MIME types; no third-party consumer is known. Rollback for
  every slice is a single-commit revert; fixtures regenerate
  deterministically.
- No public API removals without caller proof (Slice C).

## Gates (after each slice)

```bash
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
deno task check
deno task lint
```

Linux Docker gate if any Network or Compat file is touched (expected:
none).

## Resolution (2026-07-23)

All three slices landed in a single commit on 2026-07-23:

- **Slice A**: V-flag fix (tied `V` emission to `v` presence in
  `STARMstNode.serializeToDagCBOR:`) + fixture regeneration + new
  `testSTARL0VFlagAbsentWhenVIsAbsent` assertion.
- **Slice B**: `parseL0Body` rewritten as verifying stack-based reader;
  `carDataFromSTARData:` fixed to synthesize a repo-spec commit block,
  set the CAR root to the commit CID, and reject sig-less archives.
  Round-trip, empty-tree, malformed-input, and STAR→CAR conversion
  tests added (6 new test methods).
- **Slice C**: `starL0DataFromCARData:` and `starLiteDataFromCARData:`
  deleted from `.m` and `.h` with zero-caller proof; ADR 0009 recorded
  for versioning, variants, MIME types, and the empty-tree encoding
  decision.

Deciduous goal `#1369` closed; actions `#1370`–`#1372` complete.
Mega-plan Phase 4 item 9 marked complete.

Per the plans README lifecycle rule: this file is superseded by the
commit record, ADR 0009, and the mega-plan status update. It can be
archived or deleted after a reasonable retention window.
