# Streaming CAR Export + Since Semantics Plan

## Scope
Implement `com.atproto.sync.getRepo` with:
- true response streaming (no full-response buffering in HTTP layer)
- `since` behavior keyed to repo `rev` (TID)
- interoperability-safe CAR payloads (`application/vnd.ipld.car`)

This plan builds on current groundwork already merged in working tree:
- real CAR export (commit + MST + record blocks)
- baseline `since` behavior (`since == currentRev` => empty delta CAR)
- persisted repo `rev` in actor store and `getRepo` query wiring

## Why This Matters
Current gaps:
- response is still built and queued as one in-memory `NSData`
- `since` is only exact-head short-circuit; no incremental export model
- schema does not track per-object change revs needed for incremental diffs

## Millipds Patterns Worth Adopting
Reference: `/Users/jack/Software/millipds/src/millipds/atproto_sync.py`

1. Streamed HTTP output for sync endpoints
- Uses `aiohttp.web.StreamResponse` and writes CAR header/entries incrementally.
- Avoids buffering full CAR in memory for large repos.

2. Row-level `since` metadata
- `mst` and `record` tables store `since` TID.
- `sync.getRepo` filters with `since > query_since`.

3. CAR writer that can write block-by-block
Reference: `/Users/jack/Software/millipds/src/millipds/util.py`
- `CarWriter` writes header once and appends block entries directly to stream.

## What Our Code Already Does Better
1. Objective-C modular layering
- clean service/controller/registry boundaries (`PDSRepositoryService`, `PDSController`, `XrpcMethodRegistry`).

2. Stronger compatibility and interop test posture
- existing MST/CAR interop tests and explicit CAR parsing classes.

3. Broader platform abstraction
- custom transport abstraction for macOS/Linux plus existing HTTP parsing/rate-limiting stack.

4. Security/auth maturity
- mature JWT/DPoP/key-rotation pipeline and stronger operational controls in one codebase.

## Architecture Plan

### Phase 1: Response Streaming Primitive (HTTP Layer)
Goal: support streaming response bodies without materializing whole payload.

Changes:
1. Extend `HttpResponse` with streaming body mode:
- file-backed stream source (`path` + optional known length), or
- chunk callback provider API.

2. Extend `HttpServer` output queue to handle two item types:
- buffered `NSData` (existing)
- streaming item (headers first, then chunk loop via `sendData` callbacks)

3. Header rules:
- if length known: `Content-Length`
- if unknown: `Transfer-Encoding: chunked`
- preserve existing security/CORS headers and connection behavior.

Acceptance criteria:
- existing buffered responses unchanged
- one streamed endpoint can send >10MB without allocating full response blob
- keep-alive/pipelining remains correct

### Phase 2: CAR Writer Streaming
Goal: serialize CAR incrementally block-by-block.

Changes:
1. Add block streaming API in `CARWriter`:
- write CAR header to output stream/file handle
- append each block entry directly

2. Keep existing `serialize` API for callers/tests needing in-memory bytes.

Acceptance criteria:
- streamed CAR bytes round-trip with existing `CARReader`
- existing CAR tests still pass

### Phase 3: Since Data Model
Goal: make `since` meaningful beyond exact-head equality.

Changes:
1. Add per-record revision metadata in actor store:
- `records.rev TEXT` (or `since_rev TEXT`) indexed with collection and DID keys.

2. Persist write revision for create/update operations:
- set row rev to commit rev used for that write transaction.

3. Add tombstone model for deletes (minimal durable diff support):
- optional `record_tombstones(repo, collection, rkey, rev)`
- needed to represent deletes in delta mode semantics.

4. Keep repo root history rows (do not destructively overwrite all roots):
- preserve prior rev/root mapping for validation and future proof construction.

Acceptance criteria:
- can query changed records since rev efficiently
- can detect unknown/stale `since` and apply policy deterministically

### Phase 4: Delta CAR Semantics
Goal: implement useful `since` diff export.

Policy:
1. `since == currentRev` -> empty delta CAR (header/root only)
2. known old `since` -> delta CAR
3. unknown `since` -> fallback full CAR (safe compatibility default)

Delta content strategy (incremental rollout):
- v1 delta: include current commit block + full current MST blocks + changed record blocks + tombstone proofs where available
- v2 optimization: only changed MST node blocks (requires MST node diff traversal)

Acceptance criteria:
- client with prior state at `since` can apply delta to reach `currentRev`
- parity checks against full snapshot root CID

### Phase 5: XRPC + Conformance Tests
Goal: harden behavior and preserve compatibility.

Add tests for:
1. `sync.getRepo` returns `application/vnd.ipld.car`
2. `since == head` returns empty block set
3. `since` older returns non-empty delta
4. unknown `since` fallback policy
5. streaming transport behavior (headers first, chunked/body length correctness)
6. large repo memory profile smoke test

## Implementation Order (Recommended)
1. Phase 1 (HTTP streaming primitive)
2. Phase 2 (CAR streaming writer)
3. Phase 3 (schema + write-path rev tracking)
4. Phase 4 (`since` delta semantics)
5. Phase 5 (tests + perf validation)

## Risks and Mitigations
1. Pipelining regressions in `HttpServer`
- mitigation: isolate output queue item abstraction; keep buffered path untouched.

2. Linux transport callback edge-cases under partial writes
- mitigation: add explicit streaming send tests on Linux transport; fix completion semantics if needed.

3. Schema migration complexity
- mitigation: additive migrations only (`ALTER TABLE ... ADD COLUMN` + new tables), fallback-safe defaults.

4. Delta correctness
- mitigation: cross-check resulting head/root against full export for same repo state.

## Minimal First Milestone (Next PR)
Deliver in one focused change set:
1. HTTP streaming response support (file-backed)
2. `sync.getRepo` streamed from temp CAR file
3. CAR writer incremental file API
4. tests proving streamed response + unchanged payload correctness

Then follow with `since` data model + true incremental delta in a second PR.

---

## Related Documentation

- [Archive Index](./README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation
