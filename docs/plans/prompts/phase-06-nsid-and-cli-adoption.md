---
phase: 6
title: Generated NSID constants and CLI/lifecycle adoption
status: in-progress
agent: claude
depends_on: [3]
---

# Phase 6: Generated NSID constants and CLI/lifecycle adoption

## Progress (2026-07-17)

- Generator landed: `f46ab5fb8` generates ObjC NSID constants from the
  canonical lexicons (`scripts/generate_nsid_constants.ts`).
- The call-site adoption sweep is committed: every `Xrpc*Pack.m`,
  `XrpcHandler.h/.m` (pass-through registration methods deleted),
  Germ/Video packs, the CI drift-check job, and
  `scripts/migrate_nsid_constants.ts`/`migrate_nsid_strings.ts`. This
  landed separately from phase 7's relay-removal and sync-slice commits,
  which shared the same worktree — see `docs/plans/prompts/README.md`
  for the loop-protocol rule this hazard produced.
- Remaining: raw-literal lint against new endpoint literals, then the
  untouched CLI/lifecycle adoption arc (scope item 2).

## Mission

Two mechanical-but-broad hygiene arcs, both explicitly gated until phase 3's
endpoint classification is correct: generate plain Objective-C NSID
constants from the canonical lexicon root, and finish
`GZCommandLineOptions`/`GZServiceLifecycle` adoption across the remaining
binaries.

## Read first

- `docs/plans/workstreams/02-core-architecture-and-reliability.md` (A4, A7)
- `docs/adr/0003-xrpc-registration-uses-plain-nsid-constants.md`
- The generator core at `Garazyk/Resources/lexicons` (phase 3 will have
  touched classification — reread its output)

## Scope

1. **NSID constants** (A7, mega Phase 3 item 3): generate
   `NSString * const` endpoint NSIDs deterministically with a CI drift
   check; migrate registration call sites in staged slices; delete
   XrpcHandler pass-through registration methods in stages; lint against
   new raw endpoint literals.
2. **CLI/lifecycle adoption** (A4, mega Phase 3 item 4): for each binary
   beyond Beskid/Mikrus/Syrena — characterize current options/exit
   codes/stderr first, port to `GZCommandLineOptions` +
   `GZServiceLifecycle`, preserve service-specific signals and Linux
   category checks, smoke `--help` plus one real invocation on macOS and
   Linux. One binary per commit.

Out of scope: god-file decomposition (mega Phase 4), any behavior change.

## Constraints

- GNUstep category loading must be proven before any category-based split.
- Run the Linux Docker gate for binary entrypoint changes.
- Bound builds at `-j4`.

## Acceptance gate

- Generated constants byte-stable across two runs; drift check in CI.
- Every migrated registration site covered by the existing route
  characterization; AllTests green after each slice.
- Each ported binary has its characterization diff (before/after identical).

## On completion

Update workstream 02 A4/A7, mega-plan Phase 3 items 3-4; set
`status: complete` here.
