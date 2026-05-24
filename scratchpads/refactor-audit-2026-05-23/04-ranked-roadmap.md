# Refactoring Ranked Roadmap: Mikrus, Beskid, and Syrena

This document defines a structured, phased execution plan to safely extract
duplicate patterns and boilerplate across **Mikrus**, **Beskid**, and **Syrena
(AppView)** without interrupting live services or breaking protocol compliance.

---

## Refactoring Phased Plan

### Phase 1: Database Query Runner Extraction (Immediate)

**Goal**: Centralize C-level SQLite binding and execution boilerplate into
`ATProtoDatabaseQueryRunner`.

1. **Scaffold Query Runner**: Create `ATProtoDatabaseQueryRunner.[hm]` in
   `Garazyk/Sources/Database/Utils/`.
2. **Implement Runner Logic**: Implement connection pool manager execution
   wrapping, error logging, and standard statement binding utilizing inline
   `ATProtoDBBindParams` and `ATProtoDBColumnValue` functions.
3. **Write Direct Unit Tests**: Create `ATProtoDatabaseQueryRunnerTests.m` under
   `Garazyk/Tests/Database/` to directly verify execution, binding, and error
   conversion.
4. **Port Beskid**: Port `BeskidDatabase.m` to use `ATProtoDatabaseQueryRunner`.
   Run `BeskidTests` to verify functionality.
5. **Port Mikrus**: Port `MikrusDatabase.m` to use `ATProtoDatabaseQueryRunner`.
   Run `MikrusTests` to verify functionality.
6. **Eliminate Duplicates**: Safely delete duplicate query helpers in
   `MikrusDatabase.m` and `BeskidDatabase.m`.

**Staging & Rollback**:

- Since the query runner does not modify database schemas, a rollback only
  requires resetting the modified `.m` database classes in Git.

---

### Phase 2: Route Helper & DID Parser Extraction (Immediate)

**Goal**: Factor out overlapping XRPC query parameter validations, rate limiter
checks, and DID document parsers into `GZXrpcHelper`.

1. **Scaffold Helper**: Create `GZXrpcHelper.[hm]` in `Garazyk/Sources/Network/`
   or a shared utility namespace.
2. **Move Helpers**: Move `checkRateLimitForRequest:response:`,
   `requiredParam:request:response:`, and `handleFromDocument:` to
   `GZXrpcHelper`.
3. **Write Unit Tests**: Add direct unit tests matching standard DID documents
   to verify handle, PDS endpoint, and verification key extraction.
4. **Refactor Route Packs**:
   - Refactor `MikrusXrpcRoutePack.m` to make class method calls to
     `GZXrpcHelper`.
   - Refactor `BeskidXrpcRoutePack.m` similarly.
5. **Verify Routing Safety**: Run `AllTests` (particularly `MikrusTests` and
   `BeskidTests`) to guarantee no request routing, rate limiting, or parameter
   extraction failures were introduced.

---

### Phase 3: Configuration Base Class Integration (Secondary)

**Goal**: Unified properties (`httpPort`, `dataDirectory`, rate limits) and
common scanners (port checking, CSV split) inside `GZBaseConfiguration`.

1. **Scaffold Parent**: Create `GZBaseConfiguration.[hm]` under
   `Garazyk/Sources/Shared/` or `Core/`.
2. **Inheritance Swap**: Make `MikrusConfiguration`, `BeskidConfiguration`, and
   `AppViewConfiguration` inherit from `GZBaseConfiguration`.
3. **Boilerplate Cleanup**: Delete duplicate properties and copy-pasted
   `splitCSV:` or scanner-based port validations.
4. **Verification**: Verify environment overrides load correctly via config
   tests.

---

### Phase 4: Entrypoint Signal Trapping Extraction (Tertiary)

**Goal**: Consolidate redundant signal trapping and Curl global init inside a
helper module or `GZServiceLifecycle`.

1. **Scaffold Lifecycle Helper**: Create a lifecycle helper
   `GZServiceLifecycle.[hm]`.
2. **Simplify entrypoints**: Replace raw signal trapping block copy-pastas in
   `main.m` with a unified lifecycle start/stop coordinator.

---

## Characterization Testing Strategy

Before modifying any implementation code, we must execute the existing XCTest
suites to establish a performance and correctness baseline:

```bash
# Propose running all unit tests to baseline behavior
make -C build AllTests -j4
./build/tests/AllTests
```

Any modification to database execution or routing logic must be followed by
running the exact service suite:

- **Mikrus Tests**:
  [MikrusTests.m](file:///Users/jack/Software/garazyk/Garazyk/Tests/Mikrus/MikrusTests.m)
- **Beskid Tests**:
  [BeskidTests.m](file:///Users/jack/Software/garazyk/Garazyk/Tests/Beskid/BeskidTests.m)

Only when all baselines pass are the changes considered complete and safe to
stage.
