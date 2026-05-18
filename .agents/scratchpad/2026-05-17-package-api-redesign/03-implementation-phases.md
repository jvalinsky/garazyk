# Implementation Phases

Date: 2026-05-17

## Phase 1: Tracking And Inventory

Create scratchpads, Deciduous nodes, and record current verification output.

## Phase 2: Export Map Design

Add explicit subpath exports in each package `deno.json`. Replace broad root barrels with curated named exports.

## Phase 3: Laweta Boundary Cleanup

Keep generic Docker primitives on root. Move ATProto/local-network orchestration to `@garazyk/hamownia/atproto-network`; keep only dependency-free ATProto runtime helpers on `@garazyk/laweta/atproto-runtime`.

## Phase 4: Gruszka Typing Cleanup

Keep root focused on `XrpcClient`, transport, raw client, firehose, and stable generated helper types. Move hand-written namespace clients to `@garazyk/gruszka/legacy-clients`. Keep full generated lexicons on `@garazyk/gruszka/lexicons`.

## Phase 5: Schemat Purity Split

Keep pure topology/schema APIs on root. Move runtime env/git/run-directory helpers to `@garazyk/schemat/runtime`.

## Phase 6: Hamownia Config Split

Keep root focused on scenario authoring. Move config globals to `@garazyk/hamownia/config` and introduce `createScenarioConfig(...)`.

## Phase 7: Documentation And Verification

Add module docs, deprecation notes, focused import smoke tests, and run package checks.

Completed implementation notes:

- Added explicit package subpath exports in all four package `deno.json` files.
- Replaced root barrels with curated named exports.
- Removed all `laweta -> hamownia/schemat` boundary violations and reduced the boundary baseline from 17 known violations to 2 known violations.
- Added public API smoke tests for each package.
- Made `deno doc --lint` pass for all four root entrypoints.

## Rollback Notes

Each package can roll back independently by restoring its previous root barrel and removing the new subpath exports. Scenario script migrations should be mechanical import rewrites only.
