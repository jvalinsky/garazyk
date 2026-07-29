---
sessionId: session-260727-152420-itc8
---

# Requirements

### Goal
Complete Phase 21 / Workstream 07 §O7 in the `phase-21` worktree and make it merge-ready without changing any AppView response bytes.

### Remaining acceptance criteria
- Preserve byte-identical responses for every affected feed, graph, actor, and route-clamp endpoint.
- Keep the new 5-versus-50 page assertions bounded and independent of page size.
- Record `EXPLAIN QUERY PLAN` evidence for the materialized counts/read paths.
- Demonstrate counts migration apply, rollback, and re-apply behavior.
- Demonstrate that lower ingest checkpoint sequences cannot overwrite higher sequences.
- Verify route-boundary limit clamping remains universal after redundant service-clamp removal.

### Constraints
- Do not modify the lexicon validator, SQL parameterization, ingest leasing, or batch-write transaction.
- Do not merge while a response diff, required test failure, or unreviewed scope change remains.

# Technical Design

### Current implementation
- `FeedService.m` now routes `getAuthorFeedForActor:limit:cursor:filter:error:` through `formatFeedItems:`, which batches author hydration and interaction counts and uses `records.created_at` as `indexedAt`.
- `GraphService.m` and `ActorService.m` contain the related batched profile/record hydration work; `ActorService.m` now consumes the batched DID-to-handle result without falling back to a per-DID lookup.
- `RecordBodyBatchHydrationTests.m`, registered in `Garazyk/Tests/test_main.m`, asserts equal query counts for 5- and 50-item author-feed and follows pages.
- The phase prompt identifies earlier scope slices: materialized counters/triggers, profile and record batching, monotonic checkpoint saves, and universal route clamping.

### Completion approach
- Treat captured endpoint bytes as the compatibility oracle: capture the same seeded/request fixtures before and after the remaining cleanup, then use binary comparison rather than semantic JSON comparison.
- Use the actual SQL issued by the counts/read paths with realistic fixtures for `EXPLAIN QUERY PLAN`; retain existing indexes when they satisfy the plan and only change schema if evidence proves it necessary.
- Add focused XCTest coverage next to existing AppView/database tests for migration lifecycle, checkpoint ordering, and every route’s limit behavior. Keep the registered `RecordBodyBatchHydrationTests` as the page-size N+1 regression guard.
- Audit the uncommitted service changes for the payload hazards introduced by batching: timestamp fallback, record order, missing profile fallback, count semantics, embeds, and cursor behavior. Correct only discrepancies against the captured baseline.

# Validation

### Required evidence
- Build using `cmake --build build --target AllTests --parallel 4`.
- Run `./build/tests/AllTests -XCTest RecordBodyBatchHydrationTests` and the focused migration/checkpoint/route suites added or updated for this phase.
- Run `PDS_TEST_REGISTRATION_AUDIT=1 build/tests/AllTests` after reconfiguring CMake so the new suite cannot silently be skipped.
- Save before/after binary captures and a clean diff result for every affected route.
- Save `EXPLAIN QUERY PLAN` output for the counter/read SQL and state which existing index satisfies each predicate/order.
- Run the repository quality gates (`deno task check`, `deno task lint`, `deno task test`, then the gated `AllTests` command). Report unrelated pre-existing failures separately; do not represent them as passes.

### Merge condition
Only commit/merge after all required artifacts are clean, the phase prompt is updated from `in-progress` with truthful evidence, and a SQLite-performance review finds no scan/index, SQL-safety, or payload-parity regression.

# Delivery Steps

### * Step 1: Establish payload and query-plan evidence
Byte-identical baseline and optimized AppView responses are captured and the optimized SQL plans are recorded.
- Identify every endpoint affected by `FeedService.m`, `GraphService.m`, `ActorService.m`, `AppViewDatabase.m`, count materialization, and clamp cleanup.
- Run deterministic seeded requests that exercise author feed, timeline/follow data, actor hydration, and limit boundaries; retain baseline and current raw response bytes.
- Diff each pair byte-for-byte and stop to correct any difference before further optimization work.
- Run `EXPLAIN QUERY PLAN` for the actual counter and hydration queries and record index usage or narrowly remediate a demonstrated plan problem.

###   Step 2: Close phase-specific regression coverage
The remaining Workstream 07 acceptance behaviors are asserted in registered XCTest coverage.
- Extend the relevant migration/database tests to cover counter migration apply, rollback, and re-apply with trigger correctness.
- Extend checkpoint tests to prove a lower sequence cannot replace a persisted higher sequence.
- Audit every AppView route in `AppViewXRpcRoutePack.m` and add or update route-focused tests proving the route boundary clamps limits universally.
- Retain and run `RecordBodyBatchHydrationTests` so 50-item feed/follow pages have bounded query counts independent of page size; reconfigure CMake and perform the registration audit.

###   Step 3: Validate, document, and prepare merge
The phase is documented with reproducible passing evidence and is ready for an independent review.
- Build `AllTests` with `--parallel 4` and run the focused phase suites, then execute the prescribed Deno and gated XCTest quality gates.
- Review the final SQL/read-path diff against Workstream 07 §O7, specifically checking parameterized SQL, payload fallbacks, cursor/order semantics, index fit, and absence of forbidden out-of-scope changes.
- Update `docs/plans/prompts/phase-21-appview-hydration.md` with only verified captures, plans, and test outcomes; leave it in progress if any gate fails.
- Request the SQLite performance audit and merge only after it reports no blocking findings and the working tree contains only intended phase artifacts.