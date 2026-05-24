# Refactoring Audit Methodology: Mikrus, Beskid, and Syrena

This document outlines the systematic methodology for researching and auditing
shared code, patterns, and refactoring opportunities between the three services:
**Mikrus** (link index service), **Beskid** (edge/identity cache), and
**Syrena** (standalone AppView).

## Audit Objectives

1. Identify and inventory overlapping architectural patterns across the three
   binaries.
2. Pinpoint duplicate and boilerplate code in entrypoints, runtime bootstrap,
   database initialization, configuration loading, and XRPC routing.
3. Quantitatively score duplication targets based on safety, structural drag,
   and refactor payoff.
4. Draft a modular architecture design that extracts common patterns into
   reusable core/shared library primitives without compromising service
   boundaries.
5. Define a safe, staged execution roadmap to implement the recommended
   refactors.

## Evidence Sources

We will analyze the following primary files and source directories in the
repository:

- **Binaries**:
  - `Garazyk/Binaries/mikrus/main.m`
  - `Garazyk/Binaries/beskid/main.m`
  - `Garazyk/Binaries/syrena/main.m`
- **Configuration Layers**:
  - `Garazyk/Sources/Mikrus/MikrusConfiguration.[hm]`
  - `Garazyk/Sources/Beskid/BeskidConfiguration.[hm]`
  - `Garazyk/Sources/AppView/Server/Config/AppViewConfiguration.[hm]`
- **Runtime Layers**:
  - `Garazyk/Sources/Mikrus/MikrusRuntime.[hm]`
  - `Garazyk/Sources/Beskid/BeskidRuntime.[hm]`
  - `Garazyk/Sources/AppView/Server/AppViewRuntime.[hm]`
- **Database Layers**:
  - `Garazyk/Sources/Mikrus/MikrusDatabase.[hm]`
  - `Garazyk/Sources/Beskid/BeskidDatabase.[hm]`
  - `Garazyk/Sources/AppView/Server/AppViewDatabase.[hm]`
- **XRPC Route Packs**:
  - `Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.[hm]`
  - `Garazyk/Sources/Beskid/BeskidXrpcRoutePack.[hm]`
  - `Garazyk/Sources/AppView/Server/Lexicon/` or other routes.

## Scoring Criteria

Each candidate for extraction will be scored from 1 (low/unfavorable) to 5
(high/favorable) on:

1. **Boundary Risk**: Risk of cross-contamination or leaking service-specific
   business logic into shared libraries. (Higher score = lower risk).
2. **Structural Drag**: The amount of boilerplate or complexity this duplication
   currently introduces. (Higher score = high drag/high benefit to remove).
3. **Test Leverage**: Whether extracting this component into a shared library
   creates a single, clean interface that dramatically simplifies unit testing.
4. **Change Safety**: Safety of extraction; likelihood of side effects during
   refactoring.
5. **Refactor Payoff**: Total complexity/LOC reduced vs effort required to
   extract.

## Staging & Rollback Strategy

Any recommended refactor must use safe, progressive extraction:

- **Step 1**: Create a shared core capability or protocol (e.g., in a
  `GZServiceCore` or `GZDatabaseCore` module).
- **Step 2**: Write unit/characterization tests for the new shared module.
- **Step 3**: Port a single service (e.g. Beskid, which is simpler) to use the
  new shared component.
- **Step 4**: Verify functionality against scenario/E2E tests.
- **Step 5**: Port the remaining services (Mikrus and Syrena).
- **Rollback Path**: Retain old implementations under temporary namespace
  switches if necessary, relying on Git branches for absolute recovery.
