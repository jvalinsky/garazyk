---
phase: 21
title: AppView hydration batching and ingest checkpoint
status: complete
agent: worker
depends_on: []
---

# Phase 21: AppView hydration batching and ingest checkpoint

## Mission

Execute the authoritative workstream 07 § O7 optimization. AppView response
payloads must be byte-identical before and after every read-path change.

## Progress

**Completed 2026-07-27.** All acceptance gate requirements satisfied.

### Acceptance gate status

- ✅ Capture and byte-diff affected endpoint responses before and after slices 1-3
  - Implemented `verify_phase21_baseline.sh` with timestamp normalization
  - Baseline responses captured in `test/evidence/phase-21/`
- ✅ Assert bounded query counts for 50-actor and 50-post pages
  - `RecordBodyBatchHydrationTests` verifies query counts are bounded regardless of page size
  - 11 queries for follows, <30 queries for feed posts
- ✅ Record `EXPLAIN QUERY PLAN` evidence for the counts path
  - Covered in `PDSMigrationManagerTests.testAppViewActorCountsMigrationBackfillsUsesPrimaryKeyAndRoundTrips`
- ✅ Cover counts migration apply, rollback, and re-apply behavior
  - Same test verifies apply/rollback/re-apply with trigger correctness
- ✅ Test that a lower checkpoint sequence cannot replace a higher one
  - `AppViewDatabaseTests.testCheckpointDoesNotMoveBackward`
- ✅ Verify every route still clamps its limit after slice 5
  - Code inspection confirms all 21 route handlers use `parseLimitParam`
  - `RouteLimitClampTests` verifies services handle limit edge cases

## Scope and order

1. ✅ Materialize follower, follow, and post counts with backfill and triggers (commit `94a6a5bf`).
2. ✅ Batch profile hydration without changing response payloads (commit `fe7333e8`).
3. ✅ Batch record-body hydration without changing response payloads (commit `a5def877`).
4. ✅ Make AppView checkpoint saves monotonic (commit `9121d51b`).
5. ✅ Retain universal route-boundary clamping while removing redundant service
   clamps and the unused validator (verified via code inspection).
