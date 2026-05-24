# Refactoring Risk & Impact Scores: Mikrus, Beskid, and Syrena

This document ranks and scores each extraction candidate from 1
(low/unfavorable) to 5 (high/favorable) to identify the highest leverage
refactoring targets.

## Candidates Under Consideration

### Candidate A: Service Entrypoint & Lifecycle Bootstrap

Consolidate bootstrapping boilerplate (signals, crash reporters, curl setup,
category checks) in `main.m` files.

- **Boundary Risk**: 5/5 (Zero risk. Bootstrapping is standard system setup and
  contains no business logic.)
- **Structural Drag**: 3/5 (Boilerplate is ~30 LOC per service, easily copied
  but annoying.)
- **Test Leverage**: 2/5 (Unlikely to be unit tested; mostly system-level
  hooks.)
- **Change Safety**: 4/5 (Extremely safe; only risk is incorrect signal
  routing.)
- **Refactor Payoff**: 3/5 (Cleans up `main.m` entries to be highly clean and
  legible.)
- **Overall Score**: **17 / 25**

---

### Candidate B: CLI Argument Parser & Option Standardizer

Create a unified command-line option parser wrapper in the shared network or CLI
module.

- **Boundary Risk**: 4/5 (Low risk. Different services accept slightly different
  flags, but they can be passed in as a schema.)
- **Structural Drag**: 4/5 (Highly boilerplate-heavy. Each service currently
  maintains manual array loop scanning.)
- **Test Leverage**: 4/5 (High leverage. CLI parser schemas can be thoroughly
  unit tested in isolation.)
- **Change Safety**: 4/5 (Safe. Option parsing is deterministic and stateless.)
- **Refactor Payoff**: 4/5 (Removes massive manual `for` loops in each `main.m`
  file.)
- **Overall Score**: **20 / 25**

---

### Candidate C: Base Service Configuration Class

Extract shared properties (`httpPort`, `dataDirectory`, rate limits) and
lifecycle utilities into a common configuration parent class
`GZBaseServiceConfiguration`.

- **Boundary Risk**: 4/5 (Low risk. Properties like directory and port are
  universal across all service layers.)
- **Structural Drag**: 4/5 (High. All configuration classes implement identical
  CSV split, dictionary mapping, and validation.)
- **Test Leverage**: 4/5 (Allows unified testing of environment overrides and
  dictionary parser mappings.)
- **Change Safety**: 3/5 (Medium. Must ensure service-specific configurations
  maintain custom load-order overrides.)
- **Refactor Payoff**: 4/5 (Substantially reduces duplicate parsing and
  validation boilerplate.)
- **Overall Score**: **19 / 25**

---

### Candidate D: SQLite Connection-Pool Helper Extraction

Extract the pooled `executeQuery:params:error:` and
`executeUpdate:params:connection:error:` wrappers into a database category or
shared base class (e.g., `GZDatabaseBase`).

- **Boundary Risk**: 5/5 (No risk. These are generic SQLite statement binding
  and execution routines.)
- **Structural Drag**: 5/5 (High drag. The exact same ~100 lines of SQLite
  execution code are duplicated in Mikrus and Beskid.)
- **Test Leverage**: 4/5 (Allows testing SQLite bindings and error mapping in
  one central test suite.)
- **Change Safety**: 5/5 (Extremely safe. Query and update logic is simple and
  well-defined.)
- **Refactor Payoff**: 5/5 (Removes identical C-level SQLite prepare/step
  loops.)
- **Overall Score**: **24 / 25** (Top Priority)

---

### Candidate E: Database Connection Unification for AppView (Syrena)

Upgrade Syrena's raw single-connection serialized dispatch queue system to
utilize the common connection-pool framework (`ATProtoConnectionPool`).

- **Boundary Risk**: 4/5 (Low risk. AppView is a heavy read-heavy query service,
  which would benefit enormously from pooling.)
- **Structural Drag**: 3/5 (Medium drag. Currently runs on a private serialized
  queue which restricts concurrent read scaling.)
- **Test Leverage**: 3/5 (Testing is already established, but pooling would
  improve mock isolation.)
- **Change Safety**: 2/5 (High risk. AppView has complex background backfills
  and write proxies; modifying its concurrency engine could introduce
  regressions.)
- **Refactor Payoff**: 5/5 (Huge performance and architectural payoff by
  bringing AppView in line with PDS connection pooling standards.)
- **Overall Score**: **17 / 25**

---

### Candidate F: XRPC HTTP & Identity Parsing Utilities

Move duplicate rate-limiter assertions (`checkRateLimitForRequest:...`),
parameter requirements, and DID document parser helpers (`handleFromDocument:`,
`pdsEndpointFromDocument:`) into a shared network/identity framework.

- **Boundary Risk**: 5/5 (Zero risk. Standard ATProto specs dictate how handles
  and endpoint structures are loaded from DID documents.)
- **Structural Drag**: 4/5 (Identical route helpers and DID resolution snippets
  are copied across multiple route packs.)
- **Test Leverage**: 5/5 (High leverage. Allows DID parser helpers to be
  verified against mock PLC documents in isolation.)
- **Change Safety**: 4/5 (Very safe; parser code is functional, stateless, and
  simple.)
- **Refactor Payoff**: 4/5 (Cleans up bloated route packs to focus solely on
  route mapping and execution.)
- **Overall Score**: **22 / 25** (High Priority)

---

## Ranked Roadmap Matrix

| Rank  | Candidate                               | Category    | Score     | Complexity | Safety         | Refactor Priority |
| ----- | --------------------------------------- | ----------- | --------- | ---------- | -------------- | ----------------- |
| **1** | **D**: SQLite Query/Update Helpers      | Database    | **24/25** | Low        | Extremely High | Immediate         |
| **2** | **F**: XRPC & Identity Parsing Helpers  | Network/ID  | **22/25** | Low-Med    | High           | Immediate         |
| **3** | **B**: CLI Argument Option Parser       | CLI/Tooling | **20/25** | Medium     | High           | Secondary         |
| **4** | **C**: Base Configuration Model         | Core        | **19/25** | Medium     | Medium         | Secondary         |
| **5** | **A**: Entrypoint & Signal Setup        | Core        | **17/25** | Low        | High           | Tertiary          |
| **6** | **E**: AppView Database Connection Pool | Database    | **17/25** | High       | Low-Med        | Deferred          |
