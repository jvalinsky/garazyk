# Refactoring Risk and Impact Scores: Mikrus, Beskid, and Syrena

Scores are from 1 to 5. Higher is better for boundary risk, test leverage,
change safety, and payoff. Higher structural drag means there is more
maintenance cost to remove.

## Candidate A: Entrypoint and Lifecycle Bootstrap

Consolidate common setup in the service `main.m` files: signal ignore setup,
crash reporter install, GNUstep `curl_global_init`, category link forcing, and
graceful shutdown registration.

- **Boundary Risk**: 4/5. Common setup is generic, but Syrena has additional
  exception/SIGABRT and category-verification behavior.
- **Structural Drag**: 3/5. The duplication is visible but small.
- **Test Leverage**: 2/5. Most behavior is process-level and better covered by
  smoke tests.
- **Change Safety**: 4/5. Safe if hooks stay explicit and service-owned.
- **Refactor Payoff**: 3/5. Cleans entrypoints but does not change core
  maintenance cost much.
- **Overall Score**: **16/25**

## Candidate B: CLI Argument Parser and Option Standardizer

Create a small schema-driven command-line parser for service binaries.

- **Boundary Risk**: 4/5. Option schemas can keep service-specific flags
  separate.
- **Structural Drag**: 4/5. Each binary has a manual array loop with repeated
  missing-value and unknown-option checks.
- **Test Leverage**: 4/5. Parser behavior can be tested without starting
  runtimes.
- **Change Safety**: 4/5. Deterministic input/output makes regressions easy to
  catch.
- **Refactor Payoff**: 4/5. Removes repeated control flow and makes new service
  flags less error-prone.
- **Overall Score**: **20/25**

## Candidate C: Configuration Parsing Utilities

Extract shared configuration parsing helpers for environment lookup, CSV
splitting, numeric parsing, boolean parsing, and bounded port validation.

- **Boundary Risk**: 4/5. Parsing primitives are generic; service properties are
  not.
- **Structural Drag**: 4/5. Mikrus/Beskid repeat several loaders, and AppView
  has similar but larger logic.
- **Test Leverage**: 4/5. Parser functions can get direct unit coverage.
- **Change Safety**: 3/5. A base class or inheritance swap would be riskier than
  parser helpers.
- **Refactor Payoff**: 3/5. Useful cleanup, but less urgent than database and
  route helpers.
- **Overall Score**: **18/25**

## Candidate D: SQLite Query Runner Extraction

Extract Mikrus/Beskid query, update, and transaction wrapper code into a shared
database utility that uses `ATProtoConnectionManager`.

- **Boundary Risk**: 5/5. The duplicated behavior is generic SQLite statement
  execution.
- **Structural Drag**: 5/5. Mikrus and Beskid repeat the same
  prepare/bind/step/row/finalize control flow.
- **Test Leverage**: 5/5. A shared runner can be tested against an in-memory or
  temporary SQLite database.
- **Change Safety**: 4/5. Error domains, null handling, and finalization
  behavior must be preserved.
- **Refactor Payoff**: 5/5. Removes the most direct copy/paste while creating a
  reusable primitive for later services.
- **Overall Score**: **24/25** (top priority)

## Candidate E: AppView Database Connection Unification

Move Syrena/AppView from a raw serialized SQLite connection toward the
`ATProtoConnectionManager`/pool framework.

- **Boundary Risk**: 3/5. The desired primitive is shared, but AppView has a
  larger concurrency surface.
- **Structural Drag**: 3/5. AppView has repeated parameterized SQL code, but it
  is not the same as the Mikrus/Beskid path.
- **Test Leverage**: 3/5. Existing AppView database tests help, but concurrency
  behavior needs characterization first.
- **Change Safety**: 2/5. Backfills, write-proxy paths, and serialized access
  assumptions make this high-risk.
- **Refactor Payoff**: 4/5. Potentially valuable, but only after the smaller
  runner extraction proves stable.
- **Overall Score**: **15/25** (deferred)

## Candidate F: XRPC Route Support and DID Document Field Extraction

Extract duplicated Mikrus/Beskid route helpers and consolidate DID document
field parsing through existing network/identity primitives.

- **Boundary Risk**: 4/5. Query-parameter and rate-limit response helpers are
  generic; DID parsing must preserve legacy and current document shapes.
- **Structural Drag**: 4/5. Route packs repeat the same rate-limit, parameter,
  and identity parsing snippets.
- **Test Leverage**: 5/5. DID field extraction and HTTP error response helpers
  can be covered with direct fixtures.
- **Change Safety**: 4/5. Safe if it delegates to `XrpcErrorHelper`,
  `RateLimiter`, and `DIDDocument` helpers rather than replacing them wholesale.
- **Refactor Payoff**: 4/5. Route packs become smaller and identity parsing
  becomes less fragmented.
- **Overall Score**: **21/25** (high priority)

## Ranked Roadmap Matrix

| Rank | Candidate                            |         Category | Score | Complexity | Safety      | Priority  |
| ---- | ------------------------------------ | ---------------: | ----: | ---------- | ----------- | --------- |
| 1    | D: SQLite Query Runner               |         Database | 24/25 | Low-medium | High        | Immediate |
| 2    | F: XRPC Route Support and DID Fields | Network/Identity | 21/25 | Medium     | High        | Immediate |
| 3    | B: CLI Option Parser                 |      CLI/Tooling | 20/25 | Medium     | High        | Secondary |
| 4    | C: Configuration Parsing Utilities   |             Core | 18/25 | Medium     | Medium      | Secondary |
| 5    | A: Entrypoint Lifecycle Bootstrap    |             Core | 16/25 | Low        | Medium-high | Tertiary  |
| 6    | E: AppView Connection Unification    |         Database | 15/25 | High       | Low-medium  | Deferred  |
