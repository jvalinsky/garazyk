# Refactor Library-Readiness: Execution Prompt

You are executing a 7-plan refactoring roadmap for the Garazyk Objective-C codebase (an ATProto/Bluesky PDS implementation). A thorough review has already been completed and several corrections to the original plans have been identified. You must incorporate the review corrections as you implement — they are not optional.

## Where to Find Everything

### Original Plans (read these first)
```
.opencode/plans/refactor-library-readiness/
├── README.md                          # Overview and execution order
├── 01-pdsdatabase-decomposition.md    # Plan 01
├── 02-unified-db-connection.md        # Plan 02
├── 03-xrpc-routepack-protocol.md      # Plan 03
├── 04-service-binary-entrypoint.md    # Plan 04
├── 05-test-coverage.md                # Plan 05
├── 06-legacy-migration-cleanup.md     # Plan 06
└── 07-stubs-and-todos.md              # Plan 07
```

### Review with Corrections (mandatory — read before implementing each plan)
```
~/.letta/plans/2026-05-15-refactor-library-readiness-review.md
```

This file contains 11 required corrections to the original plans. Each one is a hard constraint, not a suggestion. The most critical:

- **Plan 04**: `ServiceMainContext` C struct with blocks will NOT compile under ARC. Must use an ObjC class instead.
- **Plan 03**: Auto-discovery via `NSClassFromString` is NOT broken on GNUstep — all mechanisms work. Use `+load` self-registration pattern.
- **Plan 06**: Depends on Plan 01 completing first. Execution order must be adjusted.
- **Plan 01**: 5 model classes (`PDSDatabaseAccount`, `PDSDatabaseRepo`, `PDSDatabaseRecord`, `PDSDatabaseBlob`, `PDSDatabaseBlock`) must also be extracted from `PDSDatabase.m`.
- **Plan 04**: Exclude Mikrus from initial migration (untracked, still stabilizing).

### Decision Graph (query for context recovery)
```bash
deciduous nodes          # List all 33 nodes
deciduous edges          # List all relationships
deciduous show 14        # Top-level roadmap goal
deciduous show 17        # Plan 01 goal
deciduous pulse          # Graph health check
```

Key node IDs:
- #14: Library-readiness roadmap (top-level goal)
- #15: Plan 07 (stubs) — execute first
- #16: Plan 05 (tests) — execute partially, then interleave
- #17: Plan 01 (PDSDatabase decomposition) — highest risk
- #18: Plan 06 (migration cleanup) — depends on #17
- #19: Plan 02 (unified DB protocol)
- #20: Plan 03 (XRPC route pack protocol)
- #21: Plan 04 (service binary entry points) — execute last
- #22–26: Completed decisions from review (read these for rationale)
- #27–32: Observations/evidence from review

### Key Source Files (verify claims against actual code)
```
Garazyk/Sources/Database/PDSDatabase.m          # 3,804 lines — the monolith
Garazyk/Sources/Database/PDSDatabase.h           # 1,014 lines — public interface
Garazyk/Sources/Database/Migration/              # Legacy (7 files)
Garazyk/Sources/Database/Migrations/             # Modern (3 files)
Garazyk/Sources/Xrpc/                            # 23 pack/methods files
Garazyk/Binaries/                                # 9 service binary main.m files
Garazyk/Tests/CharacterizationTests/             # 7 files, 1,164 lines existing
Garazyk/Tests/Database/                         # 6+ existing test files
```

## Execution Order

**Corrected order** (different from the README — see review node #25):

```
7 → 5 (partial) → 1 → 6 → 5 (remaining) → 2 → 3 → 4
```

1. **Plan 07** — Stub/TODO documentation (low risk, warm-up)
2. **Plan 05 partial** — Write characterization tests only for the inline PDSDatabase categories (Accounts, Repos, Blocks, Blobs, Transactions, VideoJobs) — NOT all 11 categories
3. **Plan 01** — PDSDatabase decomposition (highest risk, highest value)
4. **Plan 06** — Legacy migration cleanup (depends on Plan 01 being done)
5. **Plan 05 remaining** — Tests for other categories as needed
6. **Plan 02** — Unified database connection protocol
7. **Plan 03** — XRPC route pack protocol
8. **Plan 04** — Service binary entry points

## How to Log Progress

After completing each plan phase, log it in the decision graph:

```bash
# When starting a plan:
deciduous add action "Implementing Plan 07: stub documentation" -c 85 -f "affected/files"
deciduous link <plan_goal_id> <new_action_id> -r "implementation"

# When finishing a plan:
deciduous add outcome "Plan 07 complete: X stubs documented" -c 95 --commit HEAD
deciduous link <action_id> <outcome_id> -r "implementation complete"
deciduous status <plan_goal_id> completed
```

## Critical Constraints

1. **GNUstep/Linux compatibility is mandatory.** This project runs on both macOS and Linux via GNUstep. Every change must compile and work under both runtimes. Use the `gnustep-compat` skill for guidance.

2. **The review corrections are not optional.** If the original plan says one thing and the review says another, follow the review.

3. **Build after every phase.** Run the full build (CMake + XcodeGen) after each plan completes. Do not accumulate build breaks across plans.

4. **Each plan has rollback strategies.** Read them before starting. If something goes wrong, rollback rather than pushing through.

5. **Existing tests must continue passing.** Run `Tests/test_main.m` after each change. The existing CharacterizationTests and Database tests are your safety net.

6. **Mikrus is out of scope.** Do not touch `Garazyk/Binaries/mikrus/` or `Garazyk/Sources/Mikrus/`. They are untracked and still stabilizing.
