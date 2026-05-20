# Garazyk Code Review & Remediation: Detailed Action Plan

Based on the research findings and master checklists, this execution plan outlines the step-by-step approach to reviewing and remediating the codebase. The effort is structured into three prioritized phases: High-Risk Security & Stability, Core Architecture & Determinism, and DX & Tooling Accuracy.

## 1. Phase 1: High-Risk Security & Stability (Immediate Focus)
These items represent potential vulnerabilities, resource leaks, or immediate stability threats and should be addressed first.

### 1.1 `schemat` (Topology & Docker Compose)
- **Task 1: Safe YAML Serialization:** Replace all manual string concatenation in `renderComposeYaml()` with a robust YAML serializer (e.g., `@std/yaml`) to prevent injection, quoting bugs, and syntax corruption.
- **Task 2: Path Traversal Protection:** Refactor `renderVolume()` to resolve and validate paths against a trusted root directory. It must reject symlink escapes and strictly prevent directory traversal.

### 1.2 `laweta` (Docker Engine API)
- **Task 1: Socket Resource Management:** Audit `Deno.createHttpClient` usage to ensure `client.close()` is deterministically called, avoiding `EMFILE` and Rust-side memory leaks.
- **Task 2: NDJSON Buffer Limits:** Implement hard upper bounds on the NDJSON parser's partial-line buffers to prevent Out-of-Memory (OOM) or DoS conditions from malformed streams without newlines.
- **Task 3: Multiplex Stream Boundaries:** Verify the 8-byte Docker log multiplexing parser strictly respects chunk boundaries without losing bytes.

### 1.3 `gruszka` (XRPC & Firehose)
- **Task 1: DAG-CBOR Hardening:** Audit the DAG-CBOR decoder for maximum recursion depth limits (preventing stack exhaustion) and prototype pollution mitigations (rejecting `__proto__` and `constructor`).
- **Task 2: Idempotent Retries:** Restrict `TransportLayer`'s automatic HTTP retry logic strictly to `GET` operations; retrying `POST` without explicit idempotency keys is unsafe.

### 1.4 `narzedzia` (Static Analysis Tools)
- **Task 1: Security Hotspots Audit:** Review `ops_command.ts` to ensure path generation, SQL construction, and DID validation do not rely on free-form string concatenations.

---

## 2. Phase 2: Core Architecture & Determinism (Short-term Focus)
These tasks resolve architectural brittleness and unpredictable behavior that will complicate future development.

### 2.1 `tui` (Terminal UI Layout)
- **Task 1: Layout Engine Constraints:** Refactor `solveLayout()` to safely handle min/max constraints, overflow, and explicit remainder pixel distribution policies.
- **Task 2: Resize Invalidation:** Guarantee that `ScreenBuffer` actively drops its cached diff baseline and re-renders when terminal geometry changes.
- **Task 3: Sans-IO Environment Boundary:** Ensure layout and rendering functions do not read environment variables (like `NO_COLOR`) natively; require configuration to be injected by the consumer.

### 2.2 `hamownia` (Scenario Orchestration)
- **Task 1: Process Lifecycle Safety:** Migrate `Deno.Command` executions to utilize `AbortSignal.timeout()` to cleanly send `SIGTERM` and reliably kill zombie child processes.
- **Task 2: Mock Server Isolation:** Enforce strict state cleanup (clearing in-memory Maps) in `MockTwilioServer` between scenario runs to prevent cross-contamination.
- **Task 3: Reliable Telemetry:** Shift to `SimpleSpanProcessor` for synchronous OpenTelemetry span reporting to ensure failure traces are captured before a potential runner crash.

### 2.3 `schemat` (Topology Manifests)
- **Task 1: Versioned Schema Models:** Deprecate ad-hoc v1/v2 branches in `compileTopology()` and implement a version-discriminated schema model with a defined migration path.
- **Task 2: Explicit Health Probes:** Update the DSL to require explicit health-port properties rather than inferring them from the first mapped container port.

---

## 3. Phase 3: DX & Tooling Accuracy (Mid-term Focus)
These items improve the developer experience, code quality, and maintainability.

### 3.1 `narzedzia` (Module Boundaries & DX)
- **Task 1: AST-Aware Import Scans:** Replace regex-based import parsing with AST or lexer-backed tools to correctly identify `import type`, dynamic imports, and module aliases.
- **Task 2: Model-Based Doc Coverage:** Migrate TSDoc and Objective-C documentation coverage metrics away from text heuristics towards structured parser models.

### 3.2 `gruszka` (XRPC DX)
- **Task 1: Firehose Cursor Resumption:** Ensure the WebSocket consumer tracks sequence cursors persistently to resume streams without dropping or duplicating events.
- **Task 2: Type Inference Cleanups:** Audit `AgentProxy` to confirm recursive types are strict and do not degrade into `any`.

### 3.3 `tui` (Input & Widths)
- **Task 1: Grapheme-Aware Widths:** Improve `getCharWidth()` to correctly calculate rendering widths for CJK characters, emoji, zero-width joiners, and combining marks.
- **Task 2: Input Protocol Coverage:** Extend `parseKey()` to gracefully support CSI-u (Kitty protocol) events and bracketed paste.

---

## 4. Execution Workflow

To maintain accountability, every task above will be executed using the following protocol:
1. **Track:** Create a Deciduous Action node for the specific task, parented to the overarching Code Review Goal (Node 280).
2. **Execute:** Perform the refactoring or review surgically. Add relevant tests.
3. **Validate:** Execute the package-specific test suites, linting, and type-checks to confirm resolution without regressions.
4. **Conclude:** Mark the Deciduous Action node as an Outcome and link PRs or git commits.